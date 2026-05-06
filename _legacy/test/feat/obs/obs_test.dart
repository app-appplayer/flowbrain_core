import 'dart:async';

import 'package:test/test.dart';
import 'package:mcp_bundle/mcp_bundle.dart'
    show
        LlmPort,
        LlmRequest,
        LlmResponse,
        LlmUsage,
        LlmCapabilities,
        StubMetricPort;
import 'package:mcp_knowledge/mcp_knowledge.dart'
    show KnowledgeEventBus, KnowledgeEvent;

import 'package:flowbrain_core/src/feat/obs/cost_tracking_decorator.dart';
import 'package:flowbrain_core/src/feat/obs/exporter_factory.dart';
import 'package:flowbrain_core/src/feat/obs/event_logger.dart';
import 'package:flowbrain_core/src/events/flowbrain_events.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

class _MockLlmPort extends LlmPort {
  final List<LlmRequest> calls = [];
  LlmResponse nextResponse;

  _MockLlmPort({LlmResponse? response})
      : nextResponse = response ??
            const LlmResponse(
              content: 'response',
              usage: LlmUsage(inputTokens: 100, outputTokens: 50),
              model: 'claude-sonnet',
            );

  @override
  LlmCapabilities get capabilities => const LlmCapabilities.minimal();

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    calls.add(request);
    return nextResponse;
  }
}

class _RecordingMetricPort extends StubMetricPort {
  final List<({String name, double value, Map<String, String>? tags})>
      recorded = [];

