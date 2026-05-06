/// `flowbrain serve` command — loads config, boots FlowBrain, and starts
/// the MCP serve loop.
library;

import 'package:args/args.dart';
import 'package:logging/logging.dart';

final _log = Logger('flowbrain.core.boot.commands.serve');

/// Handles the `flowbrain serve` CLI command.
class ServeCommand {
  /// Build the [ArgParser] for the serve subcommand.
  static ArgParser parser() {
    return ArgParser()
      ..addOption('config',
          defaultsTo: './flowbrain.yaml', help: 'Path to config file')
      ..addOption('env',
          allowed: ['dev', 'staging', 'prod'],
          defaultsTo: 'dev',
          help: 'Environment (determines overlay)')
      ..addFlag('watch',
          negatable: false, help: 'Enable hot-reload on config changes');
  }

  /// Execute the serve command.
  ///
  /// Sequence:
  /// 1. Load config (with env overlay)
  /// 2. Validate — fail-fast on errors
  /// 3. FlowBrain.boot(config)
  /// 4. fb.serve() — start MCP servers
  /// 5. Wait for SIGINT/SIGTERM → fb.shutdown() → exit 0
  /// 6. If --watch: activate HotReloader
  static Future<int> run(ArgResults args) async {
    final configPath = args['config'] as String;
    final env = args['env'] as String;
    final watch = args['watch'] as bool;

    _log.info('Loading config from $configPath (env=$env)...');

    // Stub: actual config loading and boot delegates to CORE-CFG / CORE-ASM,
    // which are implemented by other agents.
    // TODO: Wire to FlowBrain.boot(config) once CORE-ASM is ready.

    _log.info('FlowBrain serve started.');
    if (watch) {
      _log.info('Hot-reload enabled. Watching for config changes...');
    }

    // The real implementation will:
    // 1. final config = await ConfigLoader.load(configPath, env: env);
    // 2. final validator = ConfigValidator();
    // 3. validator.validate(config); // throws ConfigError on failure
    // 4. final fb = await FlowBrain.boot(config);
    // 5. await fb.serve();
    // 6. Handle shutdown signals

    return 0;
  }
}
