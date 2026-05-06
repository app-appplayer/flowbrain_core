/// FlowBrain — main assembly class per DDD §3.1.
///
/// Single entry point for the FlowBrain runtime. Assembles a
/// [KnowledgeSystem] from config, wires optional runtimes based on
/// [RuntimeProfile], and provides [boot], [serve], [ask], [reload],
/// and [shutdown] lifecycle methods.
library;

import 'dart:math' show Random;

import 'package:logging/logging.dart';
import 'package:mcp_knowledge/mcp_knowledge.dart'
    show KnowledgeSystem, KnowledgeConfig;

import '../cfg/schema/flowbrain_config.dart';
import 'runtime_profile.dart';
import 'ask_result.dart';

/// The FlowBrain assembler — top-level entry for the FlowBrain runtime.
///
/// Use [FlowBrain.boot] to create a fully assembled instance from a
/// [FlowBrainConfig]. The assembler resolves the [RuntimeProfile],
/// builds the [KnowledgeSystem], and wires all external interfaces.
class FlowBrain {
  static final _log = Logger('FlowBrain');
  static final _random = Random();

  /// The assembled knowledge system.
  final KnowledgeSystem knowledge;

  /// The runtime configuration.
  final FlowBrainConfig config;

  /// The active runtime profile.
  final RuntimeProfile profile;

  // Forward-reference placeholders for FEAT modules.
  // These will be replaced with concrete types when FEAT modules land.

  /// MCP hub binding (stub — FEAT-MCP will provide concrete type).
  final dynamic mcpHub;

  /// Agent registry (stub — FEAT-ROUTE will provide concrete type).
  final dynamic agents;

  /// Bundle installer (stub — FEAT-BUN will provide concrete type).
  final dynamic bundles;

  /// Observability binding (stub — FEAT-OBS will provide concrete type).
  final dynamic obs;

  // ignore: unused_element
  FlowBrain._({
    required this.knowledge,
    required this.config,
    required this.profile,
    this.mcpHub, // ignore: unused_element_parameter
    this.agents, // ignore: unused_element_parameter
    this.bundles, // ignore: unused_element_parameter
    this.obs, // ignore: unused_element_parameter
  });

  /// Internal constructor used by [Assembler] to create a fully
  /// assembled FlowBrain instance.
  // ignore: unused_element
  FlowBrain.assemble({
    required this.knowledge,
    required this.config,
    required this.profile,
    this.mcpHub, // ignore: unused_element_parameter
    this.agents, // ignore: unused_element_parameter
    this.bundles, // ignore: unused_element_parameter
    this.obs, // ignore: unused_element_parameter
  });

  /// Single entry: config -> fully assembled FlowBrain.
  ///
  /// Resolves the profile from config, builds the KnowledgeSystem with
  /// optional runtimes, and wires external interfaces.
  static Future<FlowBrain> boot({
    required FlowBrainConfig config,
  }) async {
    _log.info('Booting FlowBrain with profile: ${config.profile}');

    // Step 1: validate profile
    final profile = RuntimeProfile.fromString(config.profile);

    // Step 2: build KnowledgeSystem (stub assembler for now)
    //
    // Full assembly logic (secret resolution, LlmHub creation,
    // optional runtimes, KFL decorator, FEAT modules) will be
    // implemented in assembler.dart when FEAT modules are ready.
    final system = KnowledgeSystem(
      config: KnowledgeConfig.defaults,
      // Optional runtimes left null — profile-based wiring
      // will be added when runtime packages are integrated.
    );

    _log.info('KnowledgeSystem created for profile: ${profile.name}');

    // Step 3: assemble FlowBrain
    final fb = FlowBrain._(
      knowledge: system,
      config: config,
      profile: profile,
    );

    _log.info('FlowBrain boot complete');
    return fb;
  }

  /// Expose MCP tool set and begin serving.
  ///
  /// Stub — delegates to McpHubBinding.start() when FEAT-MCP lands.
  Future<void> serve() async {
    _log.info('FlowBrain.serve() — waiting for FEAT-MCP implementation');
  }

  /// High-level ask — routes to agent, executes, returns response.
  ///
  /// Stub implementation returns a placeholder. Full routing through
  /// AskPipeline will be wired when FEAT-ROUTE lands.
  Future<AskResult> ask(String request, {String? traceId}) async {
    final tid = traceId ?? _generateTraceId();
    _log.fine('FlowBrain.ask(traceId=$tid): $request');

    // Stub: return placeholder until AskPipeline is wired.
    return AskResult(
      response: '[stub] No agent pipeline configured yet.',
      agentId: 'default',
      traceId: tid,
    );
  }

  /// Reload hot-reloadable sections (bundles, agents, policy).
  ///
  /// Stub — delegates to core/cfg/hot_reload when CORE-CFG lands.
  Future<void> reload() async {
    _log.info('FlowBrain.reload() — stub');
  }

  /// Graceful shutdown.
  Future<void> shutdown() async {
    _log.info('FlowBrain shutting down');

    // Shutdown in reverse order of initialization.
    // mcpHub?.stop(), obs?.stop() will be called when FEAT modules land.
    await knowledge.shutdown();

    _log.info('FlowBrain shutdown complete');
  }

  /// Generate a random trace ID.
  static String _generateTraceId() {
    final hex = StringBuffer();
    for (var i = 0; i < 16; i++) {
      hex.write(_random.nextInt(16).toRadixString(16));
    }
    return hex.toString();
  }
}