  @override
  Future<void> record(
    String metricName,
    double value, {
    Map<String, String>? tags,
  }) async {
    recorded.add((name: metricName, value: value, tags: tags));
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CostCalculator', () {
    test('estimates USD from tokens and model pricing', () {
      final calc = CostCalculator();
      final usd = calc.estimate(
        model: 'claude-sonnet',
        promptTokens: 1000,
        completionTokens: 500,
      );
      expect(usd, greaterThan(0));
    });

    test('returns default price for unknown model', () {
      final calc = CostCalculator();
      final usd = calc.estimate(
        model: 'unknown-model',
        promptTokens: 1000,
        completionTokens: 500,
      );
      expect(usd, greaterThan(0));
    });

    test('custom pricing map is respected', () {
      final calc = CostCalculator(
        pricing: {
          'my-model': ModelPricing(
            inputPerMillion: 10.0,
            outputPerMillion: 20.0,
          ),
        },
      );
      final usd = calc.estimate(
        model: 'my-model',
        promptTokens: 1000000,
        completionTokens: 1000000,
      );
      expect(usd, closeTo(30.0, 0.01));
    });
  });

  group('CostTrackingLlmDecorator', () {
    test('delegates complete to inner and tracks cost', () async {
      final inner = _MockLlmPort();
      final metrics = _RecordingMetricPort();

      final decorator = CostTrackingLlmDecorator(
        inner: inner,
        metrics: metrics,
        calculator: CostCalculator(),
      );

      final response =
          await decorator.complete(LlmRequest.simple('test'));

      expect(response.content, 'response');
      expect(inner.calls.length, 1);

      // Should have recorded cost and token metrics
      final costRecords =
          metrics.recorded.where((m) => m.name == 'flowbrain.llm.cost_usd');
      expect(costRecords, isNotEmpty);

      final promptTokenRecords = metrics.recorded
          .where((m) => m.name == 'flowbrain.llm.prompt_tokens');
      expect(promptTokenRecords, isNotEmpty);
      expect(promptTokenRecords.first.value, 100.0);

      final completionTokenRecords = metrics.recorded
          .where((m) => m.name == 'flowbrain.llm.completion_tokens');
      expect(completionTokenRecords, isNotEmpty);
      expect(completionTokenRecords.first.value, 50.0);
    });

    test('aggregates daily cost and resets on new day', () async {
      final inner = _MockLlmPort();
      final metrics = _RecordingMetricPort();

      final decorator = CostTrackingLlmDecorator(
        inner: inner,
        metrics: metrics,
        calculator: CostCalculator(),
      );

      await decorator.complete(LlmRequest.simple('t1'));
      await decorator.complete(LlmRequest.simple('t2'));

      expect(decorator.todayUsd, greaterThan(0));
      final afterTwo = decorator.todayUsd;

      // Simulate day change
      decorator.resetForNewDay();
      expect(decorator.todayUsd, 0.0);

      await decorator.complete(LlmRequest.simple('t3'));
      expect(decorator.todayUsd, lessThan(afterTwo));
    });

    test('emits CostThresholdExceededEvent when daily limit exceeded',
        () async {
      final inner = _MockLlmPort(
        response: const LlmResponse(
          content: 'expensive',
          usage: LlmUsage(inputTokens: 1000000, outputTokens: 500000),
          model: 'claude-sonnet',
        ),
      );
      final metrics = _RecordingMetricPort();
      final eventBus = KnowledgeEventBus();
      final events = <KnowledgeEvent>[];
      eventBus.stream.listen(events.add);

      final decorator = CostTrackingLlmDecorator(
        inner: inner,
        metrics: metrics,
        calculator: CostCalculator(),
        eventBus: eventBus,
        dailyAlertUsd: 0.001, // Very low threshold
      );

      await decorator.complete(LlmRequest.simple('big query'));
      // Allow stream propagation
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<CostThresholdExceededEvent>(), isNotEmpty);
      await eventBus.close();
    });

    test('capabilities delegated from inner', () {
      final inner = _MockLlmPort();
      final decorator = CostTrackingLlmDecorator(
        inner: inner,
        calculator: CostCalculator(),
      );
      expect(decorator.capabilities, inner.capabilities);
    });
  });

  group('ExporterFactory', () {
    test('builds StructuredLogExporter for "log"', () {
      final config = ObservabilityConfig(exporters: ['log']);
      final exporters = ExporterFactory.build(config);
      expect(exporters.length, 1);
      expect(exporters.first, isA<StructuredLogExporter>());
    });

    test('builds PrometheusExporter stub for "prometheus"', () {
      final config = ObservabilityConfig(exporters: ['prometheus']);
      final exporters = ExporterFactory.build(config);
      expect(exporters.length, 1);
      expect(exporters.first, isA<PrometheusExporter>());
    });

    test('builds OtelExporter stub for "otel"', () {
      final config = ObservabilityConfig(exporters: ['otel']);
      final exporters = ExporterFactory.build(config);
      expect(exporters.length, 1);
      expect(exporters.first, isA<OtelExporter>());
    });

    test('throws on unknown exporter name', () {
      final config = ObservabilityConfig(exporters: ['unknown']);
      expect(() => ExporterFactory.build(config), throwsArgumentError);
    });

    test('builds multiple exporters', () {
      final config =
          ObservabilityConfig(exporters: ['log', 'prometheus', 'otel']);
      final exporters = ExporterFactory.build(config);
      expect(exporters.length, 3);
    });
  });

  group('ObservabilityBinding', () {
    test('dispatches events to all exporters', () async {
      final eventBus = KnowledgeEventBus();
      final config = ObservabilityConfig(exporters: ['log']);
      final binding = ObservabilityBinding.start(config, eventBus);

      // Emit a test event
      eventBus.emit(CostThresholdExceededEvent(
        todayUsd: 5.0,
        threshold: 1.0,
        timestamp: DateTime.now(),
      ));

      // Allow stream propagation
      await Future<void>.delayed(Duration.zero);

      // Binding should have dispatched without errors
      await binding.stop();
      await eventBus.close();
    });

    test('stop cancels subscription and stops exporters', () async {
      final eventBus = KnowledgeEventBus();
      final config = ObservabilityConfig(exporters: ['log']);
      final binding = ObservabilityBinding.start(config, eventBus);

      await binding.stop();

      // Emitting after stop should not cause errors
      eventBus.emit(CostThresholdExceededEvent(
        todayUsd: 5.0,
        threshold: 1.0,
        timestamp: DateTime.now(),
      ));

      await Future<void>.delayed(Duration.zero);
      await eventBus.close();
    });
  });
}
