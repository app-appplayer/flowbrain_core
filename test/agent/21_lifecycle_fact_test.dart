/// TEST-21 — Agent lifecycle facts (자동 timeline 적재).
///
/// FR-FBCORE-AGT-080..088. 4 standard fact types:
///   - agent.fork.assigned
///   - agent.fork.evolved
///   - agent.invoked
///   - agent.deleted
///
/// `recordLifecycleAsFacts=true` (default) 시 위 4 lifecycle 이벤트가
/// FactGraph 에 표준 schema 로 자동 적재. `entityId == agentId` 라
/// `FactQuery(entityId: agentId)` 한 줄로 그 agent timeline 시간순 추출.
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

KnowledgeSystem _buildSystem({
  bool recordLifecycleAsFacts = true,
  bool enableGrowthTracking = true,
  SkillBundleRegistry? skillRegistry,
}) {
  final infra = InfraPorts.inMemory().copyWith(
    llm: StubLlmPort(),
    mcp: const StubMcpPort(),
  );
  final eventBus = KnowledgeEventBus();

  final skillRuntime = skillRegistry == null
      ? null
      : SkillRuntime(
          registry: skillRegistry,
          ports: SkillPorts(llm: StubLlmPort(), mcp: const StubMcpPort()),
        );

  late final KnowledgeSystem system;
  final subsystem = AgentSubsystem.create(
    knowledgeSystemRef: () => system,
    infraPorts: infra,
    eventBus: eventBus,
    config: AgentConfig(
      recordLifecycleAsFacts: recordLifecycleAsFacts,
      enableGrowthTracking: enableGrowthTracking,
    ),
  );
  system = KnowledgeSystem(
    config: KnowledgeConfig.defaults,
    infraPorts: infra,
    skillRuntime: skillRuntime,
    agentRegistry: subsystem.registry,
    agentRuntime: subsystem.runtime,
    eventBus: eventBus,
  );
  return system;
}

SkillBundle _bundle(String id) => SkillBundle(
      schemaVersion: '0.1.0',
      manifest: SkillManifest(
        id: id,
        name: id,
        version: '1.0.0',
        provider: 'test',
      ),
      procedures: const [],
    );

