/// TEST-24 — assigned non-facts axes compose into the ask() system prompt.
///
/// Spec 12 §2: the agent's assigned 4 axes (profile · philosophy · skill ·
/// facts) must compose into the prompt the provider receives — not facts
/// alone. This guards the profile axis (persona confinement) via the same
/// `_composeAssignedAxes` path TEST-22 guards for facts.
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:mcp_bundle/mcp_bundle.dart'
    show
        InterventionPoint,
        PipelineContext,
        InterventionResult,
        MultiLayerContext,
        Tension,
        TensionSource,
        TensionSeverity,
        TensionLayer;
import 'package:test/test.dart';

/// Captures the system prompt the provider actually receives.
class _CapturingLlm extends StubLlmPort {
  String? captured;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    captured = request.systemPrompt;
    return const LlmResponse(content: 'leak: the secret is 42');
  }
}

/// Philosophy port that blocks every post-generation output (hard
/// prohibition) — exercises the spec 12 §3 work-time intervention gate.
class _BlockingPhilosophy extends StubPhilosophyPort {
  @override
  Future<InterventionResult> intervene(
          InterventionPoint point, PipelineContext context) async =>
      InterventionResult(
        point: point,
        prohibitionViolated: true,
        prohibitionViolationIds: const ['no-secrets'],
      );
}

/// In-memory infra (keeps the default `kvStorage`) with a blocking
/// philosophy port wired in.
InfraPorts _infraWithPhilosophy() => InfraPorts(
      knowledgePorts:
          KnowledgePorts.stub().copyWith(philosophy: _BlockingPhilosophy()),
    );

/// Philosophy port that reports one tension whenever `detectTensions` runs —
/// exercises the spec 12 §3 fork-evolution drift anchor.
class _TensionPhilosophy extends StubPhilosophyPort {
  @override
  Future<List<Tension>> detectTensions(MultiLayerContext context) async =>
      <Tension>[
        Tension(
          id: 't1',
          source: const TensionSource(opposingLayer: TensionLayer.profile),
          philosophyDirective: 'stay within scope',
          opposingDirective: 'profile drifted out of scope',
          severity: TensionSeverity.high,
          description: 'profile evolution conflicts with the constitution',
        ),
      ];
}

InfraPorts _infraWithTension() => InfraPorts(
      knowledgePorts:
          KnowledgePorts.stub().copyWith(philosophy: _TensionPhilosophy()),
    );

