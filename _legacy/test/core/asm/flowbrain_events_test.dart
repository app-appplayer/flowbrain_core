/// Tests for FlowBrain-specific events per SDD §5.4.
library;

import 'package:test/test.dart';
import 'package:mcp_knowledge/mcp_knowledge.dart' show KnowledgeEvent;
import 'package:flowbrain_core/src/events/flowbrain_events.dart';

void main() {
  final now = DateTime(2026, 4, 11, 12, 0, 0);

  group('FlowBrain events', () {
    test('AgentResolvedEvent implements KnowledgeEvent', () {
      final event = AgentResolvedEvent(
        agentId: 'agent-1',
        request: 'hello',
        timestamp: now,
      );
      expect(event, isA<KnowledgeEvent>());
      expect(event.type, 'agent_resolved');
      expect(event.agentId, 'agent-1');
      expect(event.request, 'hello');
      expect(event.timestamp, now);
    });

    test('AgentAskStartedEvent implements KnowledgeEvent', () {
      final event = AgentAskStartedEvent(
        agentId: 'agent-1',
        request: 'question',
        traceId: 'trace-123',
        timestamp: now,
      );
      expect(event, isA<KnowledgeEvent>());
      expect(event.type, 'agent_ask_started');
      expect(event.agentId, 'agent-1');
      expect(event.traceId, 'trace-123');
    });

    test('AgentAskCompletedEvent implements KnowledgeEvent', () {
      final event = AgentAskCompletedEvent(
        agentId: 'agent-1',
        traceId: 'trace-123',
        duration: const Duration(milliseconds: 500),
        success: true,
        timestamp: now,
      );
      expect(event, isA<KnowledgeEvent>());
      expect(event.type, 'agent_ask_completed');
      expect(event.duration, const Duration(milliseconds: 500));
      expect(event.success, isTrue);
    });

    test('KflEscalationEvent implements KnowledgeEvent', () {
      final event = KflEscalationEvent(
        tier: 'partial',
        confidence: 0.6,
        failed: false,
        timestamp: now,
      );
      expect(event, isA<KnowledgeEvent>());
      expect(event.type, 'kfl_escalation');
      expect(event.tier, 'partial');
      expect(event.confidence, 0.6);
      expect(event.failed, isFalse);
    });

    test('ConfigReloadedEvent implements KnowledgeEvent', () {
      final event = ConfigReloadedEvent(
        sections: ['agents', 'bundles'],
        timestamp: now,
      );
      expect(event, isA<KnowledgeEvent>());
      expect(event.type, 'config_reloaded');
      expect(event.sections, ['agents', 'bundles']);
    });

    test('BundleRolledBackEvent implements KnowledgeEvent', () {
      final event = BundleRolledBackEvent(
        bundleId: 'bundle-x',
        reason: 'integrity check failed',
        timestamp: now,
      );
      expect(event, isA<KnowledgeEvent>());
      expect(event.type, 'bundle_rolled_back');
      expect(event.bundleId, 'bundle-x');
      expect(event.reason, 'integrity check failed');
    });

    test('CostThresholdExceededEvent implements KnowledgeEvent', () {
      final event = CostThresholdExceededEvent(
        todayUsd: 12.50,
        threshold: 10.0,
        timestamp: now,
      );
      expect(event, isA<KnowledgeEvent>());
      expect(event.type, 'cost_threshold_exceeded');
      expect(event.todayUsd, 12.50);
      expect(event.threshold, 10.0);
    });

    test('AgentAskStartedEvent allows null agentId', () {
      final event = AgentAskStartedEvent(
        request: 'question',
        traceId: 'trace-456',
        timestamp: now,
      );
      expect(event.agentId, isNull);
      expect(event.type, 'agent_ask_started');
    });

    test('ConfigReloadFailedEvent implements KnowledgeEvent', () {
      final event = ConfigReloadFailedEvent(
        error: 'parse failed',
        sections: ['agents'],
        timestamp: now,
      );
      expect(event, isA<KnowledgeEvent>());
      expect(event.type, 'config_reload_failed');
      expect(event.error, 'parse failed');
      expect(event.sections, ['agents']);
    });

    test('all 8 event types have distinct type fields', () {
      final events = <KnowledgeEvent>[
        AgentResolvedEvent(agentId: 'a', request: 'r', timestamp: now),
        AgentAskStartedEvent(request: 'r', traceId: 't', timestamp: now),
        AgentAskCompletedEvent(agentId: 'a', traceId: 't', duration: Duration.zero, success: true, timestamp: now),
        KflEscalationEvent(tier: 'miss', confidence: 0.0, timestamp: now),
        ConfigReloadedEvent(sections: [], timestamp: now),
        ConfigReloadFailedEvent(error: 'err', timestamp: now),
        BundleRolledBackEvent(bundleId: 'b', reason: '', timestamp: now),
        CostThresholdExceededEvent(todayUsd: 0, threshold: 0, timestamp: now),
      ];

      final types = events.map((e) => e.type).toSet();
      expect(types.length, 8, reason: 'all 8 events should have unique type identifiers');
    });
  });
}
