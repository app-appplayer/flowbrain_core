/// `flowbrain reload` command — triggers a hot-reload of configuration.
///
/// Sends a reload signal to the running FlowBrain instance, either via
/// HUP signal or loopback MCP `internal.reload` call per DDD core-boot.md
/// section 3.5.
library;

import 'package:args/args.dart';
import 'package:logging/logging.dart';

final _log = Logger('flowbrain.core.boot.commands.reload');

/// Handles the `flowbrain reload` CLI command.
class ReloadCommand {
  /// Build the [ArgParser] for the reload subcommand.
  static ArgParser parser() {
    return ArgParser()
      ..addOption('config',
          defaultsTo: './flowbrain.yaml', help: 'Path to config file')
      ..addFlag('force',
          negatable: false,
          help: 'Force reload even if unreloadable fields changed');
  }

  /// Execute the reload command.
  ///
  /// Triggers a hot-reload of the running FlowBrain configuration.
  /// Reloadable sections: bundles, agents, policy, observability.
  /// Non-reloadable fields (profile, providers) require a full restart.
  static Future<int> run(ArgResults args) async {
    final configPath = args['config'] as String;
    final force = args['force'] as bool;

    _log.info('Triggering FlowBrain hot-reload...');
    _log.info('Config: $configPath');
    if (force) {
      _log.info('Force mode enabled');
    }

    // Stub: actual implementation will send HUP signal or call
    // loopback MCP internal.reload endpoint.
    _log.info(
      'Reload command stub — '
      'will connect to running FlowBrain instance when fully wired.',
    );

    return 0;
  }
}
