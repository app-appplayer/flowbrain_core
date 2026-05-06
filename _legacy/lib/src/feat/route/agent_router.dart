/// Agent router for FEAT-ROUTE.
///
/// Resolves a natural-language request to an [AgentDefinition] using a
/// multi-tier strategy: cache -> keyword/regex -> LLM fallback -> default.
library;

import 'package:logging/logging.dart';

import '../../core/asm/errors.dart';
import 'agent_definition.dart';
import 'agent_registry.dart';

final _log = Logger('AgentRouter');

// ── Ports / abstractions ─────────────────────────────────────────────────

/// Minimal LLM port abstraction used only for agent classification.
/// The host wires a real LlmPort adapter; tests supply a stub.
abstract class LlmPort {
  /// Send a prompt and receive a text response.
  Future<LlmResponse> complete(String prompt);
}

/// Simplified LLM response for routing purposes.
class LlmResponse {
  /// Response text.
  final String text;

  const LlmResponse({required this.text});
}

/// Simple route-level cache abstraction.
abstract class AskRouteCache {
  /// Retrieve cached agent id for a request, or null.
  String? get(String request);

  /// Store a mapping from request to agent id.
  void put(String request, String agentId);
}

/// In-memory LRU-ish cache implementation (bounded).
class InMemoryRouteCache implements AskRouteCache {
  final int _maxSize;
  final Map<String, String> _map = {};

  InMemoryRouteCache({int maxSize = 256}) : _maxSize = maxSize;

  @override
  String? get(String request) => _map[request];

  @override
  void put(String request, String agentId) {
    if (_map.length >= _maxSize) {
      // Evict oldest entry
      _map.remove(_map.keys.first);
    }
    _map[request] = agentId;
  }
}

// ── Router ───────────────────────────────────────────────────────────────

/// Routes a natural-language request to the appropriate [AgentDefinition].
///
/// Resolution priority:
/// 1. Cache hit
/// 2. Keyword / regex rule match
/// 3. LLM-based classification (if [llm] is provided)
/// 4. Default agent
/// 5. Throw [AgentNotFoundError]
class AgentRouter {
  /// Agent registry to search.
  final AgentRegistry registry;

  /// Optional LLM port for classification fallback.
  final LlmPort? llm;

  /// Route-level cache.
  final AskRouteCache cache;

  AgentRouter({
    required this.registry,
    required this.cache,
    this.llm,
  });

  /// Resolve a [request] string to an [AgentDefinition].
  Future<AgentDefinition> resolve(String request) async {
    // 1. Cache hit
    final cached = cache.get(request);
    if (cached != null) {
      final agent = registry.get(cached);
      if (agent != null) return agent;
    }

    // 2. Rule-based (keyword / regex) — skip LlmRule
    for (final agent in registry.list()) {
      final rule = agent.route;
      if (rule != null && rule is! LlmRule && rule.matches(request)) {
        cache.put(request, agent.id);
        return agent;
      }
    }

    // 3. LLM-based fallback
    if (llm != null) {
      try {
        final agent = await _classifyWithLlm(request);
        if (agent != null) {
          cache.put(request, agent.id);
          return agent;
        }
      } catch (e) {
        _log.warning('LLM classification failed, falling back to default: $e');
      }
    }

    // 4. Default agent
    final def = registry.defaultAgent;
    if (def != null) return def;

    // 5. No match
    throw AgentNotFoundError('No agent matched: $request');
  }

  /// Use LLM to classify the request into an agent id.
  Future<AgentDefinition?> _classifyWithLlm(String request) async {
    final candidates = registry.list();
    final prompt = _buildClassificationPrompt(request, candidates);
    final response = await llm!.complete(prompt);
    final id = _extractAgentId(response.text);
    return id != null ? registry.get(id) : null;
  }

  /// Build a classification prompt listing available agents.
  String _buildClassificationPrompt(
    String request,
    List<AgentDefinition> candidates,
  ) {
    final agentList = candidates
        .map((a) => '- ${a.id}: skills=${a.skills.join(",")}')
        .join('\n');
    return 'Given the following agents:\n$agentList\n\n'
        'Which agent id best handles this request?\n'
        '"$request"\n\n'
        'Reply with only the agent id.';
  }

  /// Extract a clean agent id from LLM response text.
  String? _extractAgentId(String text) {
    final trimmed = text.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    // Take the first line, strip quotes
    final firstLine = trimmed.split('\n').first.replaceAll(RegExp(r'["\s]'), '');
    return firstLine.isNotEmpty ? firstLine : null;
  }
}