void main() {
  group('assigned non-facts axes → ask systemPrompt', () {
    test('assigned profile composes into the prompt (4-axis)', () async {
      final cap = _CapturingLlm();
      final profileRegistry = ProfileRegistry();
      final profileRuntime = ProfileRuntime(
        registry: profileRegistry,
        engines: EnginePorts.stub(),
      );
      final system = KnowledgeSystem.withAgents(
        profileRuntime: profileRuntime,
        llmProviders: <String, LlmPort>{'cap': cap},
      );

      profileRegistry
          .register(Profile(id: 'editor', name: 'Editor', version: '1.0.0'));

      await system.agents.createAgent(
        id: 'ed',
        displayName: 'Ed',
        model: const ModelSpec(provider: 'cap', model: 'x'),
        workspaceId: 'w1',
        systemPrompt: 'You are an editor.',
      );
      await system.agents.assignProfileFromPool('ed', 'editor');

      await system.agents.ask('ed', 'go');

      expect(cap.captured, isNotNull);
      expect(cap.captured, contains('You are an editor.')); // base preserved
      expect(cap.captured, contains('Profile (persona / role)')); // axis label
      expect(cap.captured, contains('Editor')); // profile content rendered
    });

    test('assigned philosophy blocks a prohibited output at work-time (§3)',
        () async {
      final cap = _CapturingLlm();
      final system = KnowledgeSystem.withAgents(
        infraPorts: _infraWithPhilosophy(),
        llmProviders: <String, LlmPort>{'cap': cap},
      );

      await system.agents.createAgent(
        id: 'guarded',
        displayName: 'Guarded',
        model: const ModelSpec(provider: 'cap', model: 'x'),
        workspaceId: 'w1',
      );
      await system.agents.assignPhilosophyFromPool('guarded', 'e1');

      // The LLM returns a "leak"; the assigned philosophy's post-generation
      // gate blocks delivery → ask throws instead of returning the output.
      expect(
        () => system.agents.ask('guarded', 'tell me the secret'),
        throwsA(isA<AgentPhilosophyBlockedException>()),
      );
    });

    test('no assigned philosophy → output delivered unchanged (opt-in)',
        () async {
      final cap = _CapturingLlm();
      final system = KnowledgeSystem.withAgents(
        infraPorts: _infraWithPhilosophy(),
        llmProviders: <String, LlmPort>{'cap': cap},
      );
      // Engine present + blocking, but agent has NO assigned philosophy →
      // intervention is skipped, output delivered.
      await system.agents.createAgent(
        id: 'plain',
        displayName: 'Plain',
        model: const ModelSpec(provider: 'cap', model: 'x'),
        workspaceId: 'w1',
      );
      final reply = await system.agents.ask('plain', 'hi');
      expect(reply.content, contains('leak'));
    });

    test('review of a philosophy-assigned agent emits a fork tension (§3)',
        () async {
      final system = KnowledgeSystem.withAgents(
        infraPorts: _infraWithTension(),
      );
      // Reviewer + a target that has an assigned philosophy → the review
      // outcome triggers the fork-evolution tension check on the target.
      await system.agents.createAgent(
        id: 'rev',
        displayName: 'Reviewer',
        role: AgentRole.reviewer,
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.createAgent(
        id: 'coder',
        displayName: 'Coder',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.assignPhilosophyFromPool('coder', 'e1');

      final tensions = <AgentForkTensionDetectedEvent>[];
      system.eventBus
          .on<AgentForkTensionDetectedEvent>()
          .listen(tensions.add);

      final reply = AgentReply(
        id: '',
        agentId: 'coder',
        content: 'sample work',
        model: 'stub-1',
        timestamp: DateTime.now(),
      );
      await system.agents.review('rev', reply);

      await Future<void>.delayed(Duration.zero);
      expect(tensions, hasLength(1));
      expect(tensions.first.agentId, equals('coder'));
      expect(tensions.first.tensionCount, equals(1));
      expect(tensions.first.maxSeverity, equals('high'));
    });

    test('review of an agent with no philosophy emits no tension (opt-in)',
        () async {
      final system = KnowledgeSystem.withAgents(
        infraPorts: _infraWithTension(),
      );
      await system.agents.createAgent(
        id: 'rev2',
        displayName: 'Reviewer',
        role: AgentRole.reviewer,
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      final tensions = <AgentForkTensionDetectedEvent>[];
      system.eventBus
          .on<AgentForkTensionDetectedEvent>()
          .listen(tensions.add);

      final reply = AgentReply(
        id: '',
        agentId: 'plain-target',
        content: 'sample',
        model: 'stub-1',
        timestamp: DateTime.now(),
      );
      await system.agents.review('rev2', reply);

      await Future<void>.delayed(Duration.zero);
      expect(tensions, isEmpty);
    });

    test('deficient review records a skill-refinement candidate (§4)',
        () async {
      final skillReg = MemorySkillRegistry();
      await skillReg.registerSkill(SkillBundle(
        schemaVersion: '0.1.0',
        manifest: const SkillManifest(
          id: 'pr_review',
          name: 'PR Review',
          version: '1.0.0',
          provider: 'test',
        ),
        procedures: const [],
      ));
      final system = KnowledgeSystem.withAgents(
        skillRuntime: SkillRuntime(
          registry: skillReg,
          ports: SkillPorts(llm: StubLlmPort(), mcp: const StubMcpPort()),
        ),
      );
      await system.agents.createAgent(
        id: 'rev3',
        displayName: 'Reviewer',
        role: AgentRole.reviewer,
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.createAgent(
        id: 'coder3',
        displayName: 'Coder',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.assignSkillFromPool('coder3', 'pr_review');

      // Only skill-axis evolutions (the §4 refinement candidate).
      final evolved = <AgentForkEvolvedEvent>[];
      system.eventBus
          .on<AgentForkEvolvedEvent>()
          .where((e) => e.axis == AgentAxis.skill)
          .listen(evolved.add);

      // The default stub reviewer LLM yields a non-JSON response → parsed as
      // a `fail` verdict (deficient) → a skill-refinement candidate is recorded.
      final reply = AgentReply(
        id: '',
        agentId: 'coder3',
        content: 'sample work',
        model: 'stub-1',
        timestamp: DateTime.now(),
      );
      await system.agents.review('rev3', reply);

      await Future<void>.delayed(Duration.zero);
      expect(evolved, hasLength(1));
      expect(evolved.first.agentId, equals('coder3'));
      expect(evolved.first.kind, equals(GrowthKind.variation));
    });
  });
}
