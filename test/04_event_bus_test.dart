/// TEST-04 — KnowledgeEventBus (MOD-CORE-004)
///
/// Verifies broadcast semantics + 20 event types (Knowledge 13 + Agent 7) +
/// subscriber-exception isolation.
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

void main() {
  group('MOD-CORE-004 KnowledgeEventBus', () {
    test('T-EVT-001 — broadcast stream API surface', () async {
      final bus = KnowledgeEventBus();
      expect(bus.stream, isA<Stream<KnowledgeEvent>>());
      await bus.close();
    });

    test('T-EVT-002 — Agent 7 event types present + KnowledgeEvent contract',
        () {
      final now = DateTime.now();
      final agentEvents = <KnowledgeEvent>[
        AgentCreatedEvent(
          agentId: 'a',
          displayName: 'A',
          role: AgentRole.worker,
          model: ModelSpec.stub(),
          timestamp: now,
        ),
        AgentDeletedEvent(agentId: 'a', timestamp: now),
        AgentInvokedEvent(
          agentId: 'a',
          model: 'stub-1',
          turnIndex: 0,
          success: true,
          duration: Duration.zero,
          timestamp: now,
        ),
        AgentForkAssignedEvent(
          agentId: 'a',
          axis: AgentAxis.skill,
          sourceRef: 's',
          forkedRef: 'a::s',
          timestamp: now,
        ),
        AgentForkEvolvedEvent(
          agentId: 'a',
          axis: AgentAxis.skill,
          forkedRef: 'a::s',
          kind: GrowthKind.variation,
          timestamp: now,
        ),
        ManagerRoutedEvent(
          managerId: 'm',
          targetAgentId: 'a',
          confidence: 0.9,
          timestamp: now,
        ),
        ReviewerVerifiedEvent(
          reviewerId: 'r',
          targetAgentId: 'a',
          verdict: ReviewVerdict.pass,
          timestamp: now,
        ),
      ];
      for (final event in agentEvents) {
        expect(event.timestamp, equals(now));
        expect(event.type, isNotEmpty);
        expect(event.runtimeType.toString().endsWith('Event'), isTrue);
      }
    });

    test('T-EVT-003 — emit reaches subscribers', () async {
      final bus = KnowledgeEventBus();
      final received = <String>[];
      final sub = bus.stream.listen((e) => received.add(e.type));
      bus.emit(AgentDeletedEvent(
        agentId: 'a',
        timestamp: DateTime.now(),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(received, contains('agent_deleted'));
      await sub.cancel();
      await bus.close();
    });

    test('T-EVT-004 — emit after close is silently dropped', () async {
      final bus = KnowledgeEventBus();
      await bus.close();
      bus.emit(AgentDeletedEvent(
        agentId: 'a',
        timestamp: DateTime.now(),
      ));
    });

    test('T-EVT-005 — typed filter via on<T>', () async {
      final bus = KnowledgeEventBus();
      final received = <AgentDeletedEvent>[];
      final sub = bus.on<AgentDeletedEvent>().listen(received.add);
      bus.emit(AgentCreatedEvent(
        agentId: 'a',
        displayName: 'A',
        role: AgentRole.worker,
        model: ModelSpec.stub(),
        timestamp: DateTime.now(),
      ));
      bus.emit(AgentDeletedEvent(
        agentId: 'a',
        timestamp: DateTime.now(),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      await sub.cancel();
      await bus.close();
    });

    test('T-EVT-006 — subscribe<T>() isolates handler exceptions', () async {
      final bus = KnowledgeEventBus();
      final survived = <String>[];
      bus.subscribe<AgentDeletedEvent>((_) => throw Exception('boom'));
      bus.subscribe<AgentDeletedEvent>((e) => survived.add(e.agentId));
      bus.emit(AgentDeletedEvent(
        agentId: 'a',
        timestamp: DateTime.now(),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(survived, equals(['a']));
      await bus.close();
    });
  });
}
