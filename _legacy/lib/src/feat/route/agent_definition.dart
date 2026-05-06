/// Agent definition and route rule types for FEAT-ROUTE.
///
/// Defines the [AgentDefinition] value type and [RouteRule] sealed class
/// hierarchy (keyword, regex, LLM-based matching).
library;

/// Definition of an agent with its capabilities and routing configuration.
class AgentDefinition {
  /// Unique agent identifier.
  final String id;

  /// FactGraph scopes this agent can access.
  final List<String> factGraphScopes;

  /// Skill identifiers this agent can execute.
  final List<String> skills;

  /// Profile identifier for output formatting.
  final String profileId;

  /// Philosophy identifier for value-based intervention.
  final String philosophyId;

  /// Whether this agent is currently active.
  final bool enabled;

  /// Optional routing rule for request matching.
  final RouteRule? route;

  const AgentDefinition({
    required this.id,
    required this.factGraphScopes,
    required this.skills,
    required this.profileId,
    required this.philosophyId,
    this.enabled = true,
    this.route,
  });

  /// Construct from a config map entry (YAML/JSON deserialized).
  factory AgentDefinition.fromConfig(String id, Map<String, dynamic> config) {
    return AgentDefinition(
      id: id,
      factGraphScopes: _parseStringList(config['scopes']),
      skills: _parseStringList(config['skills']),
      profileId: config['profile'] as String? ?? 'default',
      philosophyId: config['philosophy'] as String? ?? 'default',
      enabled: config['enabled'] as bool? ?? true,
      route: _parseRouteRule(config['route']),
    );
  }
}

// ── RouteRule sealed hierarchy ────────────────────────────────────────────

/// Sealed base for routing rules. Each subclass defines how a request
/// string is matched to an agent.
sealed class RouteRule {
  const RouteRule();

  /// Return true if [request] matches this rule.
  bool matches(String request);
}

/// Matches when any keyword is found in the request (case-insensitive).
class KeywordRule extends RouteRule {
  /// Keywords to search for.
  final List<String> keywords;

  const KeywordRule({required this.keywords});

  @override
  bool matches(String request) {
    final lower = request.toLowerCase();
    return keywords.any((k) => lower.contains(k.toLowerCase()));
  }
}

/// Matches when the regex pattern hits the request.
class RegexRule extends RouteRule {
  /// Regular expression pattern.
  final RegExp pattern;

  const RegexRule({required this.pattern});

  @override
  bool matches(String request) => pattern.hasMatch(request);
}

/// LLM-based classification rule. The [matches] method always returns
/// false — actual resolution is performed by [AgentRouter] via the
/// LLM port at runtime.
class LlmRule extends RouteRule {
  /// Classification prompt template.
  final String prompt;

  const LlmRule({required this.prompt});

  @override
  bool matches(String request) => false;
}

// ── Helpers ──────────────────────────────────────────────────────────────

List<String> _parseStringList(dynamic value) {
  if (value == null) return [];
  if (value is List) return value.map((e) => e.toString()).toList();
  return [];
}

RouteRule? _parseRouteRule(dynamic value) {
  if (value == null) return null;
  if (value is! Map<String, dynamic>) return null;

  final type = value['type'] as String?;
  switch (type) {
    case 'keyword':
      return KeywordRule(keywords: _parseStringList(value['keywords']));
    case 'regex':
      return RegexRule(pattern: RegExp(value['pattern'] as String));
    case 'llm':
      return LlmRule(prompt: value['prompt'] as String? ?? '');
    default:
      return null;
  }
}
