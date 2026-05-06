/// Concrete FlowBrain MCP tool implementations and ToolSetBuilder.
///
/// All 10 standard tools delegate to the FlowBrain facade (or a
/// domain-specific facade accessed through it). The FlowBrain
/// reference is accepted as `dynamic` to avoid circular dependency
/// with the assembler module that is implemented by another agent.
library;

import 'package:logging/logging.dart';

import 'flowbrain_tool.dart';

final _log = Logger('flowbrain.feat.mcp.tool_set');

// ---------------------------------------------------------------------------
// 1. KnowledgeSaveTool
// ---------------------------------------------------------------------------

/// Save content to the knowledge graph as pending candidates.
class KnowledgeSaveTool extends FlowBrainTool {
  final dynamic fb;
  KnowledgeSaveTool(this.fb);

  @override
  String get name => 'knowledge.save';

  @override
  String get description =>
      'Save content to the knowledge graph as pending candidates';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'content': {'type': 'string'},
          'mimeType': {'type': 'string'},
          'metadata': {'type': 'object'},
        },
        'required': ['content'],
      };

  @override
  Future<Map<String, dynamic>> handler(Map<String, dynamic> args) async {
    final content = args['content'] as String;
    final mimeType = args['mimeType'] as String? ?? 'text/plain';
    try {
      // Delegate to FlowBrain's knowledge facade when available.
      // The facade API: fb.knowledge.facts.extractFragments / createCandidates
      final knowledge = fb.knowledge;
      final fragments =
          await knowledge.facts.extractFragments(content, mimeType) as List;
      final candidates = fragments
          .map((f) => {
                'content': f.text as String,
                'source': 'mcp.knowledge.save',
                'confidence': f.confidence,
              })
          .toList();
      final ids =
          await knowledge.facts.createCandidates(candidates) as List<String>;
      return {'candidateIds': ids, 'count': ids.length};
    } catch (e) {
      _log.warning('KnowledgeSaveTool delegation failed, returning stub: $e');
      // Stub fallback until FlowBrain facade is fully wired.
      return {'candidateIds': <String>[], 'count': 0, 'stub': true};
    }
  }
}

// ---------------------------------------------------------------------------
// 2. KnowledgeQueryTool
// ---------------------------------------------------------------------------

/// Query the knowledge graph using KFL (Knowledge Filter Language).
class KnowledgeQueryTool extends FlowBrainTool {
  final dynamic fb;
  KnowledgeQueryTool(this.fb);

  @override
  String get name => 'knowledge.query';

  @override
  String get description =>
      'Query the knowledge graph using natural language or KFL';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          'limit': {'type': 'integer'},
          'filters': {'type': 'object'},
        },
        'required': ['query'],
      };

  @override
  Future<Map<String, dynamic>> handler(Map<String, dynamic> args) async {
    final query = args['query'] as String;
    final limit = args['limit'] as int? ?? 10;
    try {
      final results =
          await fb.knowledge.facts.query(query, limit: limit) as List;
      return {
        'results': results.map((r) => r.toJson()).toList(),
        'count': results.length,
      };
    } catch (e) {
      _log.warning('KnowledgeQueryTool delegation failed, returning stub: $e');
      return {'results': <Map<String, dynamic>>[], 'count': 0, 'stub': true};
    }
  }
}

// ---------------------------------------------------------------------------
// 3. SkillExecuteTool
// ---------------------------------------------------------------------------

/// Execute a registered skill by name.
class SkillExecuteTool extends FlowBrainTool {
  final dynamic fb;
  SkillExecuteTool(this.fb);

  @override
  String get name => 'skill.execute';

  @override
  String get description => 'Execute a registered skill by name';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'skill': {'type': 'string'},
          'args': {'type': 'object'},
        },
        'required': ['skill'],
      };

  @override
  Future<Map<String, dynamic>> handler(Map<String, dynamic> args) async {
    final skillName = args['skill'] as String;
    final skillArgs = args['args'] as Map<String, dynamic>? ?? {};
    try {
      final result = await fb.skills.execute(skillName, skillArgs);
      return {'result': result};
    } catch (e) {
      _log.warning('SkillExecuteTool delegation failed, returning stub: $e');
      return {'result': null, 'stub': true};
    }
  }
}

// ---------------------------------------------------------------------------
// 4. AgentAskTool
// ---------------------------------------------------------------------------

/// Send a natural-language question to FlowBrain's agent.
class AgentAskTool extends FlowBrainTool {
  final dynamic fb;
  AgentAskTool(this.fb);

  @override
  String get name => 'agent.ask';

  @override
  String get description =>
      'Ask FlowBrain a natural-language question';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'question': {'type': 'string'},
          'context': {'type': 'object'},
        },
        'required': ['question'],
      };

  @override
  Future<Map<String, dynamic>> handler(Map<String, dynamic> args) async {
    final question = args['question'] as String;
    try {
      final answer = await fb.ask(question);
      return {'answer': answer};
    } catch (e) {
      _log.warning('AgentAskTool delegation failed, returning stub: $e');
      return {'answer': null, 'stub': true};
    }
  }
}

// ---------------------------------------------------------------------------
// 5. PackInstallTool
// ---------------------------------------------------------------------------

/// Install a knowledge pack from a source URI.
class PackInstallTool extends FlowBrainTool {
  final dynamic fb;
  PackInstallTool(this.fb);

  @override
  String get name => 'pack.install';

