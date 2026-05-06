/// `flowbrain pack` command — manages knowledge packs.
///
/// Subcommands: install, list, uninstall, update, build, test, scaffold.
library;

import 'package:args/args.dart';
import 'package:logging/logging.dart';

final _log = Logger('flowbrain.core.boot.commands.pack');

/// Handles the `flowbrain pack <subcommand>` CLI commands.
class PackCommand {
  /// Build the [ArgParser] for the pack command and its subcommands.
  static ArgParser parser() {
    final packParser = ArgParser()
      ..addFlag('offline',
          negatable: false,
          help: 'Operate directly on storage without a running FlowBrain');

    // install <source>
    packParser.addCommand(
      'install',
      ArgParser()
        ..addOption('version', abbr: 'v', help: 'Specific version to install'),
    );

    // list
    packParser.addCommand('list', ArgParser());

    // uninstall <id>
    packParser.addCommand('uninstall', ArgParser());

    // update <id>[@version]
    packParser.addCommand(
      'update',
      ArgParser()
        ..addOption('version', abbr: 'v', help: 'Target version for update'),
    );

    // build <dir>
    packParser.addCommand('build', ArgParser());

    // test <path>
    packParser.addCommand('test', ArgParser());

    // scaffold <name>
    packParser.addCommand('scaffold', ArgParser());

    return packParser;
  }

  /// Execute the pack command by dispatching to the appropriate subcommand.
  static Future<int> run(ArgResults args) async {
    final sub = args.command;
    if (sub == null) {
      _log.severe('No pack subcommand specified. '
          'Available: install, list, uninstall, update, build, test, scaffold');
      return 1;
    }

    switch (sub.name) {
      case 'install':
        return _install(sub);
      case 'list':
        return _list(sub);
      case 'uninstall':
        return _uninstall(sub);
      case 'update':
        return _update(sub);
      case 'build':
        return _build(sub);
      case 'test':
        return _test(sub);
      case 'scaffold':
        return _scaffold(sub);
      default:
        _log.severe('Unknown pack subcommand: ${sub.name}');
        return 1;
    }
  }

  // ---- Subcommand stubs (delegate to FEAT-BUN) ----

  static Future<int> _install(ArgResults args) async {
    if (args.rest.isEmpty) {
      _log.severe('Usage: flowbrain pack install <source>');
      return 1;
    }
    final source = args.rest.first;
    final version = args['version'] as String?;
    _log.info('Installing pack from $source'
        '${version != null ? " (version $version)" : ""}...');
    // TODO: Delegate to BundleInstaller.install(source, version: version)
    return 0;
  }

  static Future<int> _list(ArgResults args) async {
    _log.info('Installed packs:');
    // TODO: Delegate to BundleInstaller.list()
    _log.info('  (none)');
    return 0;
  }

  static Future<int> _uninstall(ArgResults args) async {
    if (args.rest.isEmpty) {
      _log.severe('Usage: flowbrain pack uninstall <id>');
      return 1;
    }
    final id = args.rest.first;
    _log.info('Uninstalling pack: $id...');
    // TODO: Delegate to BundleInstaller.uninstall(id)
    return 0;
  }

  static Future<int> _update(ArgResults args) async {
    if (args.rest.isEmpty) {
      _log.severe('Usage: flowbrain pack update <id>[@version]');
      return 1;
    }
    final target = args.rest.first;
    final version = args['version'] as String?;
    _log.info('Updating pack: $target'
        '${version != null ? " to version $version" : ""}...');
    // TODO: Delegate to BundleInstaller.update(target, version: version)
    return 0;
  }

  static Future<int> _build(ArgResults args) async {
    if (args.rest.isEmpty) {
      _log.severe('Usage: flowbrain pack build <dir>');
      return 1;
    }
    final dir = args.rest.first;
    _log.info('Building pack from directory: $dir...');
    // TODO: Delegate to pack builder
    return 0;
  }

  static Future<int> _test(ArgResults args) async {
    if (args.rest.isEmpty) {
      _log.severe('Usage: flowbrain pack test <path>');
      return 1;
    }
    final path = args.rest.first;
    _log.info('Testing pack at: $path...');
    // TODO: Delegate to pack tester
    return 0;
  }

  static Future<int> _scaffold(ArgResults args) async {
    if (args.rest.isEmpty) {
      _log.severe('Usage: flowbrain pack scaffold <name>');
      return 1;
    }
    final name = args.rest.first;
    _log.info('Scaffolding new pack: $name...');
    // TODO: Generate pack template directory
    return 0;
  }
}