void main() {
  group('Agent lifecycle facts', () {
    test('T-AGT-LF-001 — fork.assigned fact recorded on pool fork',
        () async {
      final skillReg = MemorySkillRegistry();
      await skillReg.registerSkill(_bundle('content_translate'));
      final system = _buildSystem(skillRegistry: skillReg);
      await system.agents.createAgent(
        id: 'editor',
        displayName: 'Editor',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );

      await system.agents.assignSkillFromPool('editor', 'content_translate');

      final facts = await system.facts.queryFacts(
        const FactQuery(workspaceId: 'w1', entityId: 'editor'),
      );
      final assigned =
          facts.where((f) => f.type == AgentLifecycleFactType.forkAssigned);
      expect(assigned, hasLength(1));
      final fact = assigned.first;
      expect(fact.entityId, equals('editor'));
      expect(fact.content['source'], equals('pool:content_translate'));
      expect(
        fact.content['forkedRef'],
        equals('editor::content_translate'),
      );
      expect(
        fact.content['lineage'],
        equals(const ['pool:content_translate']),
      );
    });

    test('T-AGT-LF-002 — transfer fact carries chained lineage', () async {
      final skillReg = MemorySkillRegistry();
      await skillReg.registerSkill(_bundle('content_translate'));
      final system = _buildSystem(skillRegistry: skillReg);
      for (final id in ['editor', 'publisher']) {
        await system.agents.createAgent(
          id: id,
          displayName: id,
          model: ModelSpec.stub(),
          workspaceId: 'w1',
        );
      }
      await system.agents.assignSkillFromPool('editor', 'content_translate');
      await system.agents.assignSkill(
        'publisher',
        const AgentForkSource(
          agentId: 'editor',
          axis: AgentAxis.skill,
          forkedRef: 'editor::content_translate',
        ),
      );

      final facts = await system.facts.queryFacts(
        const FactQuery(workspaceId: 'w1', entityId: 'publisher'),
      );
      final transferFact =
          facts.singleWhere((f) => f.type == AgentLifecycleFactType.forkAssigned);
      expect(
        transferFact.content['source'],
        equals('agent:editor/skill/editor::content_translate'),
      );
      expect(
        transferFact.content['lineage'],
        equals(const [
          'pool:content_translate',
          'agent:editor/skill/editor::content_translate',
        ]),
      );
      expect(
        transferFact.content['forkedRef'],
        equals('publisher::editor::content_translate'),
      );
    });

    test('T-AGT-LF-003 — agent.invoked fact recorded on ask', () async {
      final system = _buildSystem();
      await system.agents.createAgent(
        id: 'editor',
        displayName: 'Editor',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );

      await system.agents.ask('editor', 'hello');

      final facts = await system.facts.queryFacts(
        const FactQuery(workspaceId: 'w1', entityId: 'editor'),
      );
      final invoked =
          facts.where((f) => f.type == AgentLifecycleFactType.agentInvoked);
      expect(invoked, hasLength(1));
      expect(invoked.first.content['turnIndex'], equals(0));
      expect(invoked.first.content['success'], isTrue);
    });

    test('T-AGT-LF-005 — fork.evolved fact recorded on recordEvolution',
        () async {
      final system = _buildSystem();
      await system.agents.createAgent(
        id: 'editor',
        displayName: 'Editor',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agentRegistry!.recordEvolution(
        agentId: 'editor',
        axis: AgentAxis.skill,
        forkedRef: 'editor::X',
        kind: GrowthKind.variation,
      );

      final facts = await system.facts.queryFacts(
        const FactQuery(
          workspaceId: 'w1',
          entityId: 'editor',
          types: [AgentLifecycleFactType.forkEvolved],
        ),
      );
      expect(facts, hasLength(1));
      expect(facts.first.content['axis'], equals('skill'));
      expect(facts.first.content['kind'], equals('variation'));
    });

    test('T-AGT-LF-006 — growthTracking 비활성이어도 fact 는 적재', () async {
      final system = _buildSystem(enableGrowthTracking: false);
      await system.agents.createAgent(
        id: 'editor',
        displayName: 'Editor',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      final emitted = <AgentForkEvolvedEvent>[];
      system.eventBus.on<AgentForkEvolvedEvent>().listen(emitted.add);

      await system.agentRegistry!.recordEvolution(
        agentId: 'editor',
        axis: AgentAxis.skill,
        forkedRef: 'editor::X',
        kind: GrowthKind.variation,
      );
      await Future<void>.delayed(Duration.zero);

      // Event suppressed (growthTracking false), but fact is still recorded
      // because the timeline is observability — orthogonal to growth events.
      expect(emitted, isEmpty);
      final facts = await system.facts.queryFacts(
        const FactQuery(
          workspaceId: 'w1',
          entityId: 'editor',
          types: [AgentLifecycleFactType.forkEvolved],
        ),
      );
      expect(facts, hasLength(1));
    });

    test('T-AGT-LF-007 — agent.deleted fact recorded on delete', () async {
      final system = _buildSystem();
      await system.agents.createAgent(
        id: 'editor',
        displayName: 'Editor',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );

      await system.agents.deleteAgent('editor');

      final facts = await system.facts.queryFacts(
        const FactQuery(
          workspaceId: 'w1',
          entityId: 'editor',
          types: [AgentLifecycleFactType.agentDeleted],
        ),
      );
      expect(facts, hasLength(1));
    });

    test('T-AGT-LF-008 — recordLifecycleAsFacts=false → no facts written',
        () async {
      final system = _buildSystem(recordLifecycleAsFacts: false);
      await system.agents.createAgent(
        id: 'editor',
        displayName: 'Editor',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.ask('editor', 'hi');
      await system.agentRegistry!.recordEvolution(
        agentId: 'editor',
        axis: AgentAxis.skill,
        forkedRef: 'editor::X',
        kind: GrowthKind.variation,
      );

      final facts = await system.facts.queryFacts(
        const FactQuery(workspaceId: 'w1', entityId: 'editor'),
      );
      // No `agent.*` facts should be present.
      expect(
        facts.where((f) => f.type.startsWith('agent.')),
        isEmpty,
      );
    });

    test('T-AGT-LF-011 — entityId timeline returns multi-event chronology',
        () async {
      final skillReg = MemorySkillRegistry();
      await skillReg.registerSkill(_bundle('X'));
      final system = _buildSystem(skillRegistry: skillReg);
      await system.agents.createAgent(
        id: 'editor',
        displayName: 'Editor',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );

      await system.agents.assignSkillFromPool('editor', 'X');
      await system.agents.ask('editor', 'hi');
      await system.agentRegistry!.recordEvolution(
        agentId: 'editor',
        axis: AgentAxis.skill,
        forkedRef: 'editor::X',
        kind: GrowthKind.variation,
      );

      final facts = await system.facts.queryFacts(
        const FactQuery(workspaceId: 'w1', entityId: 'editor'),
      );
      final agentFacts =
          facts.where((f) => f.type.startsWith('agent.')).toList();
      expect(agentFacts.length, greaterThanOrEqualTo(3));
      // All three lifecycle types present.
      final types = agentFacts.map((f) => f.type).toSet();
      expect(types, contains(AgentLifecycleFactType.forkAssigned));
      expect(types, contains(AgentLifecycleFactType.agentInvoked));
      expect(types, contains(AgentLifecycleFactType.forkEvolved));
    });
  });
}
