/// Exporter factory and concrete exporter implementations per DDD FEAT-OBS §4.
///
/// Provides [ExporterFactory.build] to instantiate exporters from an
/// [ObservabilityConfig]. Concrete implementations:
///
///   - [StructuredLogExporter] — structured JSON logging (P0).
///   - [PrometheusExporter]    — Prometheus `/metrics` endpoint stub (P1).
///   - [OtelExporter]          — OpenTelemetry gRPC/HTTP stub (P1).
library;

import 'package:logging/logging.dart';
import 'package:mcp_knowledge/mcp_knowledge.dart' show KnowledgeEvent;

final _log = Logger('flowbrain.obs.exporter');

/// Configuration for the observability subsystem.
class ObservabilityConfig {
  /// List of exporter names to activate (e.g. ['log', 'prometheus']).
  final List<String> exporters;

  /// Optional Prometheus endpoint port.
  final int? prometheusPort;

  /// Optional OTel collector URL.
  final String? otelCollectorUrl;

  const ObservabilityConfig({
    this.exporters = const ['log'],
    this.prometheusPort,
    this.otelCollectorUrl,
  });
}

/// Abstract exporter contract.
abstract class Exporter {
  /// Initialize the exporter (open connections, etc.).
  Future<void> start();

  /// Gracefully shut down.
  Future<void> stop();

  /// Emit a numeric metric.
  void emitMetric(String name, double value, Map<String, String> labels);

  /// Emit a knowledge event.
  void emitEvent(KnowledgeEvent event);
}

/// Factory that builds a list of [Exporter] instances from config.
class ExporterFactory {
  /// Build exporters according to [config.exporters].
  ///
  /// Throws [ArgumentError] for unknown exporter names.
  static List<Exporter> build(ObservabilityConfig config) {
    return config.exporters.map((name) {
      return switch (name) {
        'log' => StructuredLogExporter(),
        'prometheus' => PrometheusExporter(port: config.prometheusPort ?? 9090),
        'otel' =>
          OtelExporter(collectorUrl: config.otelCollectorUrl ?? 'localhost:4317'),
        _ => throw ArgumentError('Unknown exporter: $name'),
      };
    }).toList();
  }
}

// ---------------------------------------------------------------------------
// Concrete exporters
// ---------------------------------------------------------------------------

/// Structured JSON log exporter (P0 — fully implemented).
class StructuredLogExporter extends Exporter {
  final Logger _logger = Logger('flowbrain.obs.log_exporter');

  @override
  Future<void> start() async {
    _logger.info('StructuredLogExporter started');
  }

  @override
  Future<void> stop() async {
    _logger.info('StructuredLogExporter stopped');
  }

  @override
  void emitMetric(String name, double value, Map<String, String> labels) {
    _logger.info(
      '{"metric":"$name","value":$value,"labels":$labels}',
    );
  }

  @override
  void emitEvent(KnowledgeEvent event) {
    _logger.info(
      '{"event":"${event.type}","timestamp":"${event.timestamp.toIso8601String()}"}',
    );
  }
}

/// Prometheus exporter stub (P1 — will expose HTTP `/metrics` endpoint).
class PrometheusExporter extends Exporter {
  /// Port for the metrics HTTP server.
  final int port;

  PrometheusExporter({this.port = 9090});

  @override
  Future<void> start() async {
    // P1: Start HTTP server on [port] exposing /metrics.
    _log.info('PrometheusExporter stub started (port=$port)');
  }

  @override
  Future<void> stop() async {
    _log.info('PrometheusExporter stub stopped');
  }

  @override
  void emitMetric(String name, double value, Map<String, String> labels) {
    // P1: Accumulate in Prometheus registry.
  }

  @override
  void emitEvent(KnowledgeEvent event) {
    // P1: Translate event to Prometheus counter/histogram.
  }
}

/// OpenTelemetry exporter stub (P1 — will push via gRPC/HTTP).
class OtelExporter extends Exporter {
  /// Collector endpoint URL.
  final String collectorUrl;

  OtelExporter({this.collectorUrl = 'localhost:4317'});

  @override
  Future<void> start() async {
    // P1: Initialize OTel SDK and connect to collector.
    _log.info('OtelExporter stub started (collector=$collectorUrl)');
  }

  @override
  Future<void> stop() async {
    _log.info('OtelExporter stub stopped');
  }

  @override
  void emitMetric(String name, double value, Map<String, String> labels) {
    // P1: Send metric via OTel data model.
  }

  @override
  void emitEvent(KnowledgeEvent event) {
    // P1: Send event as OTel span/log.
  }
}
