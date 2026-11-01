/// TEST-25 — an agent reads from and writes to the host's knowledge store
/// through two ports (platform spec 30 §5.1).
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:mcp_bundle/mcp_bundle.dart'
    show
        Ethos,
        EthosMetadata,
        EvolutionProposal,
        FactRecord,
        FeedbackEvent,
        ValuePriority;
import 'package:test/test.dart';

/// Echoes nothing useful but remembers what it was asked with.
class _Llm extends StubLlmPort {
  _Llm([this.reply = 'the answer']);
  String reply;
  String? system;
  String? prompt;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    system = request.systemPrompt;
    prompt = request.prompt ?? request.messages?.last.content;
    return LlmResponse(content: reply);
  }
}

class _Context implements AgentContextPort {
  _Context(this.text, [this.factIds = const []]);
  final String? text;
  final List<String> factIds;
  final asked = <(String, String)>[];
  DateTime? lastAsOf;
  String? lastWorkspace;

  @override
  Future<AgentContext?> contextFor(String agentId, String request,
      {String? workspaceId, DateTime? asOf}) async {
    asked.add((agentId, request));
    lastAsOf = asOf;
    lastWorkspace = workspaceId;
    final t = text;
    return t == null ? null : AgentContext(text: t, factIds: factIds);
  }
}

class _BrokenContext implements AgentContextPort {
  @override
  Future<AgentContext?> contextFor(String agentId, String request,
          {String? workspaceId, DateTime? asOf}) =>
      throw StateError('store is down');
}

class _Outputs implements AgentOutputPort {
  final recorded = <AgentOutput>[];
  @override
  Future<void> record(AgentOutput output) async => recorded.add(output);
}

class _BrokenOutputs implements AgentOutputPort {
  @override
  Future<void> record(AgentOutput output) => throw StateError('disk full');
}

/// A philosophy with two values that keeps the feedback it is given.
class _Philosophy extends StubPhilosophyPort {
  final events = <FeedbackEvent>[];

  @override
  Future<Ethos> getEthos() async {
    final now = DateTime.now();
    return Ethos(
      id: 'e1',
      name: 'E',
      valuePriorities: const [
        ValuePriority(
            id: 'safety',
            rank: 1,
            higherValue: 'safety',
            lowerValue: 'speed',
            rationale: 'r'),
        ValuePriority(
            id: 'honesty',
            rank: 2,
            higherValue: 'honesty',
            lowerValue: 'comfort',
            rationale: 'r'),
      ],
      prohibitions: const [],
      metadata: EthosMetadata(version: '1', createdAt: now, updatedAt: now),
    );
  }

  @override
  Future<EvolutionProposal?> proposeFeedback(FeedbackEvent event) async {
    events.add(event);
    return null;
  }
}

KnowledgeSystem _system(
  _Llm llm, {
  AgentContextPort? context,
  AgentOutputPort? outputs,
  StubPhilosophyPort? philosophy,
}) =>
    KnowledgeSystem.withAgents(
      config: KnowledgeConfig.withPhilosophyEvolution,
      infraPorts: InfraPorts(
        knowledgePorts: philosophy == null
            ? KnowledgePorts.stub()
            : KnowledgePorts.stub().copyWith(philosophy: philosophy),
        agentContext: context,
        agentOutputs: outputs,
      ),
      llmProviders: <String, LlmPort>{'m': llm},
    );

const _model = ModelSpec(provider: 'm', model: 'x');

Future<void> _agent(KnowledgeSystem s, String id,
        {AgentRole role = AgentRole.worker, String? prompt}) =>
    s.agents.createAgent(
      id: id,
      displayName: id,
      role: role,
      model: _model,
      workspaceId: 'w',
      systemPrompt: prompt,
    );

