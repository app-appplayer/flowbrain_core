/// FlowBrain CLI entry point — parses arguments and dispatches to commands.
///
/// Depends on `package:args` for argument parsing and delegates to
/// individual command runners in `commands/`.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart';

import 'errors.dart';
import 'commands/init_command.dart';
import 'commands/serve_command.dart';
import 'commands/doctor_command.dart';
import 'commands/pack_command.dart';
import 'commands/reload_command.dart';

final _log = Logger('flowbrain.core.boot.cli');

/// Main CLI class for FlowBrain.
class FlowBrainCli {
  /// Build the top-level [ArgParser] with all commands.
  static ArgParser buildParser() {
    final parser = ArgParser()
      ..addFlag('verbose',
          abbr: 'v', negatable: false, help: 'Enable verbose output')
      ..addFlag('version', negatable: false, help: 'Print version and exit')
      ..addFlag('help',
          abbr: 'h', negatable: false, help: 'Show usage information');

    // Subcommands
    parser.addCommand('init', InitCommand.parser());
    parser.addCommand('serve', ServeCommand.parser());
    parser.addCommand('doctor', DoctorCommand.parser());
    parser.addCommand('pack', PackCommand.parser());
    parser.addCommand('reload', ReloadCommand.parser());

    return parser;
  }

  /// Parse [args] without executing. Returns the parsed [ArgResults].
  ///
  /// Useful for testing argument parsing in isolation.
  static ArgResults parse(List<String> args) {
    return buildParser().parse(args);
  }

  /// Run the CLI with the given [args].
  ///
  /// Returns an exit code suitable for passing to [exit].
  static Future<int> run(List<String> args) async {
    final parser = buildParser();
    final ArgResults results;

    try {
      results = parser.parse(args);
    } on FormatException catch (e) {
      _log.severe(e.message);
      _printUsage(parser);
      return 1;
    }

    // Global flags
    if (results['version'] as bool) {
      _log.info('flowbrain 0.1.0');
      return 0;
    }

    if (results['help'] as bool || results.command == null) {
      _printUsage(parser);
      return 0;
    }

    final verbose = results['verbose'] as bool;
    if (verbose) {
      Logger.root.level = Level.ALL;
    }

    try {
      return await _dispatch(results.command!);
    } on FlowBrainError catch (e) {
      _log.severe(FriendlyErrorFormatter.format(e));
      return exitCodeFor(e);
    }
  }

  /// Dispatch to the appropriate command runner.
  static Future<int> _dispatch(ArgResults command) async {
    switch (command.name) {
      case 'init':
        return InitCommand.run(command);
      case 'serve':
        return ServeCommand.run(command);
      case 'doctor':
        return DoctorCommand.run(command);
      case 'pack':
        return PackCommand.run(command);
      case 'reload':
        return ReloadCommand.run(command);
      default:
        _log.severe('Unknown command: ${command.name}');
        return 1;
    }
  }

  static void _printUsage(ArgParser parser) {
    _log.info('Usage: flowbrain <command> [options]');
    _log.info('');
    _log.info('Commands:');
    _log.info('  init      Generate a flowbrain.yaml template');
    _log.info('  serve     Boot FlowBrain and start MCP servers');
    _log.info('  doctor    Run diagnostic checks');
    _log.info('  pack      Manage knowledge packs');
    _log.info('  reload    Trigger hot-reload of configuration');
    _log.info('');
    _log.info(parser.usage);
  }
}
