/// Abstract base class for FlowBrain MCP tools.
///
/// Each tool exposes a name, description, JSON Schema for inputs,
/// and a handler that processes arguments and returns a result map.
library;

/// Base class for all FlowBrain standard MCP tools.
abstract class FlowBrainTool {
  /// MCP tool name (e.g. 'knowledge.save').
  String get name;

  /// Human-readable description for MCP tool discovery.
  String get description;

  /// JSON Schema describing the tool's input parameters.
  Map<String, dynamic> get inputSchema;

  /// Execute the tool with the given arguments.
  Future<Map<String, dynamic>> handler(Map<String, dynamic> args);
}