void main() {
  group('reading: the host\'s store gives an agent its context', () {
    test('what the store holds reaches the system prompt, after a reset',
        () async {
      final llm = _Llm();
      final ctx = _Context('## Where the work stands\n- [task] finish step 3');
      final s = _system(llm, context: ctx);
      await _agent(s, 'a', prompt: 'You are A.');

      await s.agents.ask('a', 'first');
      await s.agents.ask('a', 'continue', resetContext: true);

      expect(llm.system, contains('You are A.'));
      expect(llm.system, contains('[task] finish step 3'));
      expect(ctx.asked.last, ('a', 'continue'));
    });

    test('the facts the store gave are on the record of what was produced',
        () async {
      final out = _Outputs();
      final s = _system(_Llm(),
          context: _Context('state', const ['fact-7', 'fact-9']),
          outputs: out);
      await _agent(s, 'a');
      await s.agents.ask('a', 'go');
      expect(out.recorded.single.factIds, ['fact-7', 'fact-9']);
    });

    test('a re-interpretation asks the store for that instant and says so '
        'on the record', () async {
      final ctx = _Context('state');
      final out = _Outputs();
      final s = _system(_Llm(), context: ctx, outputs: out);
      await _agent(s, 'a');
      final at = DateTime.utc(2026, 10, 1, 12);
      await s.agents.ask('a', 'go', asOf: at);
      expect(ctx.lastAsOf, at);
      expect(out.recorded.single.extra['asOf'], at.toIso8601String());

      await s.agents.ask('a', 'again');
      expect(ctx.lastAsOf, isNull);
      expect(out.recorded.last.extra.containsKey('asOf'), isFalse);
    });

    test('the store is told the agent\'s workspace, and the record carries it',
        () async {
      final ctx = _Context('state');
      final out = _Outputs();
      final s = _system(_Llm(), context: ctx, outputs: out);
      await _agent(s, 'a');
      await s.agents.ask('a', 'go');
      expect(ctx.lastWorkspace, 'w');
      expect(out.recorded.single.workspaceId, 'w');
    });

    test('an agent called from a flow step records which step', () async {
      final out = _Outputs();
      final s = _system(_Llm(), outputs: out);
      await _agent(s, 'a');
      await FlowStepRef.run(
        const FlowStepRef(
            kind: 'workflow', flowId: 'wf1', runId: 'r1', stepId: 'draft'),
        () => s.agents.ask('a', 'in the flow'),
      );
      await s.agents.ask('a', 'outside');

      expect(out.recorded.first.flow!.toJson(), {
        'kind': 'workflow',
        'flowId': 'wf1',
        'runId': 'r1',
        'stepId': 'draft',
      });
      expect(out.recorded.last.flow, isNull);
    });

    test('with no port, or nothing stored, the prompt is as it was', () async {
      final llm = _Llm();
      final s1 = _system(llm);
      await _agent(s1, 'a', prompt: 'You are A.');
      await s1.agents.ask('a', 'x');
      expect(llm.system, 'You are A.');

      final s2 = _system(llm, context: _Context(null));
      await _agent(s2, 'a', prompt: 'You are A.');
      await s2.agents.ask('a', 'x');
      expect(llm.system, 'You are A.');
    });

    test('a store that cannot answer fails the call instead of answering '
        'without the state', () async {
      final llm = _Llm();
      final s = _system(llm, context: _BrokenContext());
      await _agent(s, 'a');
      await expectLater(s.agents.ask('a', 'x'), throwsStateError);
      expect(llm.prompt, isNull, reason: 'the model was never called');
    });
  });

  group('writing: what an agent produced goes down as evidence', () {
    test('an answer is recorded with its request, model and the facts read',
        () async {
      final llm = _Llm('forty-two');
      final out = _Outputs();
      final s = _system(llm, outputs: out);
      await _agent(s, 'a');
      await s.agents.assignFacts(
        'a',
        FactQuery(workspaceId: 'w'),
      );
      await s.facts.writeFacts([
        FactRecord(
          id: 'f1',
          workspaceId: 'w',
          type: 'note',
          content: const {'text': 'the sky is blue'},
          createdAt: DateTime.now(),
        ),
      ]);
      await s.agents.assignFacts('a', FactQuery(workspaceId: 'w'));

      final reply = await s.agents.ask('a', 'what is the answer?');

      expect(reply.content, 'forty-two');
      final o = out.recorded.single;
      expect(o.kind, 'ask');
      expect(o.agentId, 'a');
      expect(o.request, 'what is the answer?');
      expect(o.content, 'forty-two');
      expect(o.model, 'x');
      expect(o.factIds, contains('f1'));
    });

    test('the lens it worked through is on the record', () async {
      final llm = _Llm();
      final out = _Outputs();
      final profiles = ProfileRegistry();
      final s = KnowledgeSystem.withAgents(
        profileRuntime:
            ProfileRuntime(registry: profiles, engines: EnginePorts.stub()),
        infraPorts: InfraPorts(
          knowledgePorts: KnowledgePorts.stub(),
          agentOutputs: out,
        ),
        llmProviders: <String, LlmPort>{'m': llm},
      );
      profiles.register(Profile(id: 'p1', name: 'P', version: '1.0.0'));
      await _agent(s, 'a');
      await s.agents.assignProfileFromPool('a', 'p1');

      await s.agents.ask('a', 'go');

      expect(out.recorded.single.lens['profile'], isNotEmpty);
    });

    test('a review and a routing decision are recorded too', () async {
      final llm = _Llm('{"verdict":"pass","comments":"fine"}');
      final out = _Outputs();
      final s = _system(llm, outputs: out);
      await _agent(s, 'rev', role: AgentRole.reviewer);
      await _agent(s, 'w');
      await s.agents.review(
        'rev',
        AgentReply(
            id: '', agentId: 'w', content: 'work', model: 'x',
            timestamp: DateTime.now()),
      );
      final review = out.recorded.single;
      expect(review.kind, 'review');
      expect(review.agentId, 'rev');
      expect(review.request, 'work');
      expect(review.content, contains('"verdict":"pass"'));
      expect(review.extra['targetAgentId'], 'w');

      out.recorded.clear();
      llm.reply = '{"targetAgentId":"w","confidence":0.9,"reason":"fits"}';
      await _agent(s, 'mgr', role: AgentRole.manager);
      await s.agents.route('mgr', 'do the thing', candidateAgentIds: ['w']);
      final route = out.recorded.single;
      expect(route.kind, 'route');
      expect(route.content, contains('"targetAgentId":"w"'));
    });

    test('a port that fails costs the agent nothing but an event', () async {
      final llm = _Llm('still answered');
      final s = _system(llm, outputs: _BrokenOutputs());
      await _agent(s, 'a');
      final failures = <AgentOutputFailedEvent>[];
      s.eventBus.on<AgentOutputFailedEvent>().listen(failures.add);

      final reply = await s.agents.ask('a', 'x');
      await Future<void>.delayed(Duration.zero);

      expect(reply.content, 'still answered');
      expect(failures.single.kind, 'ask');
      expect(failures.single.error, contains('disk full'));
    });

    test('an empty answer is not recorded', () async {
      final out = _Outputs();
      final s = _system(_Llm(''), outputs: out);
      await _agent(s, 'a');
      await s.agents.ask('a', 'x');
      expect(out.recorded, isEmpty);
    });
  });

  group('review → value', () {
    Future<(KnowledgeSystem, _Philosophy, _Llm)> setup(String reply) async {
      final llm = _Llm(reply);
      final phil = _Philosophy();
      final s = _system(llm, philosophy: phil);
      await _agent(s, 'rev', role: AgentRole.reviewer);
      await _agent(s, 'w');
      await s.agents.assignPhilosophyFromPool('w', 'e1');
      return (s, phil, llm);
    }

    AgentReply reply() => AgentReply(
        id: '', agentId: 'w', content: 'work', model: 'x',
        timestamp: DateTime.now());

    test('the reviewer is offered the values and the one it names carries '
        'the feedback', () async {
      final (s, phil, llm) = await setup(
          '{"verdict":"fail","severity":"high","comments":"c",'
          '"valuePriorityId":"safety"}');
      await s.agents.review('rev', reply());

      expect(llm.prompt, contains('safety: safety over speed'));
      expect(llm.prompt, contains('honesty: honesty over comfort'));
      expect(phil.events.single.valuePriorityId, 'safety');
      expect(llm.prompt, contains('"valueEffect"'));
    });

    test('a work that fell short of a value strengthens that value; one '
        'that followed it at too high a price weakens it', () async {
      Future<FeedbackEvent> run(String json) async {
        final (s, phil, _) = await setup(json);
        await s.agents.review('rev', reply());
        return phil.events.single;
      }

      final short = await run('{"verdict":"fail","valuePriorityId":"honesty",'
          '"valueEffect":"violated"}');
      expect(short.valuePriorityId, 'honesty');
      expect(short.outcomeScore, 1.0,
          reason: 'a violated honesty is not a case against honesty');

      final unspecified =
          await run('{"verdict":"fail","valuePriorityId":"honesty"}');
      expect(unspecified.outcomeScore, 1.0, reason: 'read as fell short');

      final costly = await run('{"verdict":"fail","valuePriorityId":"safety",'
          '"valueEffect":"overapplied"}');
      expect(costly.outcomeScore, -1.0);

      final mixed =
          await run('{"verdict":"revise","valuePriorityId":"safety"}');
      expect(mixed.outcomeScore, 0.0);

      final coarse = await run('{"verdict":"fail"}');
      expect(coarse.valuePriorityId, isNull);
      expect(coarse.outcomeScore, -1.0,
          reason: 'no value named: the coarse signal as before');
    });

    test('a value the philosophy does not have is dropped', () async {
      final (s, phil, _) = await setup(
          '{"verdict":"fail","comments":"c","valuePriorityId":"made-up"}');
      await s.agents.review('rev', reply());
      expect(phil.events.single.valuePriorityId, isNull);
    });

    test('a target with no philosophy gets the review as before', () async {
      final llm = _Llm('{"verdict":"pass"}');
      final s = _system(llm, philosophy: _Philosophy());
      await _agent(s, 'rev', role: AgentRole.reviewer);
      await _agent(s, 'w');
      await s.agents.review('rev', reply());
      expect(llm.prompt, isNot(contains('Values the work answers to')));
    });
  });
}
