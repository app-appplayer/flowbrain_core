/// Assembler — assembly logic for FlowBrain per DDD core-asm.md section 3.2.
///
/// Encapsulates the multi-step assembly sequence: validate profile,
/// resolve secrets, build providers, create optional runtimes,
/// construct KnowledgeSystem, wire FEAT modules, and return a
/// fully assembled FlowBrain instance.
///
/// Currently delegates back to [FlowBrain.boot] for the actual
/// assembly. When full FEAT module wiring is ready, the assembly
/// steps outlined in DDD core-asm.md section 3.2 will be implemented here.
library;

import 'package:logging/logging.dart';
import 'package:mcp_knowledge/mcp_knowledge.dart'
    show KnowledgeSystem, KnowledgeConfig;

import '../cfg/schema/flowbrain_config.dart';
import 'flowbrain.dart';
import 'runtime_profile.dart';

final _log = Logger('flowbrain.core.asm.assembler');

/// Assembles a fully wired [FlowBrain] instance from configuration.
///
/// Assembly sequence (per DDD core-asm.md section 3.2):
/// 1. Validate profile compatibility
/// 2. Resolve secrets and build providers
/// 3. Create optional runtimes based on profile
/// 4. Build KnowledgePorts container
/// 5. Create KnowledgeSystem
/// 6. Wrap LlmPort with KFL decorator
/// 7. Wire FEAT modules (agents, bundles, observability, MCP hub)
/// 8. Return assembled FlowBrain
class Assembler {
  /// Assemble a [FlowBrain] from the given [config].
  ///
  /// This is the canonical entry point for full assembly. Currently
  /// provides a stub implementation that creates a minimal FlowBrain.
  /// Full wiring will be added as FEAT modules mature.
  static Future<FlowBrain> assemble(FlowBrainConfig config) async {
    _log.info('Assembler.assemble: starting assembly');

    // Step 1: validate profile
    final profile = RuntimeProfile.fromString(config.profile);
    _log.fine('Profile resolved: ${profile.name}');

    // Step 2: build KnowledgeSystem (stub — full wiring pending)
    final system = KnowledgeSystem(
      config: KnowledgeConfig.defaults,
    );

    _log.info('KnowledgeSystem created for profile: ${profile.name}');

    // Steps 3-8 are stubs — full assembly logic will be added
    // when FEAT modules (MCP hub, agent registry, bundle installer,
    // observability binding) are ready for integration.

    return FlowBrain.assemble(
      knowledge: system,
      config: config,
      profile: profile,
    );
  }
}
