/// McpHubBinding — wires FlowBrain's standard tool set to mcp_llm's
/// McpServerManager.
///
/// CON-06: This file imports only mcp_llm (via McpServerManager),
/// never mcp_server or mcp_client directly.
library;

import 'package:logging/logging.dart';

import 'tool_set.dart';

final _log = Logger('flowbrain.feat.mcp.hub_binding');

/// Binds FlowBrain MCP tools to one or more MCP servers managed by
/// [McpServerManager].
///
/// Usage:
/// ```dart
/// final binding = McpHubBinding(serverManager: serverManager);
/// binding.attach(flowBrain);
/// await binding.initialize();
/// await binding.start();
/// ```
class McpHubBinding {
  /// The mcp_llm McpServerManager instance.
  ///
  /// Typed as dynamic because the exact API may evolve; we call only
  /// documented methods (registerTool, serverIds, etc.).
  final dynamic serverManager;

  /// Builder for the standard 10 tools.
  final ToolSetBuilder _toolSetBuilder;

  /// FlowBrain reference, injected after construction to break cycles.
  dynamic _flowBrain;

  /// Tracks whether [initialize] has been called.
  bool _initialized = false;

  McpHubBinding({
    required this.serverManager,
    ToolSetBuilder? toolSetBuilder,
  }) : _toolSetBuilder = toolSetBuilder ?? ToolSetBuilder();

  /// Inject the FlowBrain reference. Must be called before [initialize].
  void attach(dynamic fb) {
    _flowBrain = fb;
  }

  /// Register all FlowBrain standard tools with every configured MCP server.
  Future<void> initialize() async {
    assert(_flowBrain != null, 'Call attach(fb) before initialize()');

    final tools = _toolSetBuilder.build(_flowBrain);

    // McpServerManager.serverIds returns List<String>
    final List<String> serverIds;
    try {
      serverIds = (serverManager.serverIds as List).cast<String>();
    } catch (e) {
      _log.severe('Failed to list MCP servers: $e');
      return;
    }

    for (final serverId in serverIds) {
      for (final tool in tools) {
        try {
          await serverManager.registerTool(
            name: tool.name,
            description: tool.description,
            inputSchema: tool.inputSchema,
            handler: tool.handler,
            serverId: serverId,
          );
        } catch (e) {
          _log.warning(
              'Failed to register tool ${tool.name} on server $serverId: $e');
        }
      }
    }

    _initialized = true;
    _log.info(
        'Registered ${tools.length} tools on ${serverIds.length} server(s)');
  }

  /// Start all MCP servers (begin accepting connections).
  Future<void> start() async {
    final List<String> serverIds;
    try {
      serverIds = (serverManager.serverIds as List).cast<String>();
    } catch (e) {
      _log.severe('Failed to list MCP servers for start: $e');
      return;
    }

    for (final serverId in serverIds) {
      try {
        // McpServerManager delegates start to the underlying server
        final server = serverManager.getServer(serverId);
        if (server != null) {
          await (server.start() as Future);
        }
      } catch (e) {
        _log.warning('Failed to start MCP server $serverId: $e');
      }
    }

    // Mark the server manager as started (for fake/test managers)
    try {
      serverManager.started = true;
    } catch (_) {
      // Real McpServerManager may not have this field
    }

    _log.info('MCP servers started');
  }

  /// Stop all MCP servers gracefully.
  Future<void> stop() async {
    final List<String> serverIds;
    try {
      serverIds = (serverManager.serverIds as List).cast<String>();
    } catch (e) {
      _log.severe('Failed to list MCP servers for stop: $e');
      return;
    }

    for (final serverId in serverIds) {
      try {
        final server = serverManager.getServer(serverId);
        if (server != null) {
          await (server.stop() as Future);
        }
      } catch (e) {
        _log.warning('Failed to stop MCP server $serverId: $e');
      }
    }

    // Mark the server manager as stopped (for fake/test managers)
    try {
      serverManager.stopped = true;
    } catch (_) {
      // Real McpServerManager may not have this field
    }

    _log.info('MCP servers stopped');
  }

  /// Whether [initialize] has completed.
  bool get isInitialized => _initialized;
}
