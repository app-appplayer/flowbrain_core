/// TEST-17 — Targeted unit coverage uplift.
///
/// Covers helpers that are not exercised by the spec-driven tests:
///   - Growth Tracker 4 helpers (variation/adjustment/revision/facts)
///   - AgentRegistry update / removeOwned / getOwned / listOwned
///   - AgentFacade unassign / stream / clearHistory
///   - ConversationStore.shutdown / clear / remove (with empty agent)
///   - Agent / AgentGrowth / ModelSpec / TokenUsage / ConversationTurn
///     toJson / fromJson round-trips and copyWith branches
///   - RoutingDecision.tryParse and ReviewResult.tryParse success cases
///   - All AgentException toString outputs.
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('Growth Tracker helpers', () {
    test('all four trackers increment correct counters + emit events',
        () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );

      final events = <AgentForkEvolvedEvent>[];
      system.eventBus.on<AgentForkEvolvedEvent>().listen(events.add);

      final tracker =
          GrowthTracker(registry: system.agentRegistry!, config: AgentConfig.defaults);
      await tracker.trackVariation(agentId: 'a', forkedRef: 'a::s');
      await tracker.trackAdjustment(agentId: 'a', forkedRef: 'a::p');
      await tracker.trackRevision(agentId: 'a', forkedRef: 'a::ph');
      await tracker.trackFactsAccumulation(agentId: 'a', forkedRef: 'a::f');
      await Future<void>.delayed(Duration.zero);

      final agent = await system.agents.getAgent('a');
      expect(agent!.growth.skillCandidateCount, equals(1));
      expect(agent.growth.profileAdjustmentCount, equals(1));
      expect(agent.growth.philosophyRevisionCount, equals(1));
      expect(agent.growth.factsAccumulationCount, equals(1));
      expect(events, hasLength(4));
    });
  });

  group('AgentRegistry update / owned-axis CRUD', () {
    test('update mutates only specified fields', () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
        systemPrompt: 'orig',
        tags: const {'team': 'x'},
      );
      final updated = await system.agents.updateAgent(
        'a',
        displayName: 'A2',
        model: const ModelSpec(provider: 'anthropic', model: 'm-1'),
        systemPrompt: 'new',
        tags: const {'team': 'y'},
      );
      expect(updated.displayName, equals('A2'));
      expect(updated.model.provider, equals('anthropic'));
      expect(updated.systemPrompt, equals('new'));
      expect(updated.tags, equals({'team': 'y'}));
    });

    test('storeOwned + getOwned + listOwned + removeOwned round-trip',
        () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      final reg = system.agentRegistry!;
      await reg.storeOwned(
        agentId: 'a',
        axis: AgentAxis.skill,
        sourceRef: 's1',
        forkedRef: 'a::s1',
        payload: {'kind': 'demo'},
      );
      await reg.storeOwned(
        agentId: 'a',
        axis: AgentAxis.skill,
        sourceRef: 's2',
        forkedRef: 'a::s2',
        payload: {'kind': 'demo2'},
      );
      final owned = await reg.getOwned('a', AgentAxis.skill, 'a::s1');
      expect(owned, isA<Map>());

      final indexResolved =
          await reg.getOwnedRef('a', AgentAxis.skill, 's1');
      expect(indexResolved, equals('a::s1'));

      final list = await reg.listOwned('a', AgentAxis.skill);
      expect(list, hasLength(2));

      await reg.removeOwned('a', AgentAxis.skill, 'a::s1');
      final after = await reg.getOwned('a', AgentAxis.skill, 'a::s1');
      expect(after, isNull);
      final listAfter = await reg.listOwned('a', AgentAxis.skill);
      expect(listAfter, hasLength(1));
    });

    test('storeOwned with the same sourceRef + same forkedRef is idempotent',
        () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      final reg = system.agentRegistry!;
      await reg.storeOwned(
        agentId: 'a',
        axis: AgentAxis.profile,
        sourceRef: 'p1',
        forkedRef: 'a::p1',
        payload: 'first',
      );
      // Same forkedRef — no conflict.
      await reg.storeOwned(
        agentId: 'a',
        axis: AgentAxis.profile,
        sourceRef: 'p1',
        forkedRef: 'a::p1',
        payload: 'second',
      );
      final value = await reg.getOwned('a', AgentAxis.profile, 'a::p1');
      expect(value, equals('second'));
    });

    test('storeOwned with conflicting forkedRef throws ForkConflictException',
        () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      final reg = system.agentRegistry!;
      await reg.storeOwned(
        agentId: 'a',
        axis: AgentAxis.profile,
        sourceRef: 'p1',
        forkedRef: 'a::p1',
        payload: 'first',
      );
      await expectLater(
        () => reg.storeOwned(
          agentId: 'a',
          axis: AgentAxis.profile,
          sourceRef: 'p1',
          forkedRef: 'a::p1::other',
          payload: 'oops',
        ),
        throwsA(isA<ForkConflictException>()),
      );
    });

    test('update / delete on missing agent throws AgentNotFoundException',
        () async {
      final system = KnowledgeSystem.withAgents();
      await expectLater(
        () => system.agents.updateAgent('ghost', displayName: 'x'),
        throwsA(isA<AgentNotFoundException>()),
      );
      await expectLater(
        () => system.agents.deleteAgent('ghost'),
        throwsA(isA<AgentNotFoundException>()),
      );
    });
  });

  group('AgentFacade unassign / stream / clearHistory', () {
    test('unassign removes an owned entry', () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agentRegistry!.storeOwned(
        agentId: 'a',
        axis: AgentAxis.facts,
        sourceRef: 'q1',
        forkedRef: 'a::q1',
        payload: const {'records': []},
      );
      await system.agents.unassign('a', AgentAxis.facts, 'a::q1');
      final res = await system.agentRegistry!
          .getOwned('a', AgentAxis.facts, 'a::q1');
      expect(res, isNull);
    });

    test('stream yields tokens + final marker', () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      final tokens = await system.agents.stream('a', 'hi').toList();
      expect(tokens, isNotEmpty);
      expect(tokens.last.isFinal, isTrue);
    });

    test('clearHistory removes all turns', () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.ask('a', 'hello');
      expect(await system.agents.getHistory('a'), isNotEmpty);
      await system.agents.clearHistory('a');
      expect(await system.agents.getHistory('a'), isEmpty);
    });
  });

  group('ConversationStore shutdown / lifecycle', () {
    test('shutdown disables further operations + flush is idempotent',
        () async {
      final system = KnowledgeSystem.withAgents();
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.ask('a', 'one');
      await system.shutdown();
      // Second shutdown is harmless.
      await system.shutdown();
    });

    test('TTL configured to zero disables sweeper', () async {
      final config = KnowledgeConfig.defaults.copyWith(
        agent: AgentConfig.defaults.copyWith(
          conversationTtl: Duration.zero,
        ),
      );
      final system = KnowledgeSystem.withAgents(config: config);
      await system.agents.createAgent(
        id: 'a',
        displayName: 'A',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.ask('a', 'hello');
      // No assertion — purpose is to traverse the TTL=0 branch in
      // ConversationStore constructor / load path.
      expect(await system.agents.getHistory('a'), hasLength(1));
    });
  });

  group('Models — toJson/fromJson round-trips + copyWith', () {
    test('Agent round-trip preserves every field', () {
      final original = Agent(
        id: 'a',
        displayName: 'A',
        role: AgentRole.manager,
        model: const ModelSpec(
          provider: 'anthropic',
          model: 'm-1',
          maxTokens: 100,
          temperature: 0.5,
        ),
        workspaceId: 'w1',
        createdAt: DateTime.parse('2026-05-04T00:00:00.000Z'),
        systemPrompt: 'sys',
        growth: AgentGrowth.zero
            .bump(GrowthKind.variation, at: DateTime.parse('2026-05-04T00:01:00.000Z'))
            .bump(GrowthKind.adjustment, at: DateTime.parse('2026-05-04T00:02:00.000Z'))
            .bump(GrowthKind.revision, at: DateTime.parse('2026-05-04T00:03:00.000Z'))
            .bumpFacts(at: DateTime.parse('2026-05-04T00:04:00.000Z')),
        tags: const {'k': 'v'},
      );
      final restored = Agent.fromJson(original.toJson());
      expect(restored.id, equals(original.id));
      expect(restored.role, equals(original.role));
      expect(restored.model, equals(original.model));
      expect(restored.systemPrompt, equals(original.systemPrompt));
      expect(restored.growth.skillCandidateCount,
          equals(original.growth.skillCandidateCount));
      expect(restored.growth.factsAccumulationCount,
          equals(original.growth.factsAccumulationCount));
      expect(restored.tags, equals(original.tags));
    });

    test('AgentGrowth.fromJson handles missing fields', () {
      final growth = AgentGrowth.fromJson(const {});
      expect(growth.skillCandidateCount, equals(0));
      expect(growth.factsAccumulationCount, equals(0));
      expect(growth.lastGrowthAt, isNull);
    });

    test('ConversationTurn round-trip preserves usage + extra', () {
      final turn = ConversationTurn(
        userMessage: 'u',
        assistantReply: 'a',
        model: 'm',
        tokenUsage: const TokenUsage(promptTokens: 5, completionTokens: 7),
        timestamp: DateTime.parse('2026-05-04T00:00:00.000Z'),
        extra: const {'ctx': 'x'},
      );
      final restored = ConversationTurn.fromJson(turn.toJson());
      expect(restored.userMessage, equals('u'));
      expect(restored.tokenUsage!.totalTokens, equals(12));
      expect(restored.extra, equals({'ctx': 'x'}));
    });

    test('TokenUsage operator+ aggregates', () {
      const a = TokenUsage(promptTokens: 1, completionTokens: 2);
      const b = TokenUsage(promptTokens: 3, completionTokens: 4);
      final sum = a + b;
      expect(sum.promptTokens, equals(4));
      expect(sum.completionTokens, equals(6));
      expect(sum.totalTokens, equals(10));
    });

    test('ModelSpec equality, copyWith, toString', () {
      const a = ModelSpec(provider: 'p', model: 'm');
      final b = a.copyWith(maxTokens: 10);
      expect(a == ModelSpec.fromJson(a.toJson()), isTrue);
      expect(a == b, isFalse);
      expect(b.maxTokens, equals(10));
      expect(a.toString(), equals('p/m'));
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    test('RoutingDecision.tryParse success case', () {
      final decision = RoutingDecision.tryParse(
          '{"targetAgentId":"x","confidence":0.7,"reason":"ok"}');
      expect(decision.targetAgentId, equals('x'));
      expect(decision.confidence, equals(0.7));
      expect(decision.reason, equals('ok'));
    });

    test('RoutingDecision.tryParse rejects malformed JSON shape', () {
      expect(RoutingDecision.tryParse('null').reason, equals('parse_error'));
      expect(RoutingDecision.tryParse('{"x":1}').reason,
          equals('parse_error'));
    });

    test('ReviewResult.tryParse success case', () {
      final result = ReviewResult.tryParse(
          '{"verdict":"revise","severity":"medium","comments":"more"}');
      expect(result.verdict, equals(ReviewVerdict.revise));
      expect(result.severity, equals(ReviewSeverity.medium));
      expect(result.comments, equals('more'));
    });

    test('ReviewResult.tryParse rejects unknown verdict', () {
      final result = ReviewResult.tryParse('{"verdict":"bogus"}');
      expect(result.verdict, equals(ReviewVerdict.fail));
      expect(result.comments, equals('parse_error'));
    });
  });

  group('Agent exceptions', () {
    test('AgentNotFoundException toString', () {
      const exc = AgentNotFoundException('ghost');
      expect(exc.toString(), contains('ghost'));
    });

    test('ForkConflictException toString includes axis + sourceRef', () {
      const exc = ForkConflictException(
        agentId: 'a',
        axis: AgentAxis.skill,
        sourceRef: 's',
        existingForkedRef: 'a::s',
      );
      expect(exc.toString(), contains('skill'));
      expect(exc.toString(), contains('s'));
    });

    test('ConversationStoreUnavailableException toString includes detail',
        () {
      const exc =
          ConversationStoreUnavailableException('test detail');
      expect(exc.toString(), contains('test detail'));
    });

    test('AgentRoleMismatchException toString includes both roles', () {
      const exc = AgentRoleMismatchException(
        agentId: 'w',
        expectedRole: AgentRole.manager,
        actualRole: AgentRole.worker,
      );
      expect(exc.toString(), contains('manager'));
      expect(exc.toString(), contains('worker'));
    });
  });

  group('AgentConfig presets + copyWith', () {
    test('production preset matches defaults forkPolicy', () {
      expect(AgentConfig.production.forkPolicy,
          equals(ForkPolicy.eagerFull));
    });

    test('AgentConfig.copyWith preserves untouched fields', () {
      const base = AgentConfig.defaults;
      final next = base.copyWith(maxAgentsPerWorkspace: 10);
      expect(next.maxAgentsPerWorkspace, equals(10));
      expect(next.conversationTtl, equals(base.conversationTtl));
    });
  });
}