  @override
  String get description => 'Install a knowledge pack from a source URI';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'source': {'type': 'string'},
          'version': {'type': 'string'},
        },
        'required': ['source'],
      };

  @override
  Future<Map<String, dynamic>> handler(Map<String, dynamic> args) async {
    final source = args['source'] as String;
    final version = args['version'] as String?;
    try {
      final result = await fb.bundles.install(source, version: version);
      return {'installed': true, 'id': result};
    } catch (e) {
      _log.warning('PackInstallTool delegation failed, returning stub: $e');
      return {'installed': false, 'stub': true};
    }
  }
}

// ---------------------------------------------------------------------------
// 6. PackListTool
// ---------------------------------------------------------------------------

/// List installed knowledge packs.
class PackListTool extends FlowBrainTool {
  final dynamic fb;
  PackListTool(this.fb);

  @override
  String get name => 'pack.list';

  @override
  String get description => 'List installed knowledge packs';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {},
      };

  @override
  Future<Map<String, dynamic>> handler(Map<String, dynamic> args) async {
    try {
      final packs = await fb.bundles.list() as List;
      return {
        'packs': packs.map((p) => p.toJson()).toList(),
        'count': packs.length,
      };
    } catch (e) {
      _log.warning('PackListTool delegation failed, returning stub: $e');
      return {'packs': <Map<String, dynamic>>[], 'count': 0, 'stub': true};
    }
  }
}

// ---------------------------------------------------------------------------
// 7. PackUninstallTool
// ---------------------------------------------------------------------------

/// Uninstall a knowledge pack by ID.
class PackUninstallTool extends FlowBrainTool {
  final dynamic fb;
  PackUninstallTool(this.fb);

  @override
  String get name => 'pack.uninstall';

  @override
  String get description => 'Uninstall a knowledge pack by ID';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
        },
        'required': ['id'],
      };

  @override
  Future<Map<String, dynamic>> handler(Map<String, dynamic> args) async {
    final id = args['id'] as String;
    try {
      await fb.bundles.uninstall(id);
      return {'uninstalled': true, 'id': id};
    } catch (e) {
      _log.warning(
          'PackUninstallTool delegation failed, returning stub: $e');
      return {'uninstalled': false, 'stub': true};
    }
  }
}

// ---------------------------------------------------------------------------
// 8. PhilosophyStateTool
// ---------------------------------------------------------------------------

/// Retrieve the current philosophy state.
class PhilosophyStateTool extends FlowBrainTool {
  final dynamic fb;
  PhilosophyStateTool(this.fb);

  @override
  String get name => 'philosophy.state';

  @override
  String get description => 'Retrieve the current philosophy state';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {},
      };

  @override
  Future<Map<String, dynamic>> handler(Map<String, dynamic> args) async {
    try {
      final state = await fb.philosophy.getState();
      return {'state': state};
    } catch (e) {
      _log.warning(
          'PhilosophyStateTool delegation failed, returning stub: $e');
      return {'state': null, 'stub': true};
    }
  }
}

// ---------------------------------------------------------------------------
// 9. PipelineRunTool
// ---------------------------------------------------------------------------

/// Trigger a named ops pipeline.
class PipelineRunTool extends FlowBrainTool {
  final dynamic fb;
  PipelineRunTool(this.fb);

  @override
  String get name => 'pipeline.run';

  @override
  String get description => 'Trigger a named ops pipeline';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'pipeline': {'type': 'string'},
          'params': {'type': 'object'},
        },
        'required': ['pipeline'],
      };

  @override
  Future<Map<String, dynamic>> handler(Map<String, dynamic> args) async {
    final pipeline = args['pipeline'] as String;
    final params = args['params'] as Map<String, dynamic>? ?? {};
    try {
      final runId = await fb.ops.runPipeline(pipeline, params);
      return {'runId': runId, 'status': 'started'};
    } catch (e) {
      _log.warning('PipelineRunTool delegation failed, returning stub: $e');
      return {'runId': null, 'status': 'error', 'stub': true};
    }
  }
}

// ---------------------------------------------------------------------------
// 10. PipelineStatusTool
// ---------------------------------------------------------------------------

/// Check the status of a pipeline run.
class PipelineStatusTool extends FlowBrainTool {
  final dynamic fb;
  PipelineStatusTool(this.fb);

  @override
  String get name => 'pipeline.status';

  @override
  String get description => 'Check the status of a pipeline run';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'runId': {'type': 'string'},
        },
        'required': ['runId'],
      };

  @override
  Future<Map<String, dynamic>> handler(Map<String, dynamic> args) async {
    final runId = args['runId'] as String;
    try {
      final status = await fb.ops.getPipelineStatus(runId);
      return {'runId': runId, 'status': status};
    } catch (e) {
      _log.warning(
          'PipelineStatusTool delegation failed, returning stub: $e');
      return {'runId': runId, 'status': 'unknown', 'stub': true};
    }
  }
}

// ---------------------------------------------------------------------------
// ToolSetBuilder
// ---------------------------------------------------------------------------

/// Builds the standard set of 10 FlowBrain MCP tools.
///
/// Accepts a FlowBrain instance (as dynamic to avoid circular imports)
/// and returns all tool instances.
class ToolSetBuilder {
  /// Build all 10 standard FlowBrain tools.
  List<FlowBrainTool> build(dynamic fb) => [
        KnowledgeSaveTool(fb),
        KnowledgeQueryTool(fb),
        SkillExecuteTool(fb),
        AgentAskTool(fb),
        PackInstallTool(fb),
        PackListTool(fb),
        PackUninstallTool(fb),
        PhilosophyStateTool(fb),
        PipelineRunTool(fb),
        PipelineStatusTool(fb),
      ];
}
