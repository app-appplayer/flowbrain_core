/// TEST-03 — KnowledgeConfig (MOD-CORE-003, flowbrain wrapper)
///
/// Verifies wrapper composition + AgentConfig sub-config + presets.
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('MOD-CORE-003 KnowledgeConfig', () {
    test('T-CFG-001 — defaults exposes default workspaceId + sub-configs',
        () {
      final config = KnowledgeConfig.defaults;
      expect(config.workspaceId, equals('default'));
      expect(config.factGraph, isA<FactGraphConfig>());
      expect(config.skill, isA<SkillConfig>());
      expect(config.profile, isA<ProfileConfig>());
      expect(config.pipeline, isA<PipelineConfig>());
      expect(config.scheduler, isA<SchedulerConfig>());
      expect(config.events, isA<EventConfig>());
      expect(config.logging, isA<LoggingConfig>());
      expect(config.features, isA<FeatureFlags>());
      expect(config.philosophy, isA<PhilosophyConfig>());
      expect(config.agent, isA<AgentConfig>());
    });

    test('T-CFG-002 — agent sub-config defaults', () {
      final agent = KnowledgeConfig.defaults.agent;
      expect(agent.forkPolicy, equals(ForkPolicy.eagerFull));
      expect(agent.conversationTtl, equals(const Duration(days: 30)));
      expect(agent.maxConversationTurns, equals(100));
      expect(agent.enableGrowthTracking, isTrue);
      expect(agent.enableManagerRouting, isTrue);
      expect(agent.enableReviewer, isTrue);
    });

    test('T-CFG-003 — development preset shortens TTL', () {
      final config = KnowledgeConfig.development;
      expect(config.agent.conversationTtl, equals(const Duration(days: 7)));
    });

    test('T-CFG-004 — production preset matches defaults agent', () {
      final config = KnowledgeConfig.production;
      expect(config.agent.forkPolicy, equals(ForkPolicy.eagerFull));
    });

    test('T-CFG-005 — copyWith updates workspaceId', () {
      final config = KnowledgeConfig.defaults.copyWith(workspaceId: 'team-x');
      expect(config.workspaceId, equals('team-x'));
    });

    test('T-CFG-006 — agent copyWith independent of base', () {
      final config = KnowledgeConfig.defaults.copyWith(
        agent: AgentConfig.defaults.copyWith(maxConversationTurns: 5),
      );
      expect(config.agent.maxConversationTurns, equals(5));
      expect(KnowledgeConfig.defaults.agent.maxConversationTurns,
          equals(100));
    });
  });
}
