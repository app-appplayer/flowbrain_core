/// Agent registry for FEAT-ROUTE.
///
/// Manages the collection of [AgentDefinition] instances with
/// register/unregister/get/list operations and a default agent fallback.
library;

import 'agent_definition.dart';

/// Registry of available agents. Supports hot-reload by allowing
/// register/unregister at runtime.
class AgentRegistry {
  final Map<String, AgentDefinition> _agents = {};
  AgentDefinition? _default;

  /// Create an empty registry.
  AgentRegistry();

  /// Private constructor used by [load].
  AgentRegistry._();

  /// Look up an agent by its [id]. Returns null if not found.
  AgentDefinition? get(String id) => _agents[id];

  /// List registered agents. When [onlyEnabled] is true (default),
  /// only returns agents where `enabled == true`.
  List<AgentDefinition> list({bool onlyEnabled = true}) =>
      _agents.values.where((a) => !onlyEnabled || a.enabled).toList();

  /// Register (or replace) an agent. If the agent id is "default",
  /// it also becomes the [defaultAgent].
  void register(AgentDefinition agent) {
    _agents[agent.id] = agent;
    if (agent.id == 'default') _default = agent;
  }

  /// Remove an agent by [id].
  void unregister(String id) {
    _agents.remove(id);
    if (_default?.id == id) _default = null;
  }

  /// The designated default agent (typically id == "default").
  AgentDefinition? get defaultAgent => _default;

  /// Build a registry from a raw config map (deserialized from YAML/JSON).
  ///
  /// Each key is the agent id, each value is the agent config map.
  /// Example:
  /// ```yaml
  /// agents:
  ///   finance:
  ///     skills: [settlement]
  ///     profile: conservative
  ///     philosophy: accuracy_first
  ///     scopes: [accounting]
  ///     route:
  ///       type: keyword
  ///       keywords: [tax]
  /// ```
  static AgentRegistry load(Map<String, dynamic> configAgents) {
    final reg = AgentRegistry._();
    for (final entry in configAgents.entries) {
      final agentConfig = entry.value;
      if (agentConfig is Map<String, dynamic>) {
        reg.register(AgentDefinition.fromConfig(entry.key, agentConfig));
      }
    }
    return reg;
  }
}
