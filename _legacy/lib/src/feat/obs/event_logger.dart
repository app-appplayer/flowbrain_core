/// Observability binding that subscribes to [KnowledgeEventBus] and
/// dispatches events to configured exporters.
///
/// See DDD FEAT-OBS §5 for the full specification.
library;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:mcp_knowledge/mcp_knowledge.dart'
    show KnowledgeEventBus, KnowledgeEvent;

import 'exporter_factory.dart';

final _log = Logger('flowbrain.obs.event_logger');

/// Connects the event bus to one or more [Exporter] instances.
///
/// Use [ObservabilityBinding.start] to create and activate the binding.
class ObservabilityBinding {
  /// Active exporters receiving events and metrics.
  final List<Exporter> exporters;

  /// The knowledge event bus being observed.
  final KnowledgeEventBus eventBus;

  /// Internal subscription handle.
  StreamSubscription<KnowledgeEvent>? _eventSub;

  ObservabilityBinding({
    required this.exporters,
    required this.eventBus,
  });

  /// Create, wire, and start an [ObservabilityBinding].
  ///
  /// 1. Builds exporters from [config].
  /// 2. Starts each exporter (failures are logged but do not block).
  /// 3. Subscribes to [eventBus] and dispatches to all exporters.
  /// 4. Registers baseline metric series.
  static ObservabilityBinding start(
    ObservabilityConfig config,
    KnowledgeEventBus eventBus,
  ) {
    final exporters = ExporterFactory.build(config);
    final binding = ObservabilityBinding(
      exporters: exporters,
      eventBus: eventBus,
    );

    for (final e in exporters) {
      try {
        e.start();
      } catch (err) {
        _log.warning('Exporter start failed, skipping: $err');
      }
    }

    binding._eventSub = eventBus.stream.listen(binding._onEvent);
    binding._registerBaselineMetrics();

    return binding;
  }

  /// Dispatch a single event to all exporters, isolating failures.
  void _onEvent(KnowledgeEvent event) {
    for (final e in exporters) {
      try {
        e.emitEvent(event);
      } catch (err) {
        _log.fine('Exporter emitEvent failed (non-fatal): $err');
      }
    }
  }

  /// Prime exporters for the three baseline metric series.
  void _registerBaselineMetrics() {
    const baseline = [
      'flowbrain.llm.cost_usd',
      'flowbrain.knowledge.hit_rate',
      'flowbrain.philosophy.intervention_count',
    ];

    for (final name in baseline) {
      for (final e in exporters) {
        try {
          e.emitMetric(name, 0.0, {});
        } catch (err) {
          _log.fine('Baseline metric registration failed (non-fatal): $err');
        }
      }
    }
  }

  /// Cancel the event subscription and stop all exporters.
  Future<void> stop() async {
    await _eventSub?.cancel();
    _eventSub = null;

    for (final e in exporters) {
      try {
        await e.stop();
      } catch (err) {
        _log.warning('Exporter stop failed: $err');
      }
    }
  }
}
