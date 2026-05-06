/// Escalation policy for the Knowledge-first LLM adapter.
///
/// Classifies aggregated knowledge confidence into one of three
/// escalation tiers that determine whether to use a template,
/// a cheap model, or the primary model.
library;

/// Escalation tier selected by [EscalationPolicy.classify].
enum Tier {
  /// Knowledge fully covers the query — template response, no LLM call.
  hit,

  /// Partial knowledge — use cheap/small model with injected context.
  partial,

  /// Insufficient knowledge — full primary model call required.
  miss,
}

/// Configurable escalation thresholds and model identifiers.
class EscalationPolicy {
  /// Minimum confidence for a Tier.hit (template response).
  final double hitThreshold;

  /// Minimum confidence for a Tier.partial (cheap model).
  final double partialThreshold;

  /// Model identifier used for cheap/partial calls.
  final String cheapModel;

  /// Model identifier used for full/primary calls.
  final String primaryModel;

  /// Default language for template responses.
  final String defaultLanguage;

  /// Whether learning loop is enabled.
  final bool learningEnabled;

  const EscalationPolicy({
    this.hitThreshold = 0.85,
    this.partialThreshold = 0.5,
    this.cheapModel = 'claude-haiku-4-5',
    this.primaryModel = 'claude-sonnet-4-6',
    this.defaultLanguage = 'en',
    this.learningEnabled = true,
  });

  /// Create an [EscalationPolicy] from a [FlowBrainConfig].
  ///
  /// Reads KFL-related settings from the config's extensions map
  /// under the 'kfl' key, falling back to defaults when absent.
  factory EscalationPolicy.fromConfig(dynamic config) {
    // Accept either a FlowBrainConfig (via extensions['kfl']) or a raw Map.
    Map<String, dynamic> kfl;
    if (config is Map<String, dynamic>) {
      kfl = config;
    } else {
      // Assume FlowBrainConfig-like object with extensions field.
      try {
        final dynamic ext = (config as dynamic).extensions;
        kfl = (ext is Map<String, dynamic>)
            ? (ext['kfl'] as Map<String, dynamic>? ?? const {})
            : const {};
      } catch (_) {
        kfl = const {};
      }
    }

    return EscalationPolicy(
      hitThreshold: (kfl['hit_threshold'] as num?)?.toDouble() ?? 0.85,
      partialThreshold:
          (kfl['partial_threshold'] as num?)?.toDouble() ?? 0.5,
      cheapModel: kfl['cheap_model'] as String? ?? 'claude-haiku-4-5',
      primaryModel: kfl['primary_model'] as String? ?? 'claude-sonnet-4-6',
      defaultLanguage:
          kfl['default_language'] as String? ?? 'en',
      learningEnabled: kfl['learning'] as bool? ?? true,
    );
  }

  /// Classify an aggregated confidence score into an escalation tier.
  Tier classify(double confidence) {
    if (confidence >= hitThreshold) return Tier.hit;
    if (confidence >= partialThreshold) return Tier.partial;
    return Tier.miss;
  }
}
