/// Cost-tracking LLM decorator per DDD FEAT-OBS §3.
///
/// Wraps an [LlmPort] to track per-call token counts and USD cost,
/// aggregate daily totals, and emit [CostThresholdExceededEvent] when
/// the configurable daily cap is breached.
library;

import 'package:logging/logging.dart';
import 'package:mcp_bundle/mcp_bundle.dart'
    show
        LlmPort,
        LlmRequest,
        LlmResponse,
        LlmCapabilities,
        LlmChunk,
        MetricPort;
import 'package:mcp_knowledge/mcp_knowledge.dart' show KnowledgeEventBus;

import '../../events/flowbrain_events.dart';

final _log = Logger('flowbrain.obs.cost_tracking');

/// Per-model pricing in USD per million tokens.
class ModelPricing {
  /// Price per million input tokens.
  final double inputPerMillion;

  /// Price per million output tokens.
  final double outputPerMillion;

  const ModelPricing({
    required this.inputPerMillion,
    required this.outputPerMillion,
  });
}

/// Estimates USD cost from token counts and model identity.
class CostCalculator {
  /// Model-specific pricing lookup.
  final Map<String, ModelPricing> pricing;

  /// Fallback pricing for unknown models.
  final ModelPricing defaultPricing;

  CostCalculator({
    Map<String, ModelPricing>? pricing,
    ModelPricing? defaultPricing,
  })  : pricing = pricing ?? _defaultPricing,
        defaultPricing =
            defaultPricing ?? const ModelPricing(
              inputPerMillion: 3.0,
              outputPerMillion: 15.0,
            );

  /// Estimate cost in USD.
  double estimate({
    required String model,
    required int promptTokens,
    required int completionTokens,
  }) {
    final p = pricing[model] ?? _matchPartial(model) ?? defaultPricing;
    return (promptTokens / 1e6) * p.inputPerMillion +
        (completionTokens / 1e6) * p.outputPerMillion;
  }

  /// Try partial model name matching (e.g. "claude-sonnet" matches
  /// keys containing "sonnet").
  ModelPricing? _matchPartial(String model) {
    final lower = model.toLowerCase();
    for (final entry in pricing.entries) {
      if (lower.contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return null;
  }

  /// Baseline pricing for common models.
  static const _defaultPricing = <String, ModelPricing>{
    'claude-sonnet': ModelPricing(inputPerMillion: 3.0, outputPerMillion: 15.0),
    'claude-haiku': ModelPricing(inputPerMillion: 0.25, outputPerMillion: 1.25),
    'claude-opus': ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0),
    'gpt-4o': ModelPricing(inputPerMillion: 2.5, outputPerMillion: 10.0),
    'gpt-4o-mini': ModelPricing(inputPerMillion: 0.15, outputPerMillion: 0.6),
  };
}

/// Decorator that wraps [LlmPort] with per-call cost tracking.
class CostTrackingLlmDecorator extends LlmPort {
  /// Inner LLM port to delegate to.
  final LlmPort inner;

  /// Optional metric sink for recording cost and token metrics.
  final MetricPort? metrics;

  /// Optional event bus for threshold alerts.
  final KnowledgeEventBus? eventBus;

  /// Calculator for USD estimation.
  final CostCalculator calculator;

  /// Daily cost alert threshold in USD (null = no alert).
  final double? dailyAlertUsd;

  /// Accumulated cost for the current day.
  double _todayUsd = 0.0;

  /// Current calendar day for daily-reset logic.
  DateTime _day = _today();

  CostTrackingLlmDecorator({
    required this.inner,
    this.metrics,
    this.eventBus,
    required this.calculator,
    this.dailyAlertUsd,
  });

  /// Current day's accumulated cost (visible for testing).
  double get todayUsd => _todayUsd;

  /// Reset daily accumulator (exposed for testing day transitions).
  void resetForNewDay() {
    _day = _today();
    _todayUsd = 0.0;
  }

  @override
  LlmCapabilities get capabilities => inner.capabilities;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    final response = await inner.complete(request);
    _aggregate(request, response);
    return response;
  }

  @override
  Stream<LlmChunk> completeStream(LlmRequest request) {
    return inner.completeStream(request);
  }

  @override
  Future<List<double>> embed(String text) => inner.embed(text);

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _aggregate(LlmRequest request, LlmResponse response) {
    final promptTokens = response.usage?.inputTokens ?? 0;
    final completionTokens = response.usage?.outputTokens ?? 0;
    final model = request.model ?? response.model ?? 'default';

    final usd = calculator.estimate(
      model: model,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );

    // Daily reset check.
    final today = _today();
    if (today != _day) {
      _day = today;
      _todayUsd = 0.0;
    }
    _todayUsd += usd;

    // Record metrics.
    try {
      metrics?.record(
        'flowbrain.llm.cost_usd',
        usd,
        tags: {'model': model},
      );
      metrics?.record(
        'flowbrain.llm.prompt_tokens',
        promptTokens.toDouble(),
      );
      metrics?.record(
        'flowbrain.llm.completion_tokens',
        completionTokens.toDouble(),
      );
    } catch (e) {
      _log.fine('Metric recording failed (non-fatal): $e');
    }

    // Threshold alert.
    if (dailyAlertUsd != null && _todayUsd > dailyAlertUsd!) {
      eventBus?.emit(CostThresholdExceededEvent(
        todayUsd: _todayUsd,
        threshold: dailyAlertUsd!,
        timestamp: DateTime.now(),
      ));
    }
  }

  /// Calendar day helper (UTC).
  static DateTime _today() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }
}
