/// McpClientAdapter — implements mcp_bundle's McpPort using
/// mcp_llm's McpClientManager.
///
/// CON-06: This file imports only mcp_bundle (for the McpPort interface)
/// and receives McpClientManager as a dynamic reference via constructor.
/// It never imports mcp_server or mcp_client directly.
library;

import 'package:logging/logging.dart';
import 'package:mcp_bundle/src/ports/mcp_port.dart';

final _log = Logger('flowbrain.feat.mcp.client_adapter');

/// Adapts [McpClientManager] from mcp_llm to the [McpPort] interface
/// expected by mcp_bundle's SkillFacade.
class McpClientAdapter implements McpPort {
  /// The mcp_llm McpClientManager instance.
  ///
  /// Typed as dynamic to decouple from exact mcp_llm API version.
  final dynamic _clients;

  McpClientAdapter(this._clients);

  @override
  Future<ToolResult> callTool(
    String name,
    Map<String, dynamic> arguments, {
    String? serverId,
  }) async {
    try {
      final result = await _clients.executeTool(
        name,
        arguments,
        clientId: serverId,
      );

      // McpClientManager.executeTool returns dynamic — normalize to ToolResult
      if (result is Map<String, dynamic>) {
        final isError = result.containsKey('error');
        return ToolResult(
          content: result,
          isError: isError,
          errorMessage: isError ? result['error']?.toString() : null,
        );
      }
      return ToolResult.success(result);
    } catch (e) {
      _log.warning('callTool "$name" on server "$serverId" failed: $e');
      return ToolResult.error(e.toString());
    }
  }

  @override
  Future<ResourceContent> readResource(
    String uri, {
    String? serverId,
  }) async {
    try {
      final result = await _clients.readResource(uri, clientId: serverId);
      if (result is Map<String, dynamic>) {
        return ResourceContent(
          uri: uri,
          mimeType: result['mimeType'] as String?,
          text: result['content']?.toString(),
        );
      }
      return ResourceContent(uri: uri, text: result?.toString());
    } catch (e) {
      _log.warning('readResource "$uri" on server "$serverId" failed: $e');
      return ResourceContent(uri: uri, text: null);
    }
  }

  @override
  Future<List<ToolInfo>> listTools({String? serverId}) async {
    try {
      final tools = await _clients.getTools(serverId)
          as List<Map<String, dynamic>>;
      return tools
          .map((t) => ToolInfo(
                name: t['name'] as String? ?? '',
                description: t['description'] as String?,
                inputSchema: t['inputSchema'] as Map<String, dynamic>?,
                serverId: t['clientId'] as String?,
              ))
          .toList();
    } catch (e) {
      _log.warning('listTools on server "$serverId" failed: $e');
      return [];
    }
  }

  @override
  Future<List<ResourceInfo>> listResources({String? serverId}) async {
    try {
      final resources = await _clients.getResources(serverId)
          as List<Map<String, dynamic>>;
      return resources
          .map((r) => ResourceInfo(
                uri: r['uri'] as String? ?? '',
                name: r['name'] as String? ?? '',
                description: r['description'] as String?,
                mimeType: r['mimeType'] as String?,
                serverId: r['clientId'] as String?,
              ))
          .toList();
    } catch (e) {
      _log.warning('listResources on server "$serverId" failed: $e');
      return [];
    }
  }

  @override
  Stream<ResourceContent>? subscribeResource(
    String uri, {
    String? serverId,
  }) {
    // Resource subscription is not yet supported via McpClientManager
    _log.info('subscribeResource not yet supported via McpClientAdapter');
    return null;
  }

  @override
  Future<PromptTemplate?> getPrompt(
    String name, {
    String? serverId,
    Map<String, dynamic>? arguments,
  }) async {
    try {
      final prompts = await _clients.getPrompts(serverId)
          as List<Map<String, dynamic>>;
      final match = prompts.where((p) => p['name'] == name).firstOrNull;
      if (match == null) return null;
      return PromptTemplate(
        name: match['name'] as String? ?? name,
        text: match['description'] as String? ?? '',
        description: match['description'] as String?,
      );
    } catch (e) {
      _log.warning('getPrompt "$name" on server "$serverId" failed: $e');
      return null;
    }
  }

  @override
  Future<bool> isConnected({String? serverId}) async {
    try {
      final ids = _clients.clientIds as List<String>;
      if (serverId != null) return ids.contains(serverId);
      return ids.isNotEmpty;
    } catch (e) {
      _log.warning('isConnected check failed: $e');
      return false;
    }
  }
}
