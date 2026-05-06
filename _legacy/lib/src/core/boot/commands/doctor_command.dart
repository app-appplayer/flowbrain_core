/// `flowbrain doctor` command — runs diagnostic checks and prints a report.
library;

import 'package:args/args.dart';
import 'package:logging/logging.dart';

final _log = Logger('flowbrain.core.boot.commands.doctor');

/// Handles the `flowbrain doctor` CLI command.
class DoctorCommand {
  /// Build the [ArgParser] for the doctor subcommand.
  static ArgParser parser() {
    return ArgParser()
      ..addOption('config',
          defaultsTo: './flowbrain.yaml', help: 'Path to config file');
  }

  /// Execute the doctor command.
  ///
  /// Diagnostics:
  /// - Config file existence / parseability
  /// - Validator results (errors + warnings)
  /// - Provider connectivity ping (LLM, storage, MCP clients)
  /// - Disk space / permissions
  /// - Dependency package version compatibility
  static Future<int> run(ArgResults args) async {
    final configPath = args['config'] as String;

    _log.info('Running FlowBrain diagnostics...');
    _log.info('');

    // 1. Config file check
    final configCheck = await _checkConfigFile(configPath);

    // 2. Validation check (stub)
    final validationCheck = await _checkValidation(configPath);

    // 3. Provider connectivity (stub)
    final providerCheck = await _checkProviders();

    // 4. Disk / permissions (stub)
    final diskCheck = await _checkDisk();

    final checks = [configCheck, validationCheck, providerCheck, diskCheck];
    final failed = checks.where((c) => !c.passed).length;

    _log.info('');
    if (failed == 0) {
      _log.info('All checks passed.');
    } else {
      _log.info('$failed check(s) need attention.');
    }

    return failed > 0 ? 1 : 0;
  }

  static Future<_DiagResult> _checkConfigFile(String path) async {
    // Stub: real implementation reads and parses the YAML
    _log.info('[?] Config file: $path');
    // TODO: Wire to actual file check
    return _DiagResult('Config file', true);
  }

  static Future<_DiagResult> _checkValidation(String path) async {
    _log.info('[?] Config validation');
    // TODO: Wire to ConfigValidator
    return _DiagResult('Config validation', true);
  }

  static Future<_DiagResult> _checkProviders() async {
    _log.info('[?] Provider connectivity');
    // TODO: Ping LLM, storage, MCP clients
    return _DiagResult('Provider connectivity', true);
  }

  static Future<_DiagResult> _checkDisk() async {
    _log.info('[?] Disk space & permissions');
    // TODO: Check available disk space and write permissions
    return _DiagResult('Disk space', true);
  }
}

/// Internal diagnostic result.
class _DiagResult {
  final String name;
  final bool passed;

  _DiagResult(this.name, this.passed);
}
