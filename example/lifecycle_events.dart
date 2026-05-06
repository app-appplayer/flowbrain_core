/// FlowBrain — observe lifecycle via the broadcast event bus.
///
/// Every Knowledge / Agent operation that changes externally-visible
/// state emits a [KnowledgeEvent] on `system.eventBus`. This example
/// subscribes to the event stream and prints each event as it fires,
/// so you can see exactly what creating / asking / deleting an agent
/// triggers downstream.
///
/// Run:
///
///   dart run example/lifecycle_events.dart
library;

import 'dart:async';

import 'package:flowbrain_core/flowbrain_core.dart';

Future<void> main() async {
  final system = KnowledgeSystem.withAgents();

  // Subscribe to every KnowledgeEvent. The bus is broadcast — multiple
  // listeners are fine; cancel the subscription before shutting the
  // system down.
  final received = <String>[];
  final sub = system.eventBus.stream.listen((event) {
    received.add(event.type);
    print('event: ${event.type}'
        '  ·  ${event.timestamp.toIso8601String()}');
  });

  // Trigger a small lifecycle.
  await system.agents.createAgent(
    id: 'observer',
    displayName: 'Observer',
    role: AgentRole.worker,
    model: ModelSpec.stub(),
    workspaceId: 'events-demo',
  );
  await system.agents.ask('observer', 'What time is it?');
  await system.agents.deleteAgent('observer');

  // Allow microtasks to flush before tearing down.
  await Future<void>.delayed(const Duration(milliseconds: 10));

  print('---');
  print('${received.length} event(s) observed:');
  for (final type in received) {
    print('  - $type');
  }

  await sub.cancel();
  await system.shutdown();
}
