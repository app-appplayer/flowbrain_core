/// Config-to-runtime resolver per DDD core-cfg/04-resolver.md.
///
/// Transforms a validated [FlowBrainConfig] into concrete runtime
/// instances (LlmHub, StoragePort, etc.) that the Assembler uses
/// to wire the KnowledgeSystem.
library;

import 'package:logging/logging.dart';

import '../asm/errors.dart';
import 'schema/flowbrain_config.dart';

final _log = Logger('flowbrain.core.cfg.resolver');

/// Aggregated LLM + MCP runtime instances.
///
/// Combines the LLM port adapter with MCP server/client managers,
/// providing a single object for the Assembler to consume.
class LlmHub {
  /// The LLM port adapter for completion/embedding calls.
  final dynamic llmPort;

  /// MCP server manager for exposing FlowBrain tools.
  final dynamic mcpServers;

  /// MCP client manager for connecting to external MCP servers.
  final dynamic mcpClients;

  /// McpPort adapter wrapping McpClientManager for bundle port interface.
  final dynamic mcpPortAdapter;

  const LlmHub({
    required this.llmPort,
    this.mcpServers,
    this.mcpClients,
    this.mcpPortAdapter,
  });
}

/// Factory for creating [LlmHub] instances from LLM provider configuration.
///
/// Uses mcp_llm's LlmProviderRegistry to instantiate the provider,
/// then wraps it with LlmPortAdapter and initializes MCP managers.
class LlmHubFactory {
  /// Create an [LlmHub] from provider config and resolved secrets.
  ///
  /// Stub implementation — returns a placeholder LlmHub. Full wiring
  /// will use mcp_llm's LlmProviderRegistry and McpServerManager/
  /// McpClientManager when integrated.
  static Future<LlmHub> create(
    LlmProviderConfig config, {
    Map<String, String> resolvedSecrets = const {},
  }) async {
    _log.info('LlmHubFactory.create: type=${config.type}');

    // Stub: actual implementation will instantiate via mcp_llm
    return const LlmHub(llmPort: null);
  }
}

/// Factory for creating storage port instances from storage configuration.
///
/// Maps storage type strings to concrete adapter implementations:
/// sqlite, firestore, postgres, memory.
class StorageFactory {
  /// Create a storage port from provider config and resolved secrets.
  ///
  /// Stub implementation — returns null. Full implementation will
  /// create SqliteStorageAdapter, FirestoreStorageAdapter, etc.
  static Future<dynamic> create(
    StorageProviderConfig config, {
    Map<String, String> resolvedSecrets = const {},
  }) async {
    _log.info('StorageFactory.create: type=${config.type}');

    return switch (config.type) {
      'memory' => null, // InMemoryCollectionStoragePort
      'sqlite' => null, // SqliteStorageAdapter
      'firestore' => null, // FirestoreStorageAdapter
      'postgres' => null, // PostgresStorageAdapter
      _ => throw RuntimeWiringError(
          'Unknown storage type: ${config.type}'),
    };
  }
}
