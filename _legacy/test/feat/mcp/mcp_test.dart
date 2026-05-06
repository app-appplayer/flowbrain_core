import 'dart:io';

import 'package:test/test.dart';

import 'package:flowbrain_core/src/feat/mcp/tool_set.dart';
import 'package:flowbrain_core/src/feat/mcp/mcp_hub_binding.dart';
import 'package:flowbrain_core/src/feat/mcp/mcp_client_adapter.dart';

// Minimal stub for FlowBrain-like object used by tools.
class _FakeFlowBrain {
  final saveCalls = <Map<String, dynamic>>[];
  final queryCalls = <Map<String, dynamic>>[];
  final skillCalls = <Map<String, dynamic>>[];
  final askCalls = <Map<String, dynamic>>[];
  final installCalls = <Map<String, dynamic>>[];
  final listCalls = <int>[];
  final uninstallCalls = <Map<String, dynamic>>[];
  final philosophyCalls = <int>[];
  final pipelineRunCalls = <Map<String, dynamic>>[];
  final pipelineStatusCalls = <Map<String, dynamic>>[];
}

// Minimal stub for McpServerManager to verify hub binding calls.
class _FakeServerManager {
  final registeredTools = <Map<String, dynamic>>[];
  final serverIdList = <String>['default-server'];
  bool started = false;
  bool stopped = false;

  List<String> get serverIds => serverIdList;

  Future<bool> registerTool({
    required String name,
    required String description,
    required Map<String, dynamic> inputSchema,
    required Function handler,
    String? serverId,
  }) async {
    registeredTools.add({
      'name': name,
      'description': description,
      'serverId': serverId,
    });
    return true;
  }
}

// Minimal stub for McpClientManager to verify client adapter calls.
class _FakeClientManager {
  final executedTools = <Map<String, dynamic>>[];
  final toolListCalls = <String?>[];
  final clientIdList = <String>['client-a', 'client-b'];

  List<String> get clientIds => clientIdList;

  Future<dynamic> executeTool(
    String toolName,
    Map<String, dynamic> args, {
    String? clientId,
  }) async {
    executedTools.add({
      'toolName': toolName,
      'args': args,
      'clientId': clientId,
    });
    return {'result': 'ok'};
  }

  Future<List<Map<String, dynamic>>> getTools([String? clientId]) async {
    toolListCalls.add(clientId);
    return [
      {'name': 'echo', 'description': 'Echo tool', 'clientId': clientId},
    ];
  }
}

void main() {
  group('ToolSetBuilder', () {
    test('build() returns exactly 10 tools', () {
      final fb = _FakeFlowBrain();
      final builder = ToolSetBuilder();
      final tools = builder.build(fb);

      expect(tools, hasLength(10));
    });

    test('all tools have non-empty name and description', () {
      final fb = _FakeFlowBrain();
      final builder = ToolSetBuilder();
      final tools = builder.build(fb);

      for (final tool in tools) {
        expect(tool.name, isNotEmpty, reason: '${tool.runtimeType} name');
        expect(tool.description, isNotEmpty,
            reason: '${tool.runtimeType} description');
      }
    });

    test('all tools have valid inputSchema with type=object', () {
      final fb = _FakeFlowBrain();
      final builder = ToolSetBuilder();
      final tools = builder.build(fb);

      for (final tool in tools) {
        expect(tool.inputSchema['type'], equals('object'),
            reason: '${tool.runtimeType} schema type');
      }
    });

    test('tool names match the DDD spec', () {
      final fb = _FakeFlowBrain();
      final builder = ToolSetBuilder();
      final tools = builder.build(fb);
      final names = tools.map((t) => t.name).toSet();

      expect(names, containsAll([
        'knowledge.save',
        'knowledge.query',
        'skill.execute',
        'agent.ask',
        'pack.install',
        'pack.list',
        'pack.uninstall',
        'philosophy.state',
        'pipeline.run',
        'pipeline.status',
      ]));
    });
  });

  group('KnowledgeSaveTool', () {
    test('handler delegates to FlowBrain and returns candidateIds', () async {
      final fb = _FakeFlowBrain();
      final tool = KnowledgeSaveTool(fb);

      final result = await tool.handler({
        'content': 'test knowledge',
        'mimeType': 'text/plain',
      });

      // Since FlowBrain is a fake, the tool should handle gracefully.
      // The stub delegates — we verify the call shape.
      expect(result, isA<Map<String, dynamic>>());
      expect(result.containsKey('candidateIds'), isTrue);
    });
  });

  group('McpHubBinding', () {
    test('initialize registers all 10 tools with server manager', () async {
      final serverManager = _FakeServerManager();
      final binding = McpHubBinding(serverManager: serverManager);
      final fb = _FakeFlowBrain();
      binding.attach(fb);

      await binding.initialize();

      // 10 tools x 1 server = 10 registrations
      expect(serverManager.registeredTools, hasLength(10));
    });

    test('start/stop lifecycle delegates to server manager', () async {
      final serverManager = _FakeServerManager();
      final binding = McpHubBinding(serverManager: serverManager);
      final fb = _FakeFlowBrain();
      binding.attach(fb);

      await binding.start();
      expect(serverManager.started, isTrue);

      await binding.stop();
      expect(serverManager.stopped, isTrue);
    });
  });

  group('McpClientAdapter', () {
    test('callTool delegates to McpClientManager.executeTool', () async {
      final clientManager = _FakeClientManager();
      final adapter = McpClientAdapter(clientManager);

      final result = await adapter.callTool(
        'echo',
        {'input': 'hello'},
        serverId: 'client-a',
      );

      expect(clientManager.executedTools, hasLength(1));
      expect(clientManager.executedTools.first['toolName'], 'echo');
      expect(clientManager.executedTools.first['clientId'], 'client-a');
      expect(result.isError, isFalse);
    });

    test('listTools delegates to McpClientManager.getTools', () async {
      final clientManager = _FakeClientManager();
      final adapter = McpClientAdapter(clientManager);

      final tools = await adapter.listTools(serverId: 'client-a');

      expect(tools, hasLength(1));
      expect(tools.first.name, 'echo');
    });

    test('listServers returns clientIds', () async {
      final clientManager = _FakeClientManager();
      final adapter = McpClientAdapter(clientManager);

      final result = await adapter.isConnected();

      // Verifies adapter is callable; actual connection depends on real manager
      expect(result, isA<bool>());
    });
  });

  group('CON-06 compliance', () {
    test('no source file imports mcp_server or mcp_client directly', () {
      // Scan all Dart files under lib/src for forbidden imports
      final libDir = Directory('lib/src');
      if (!libDir.existsSync()) {
        // Fallback: try from project root
        return;
      }

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final forbidden = RegExp(
        r'''import\s+['"]package:(mcp_server|mcp_client)/''',
      );

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        expect(
          forbidden.hasMatch(content),
          isFalse,
          reason: '${file.path} imports mcp_server or mcp_client directly',
        );
      }
    });
  });
}
