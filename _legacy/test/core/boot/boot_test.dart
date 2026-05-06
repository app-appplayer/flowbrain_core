import 'package:test/test.dart';

import 'package:flowbrain_core/src/core/boot/cli.dart';
import 'package:flowbrain_core/src/core/boot/errors.dart';

void main() {
  group('CLI arg parsing', () {
    test('parses "init" command', () {
      final result = FlowBrainCli.parse(['init']);
      expect(result.command?.name, 'init');
    });

    test('parses "init" with --profile and --force', () {
      final result = FlowBrainCli.parse([
        'init',
        '--profile=server',
        '--force',
      ]);
      expect(result.command?.name, 'init');
      expect(result.command?['profile'], 'server');
      expect(result.command?['force'], isTrue);
    });

    test('parses "init" with --output', () {
      final result = FlowBrainCli.parse([
        'init',
        '--output=custom.yaml',
      ]);
      expect(result.command?.name, 'init');
      expect(result.command?['output'], 'custom.yaml');
    });

    test('parses "serve" command', () {
      final result = FlowBrainCli.parse(['serve']);
      expect(result.command?.name, 'serve');
    });

    test('parses "serve" with --config and --env', () {
      final result = FlowBrainCli.parse([
        'serve',
        '--config=custom.yaml',
        '--env=prod',
      ]);
      expect(result.command?.name, 'serve');
      expect(result.command?['config'], 'custom.yaml');
      expect(result.command?['env'], 'prod');
    });

    test('parses "serve" with --watch flag', () {
      final result = FlowBrainCli.parse([
        'serve',
        '--watch',
      ]);
      expect(result.command?.name, 'serve');
      expect(result.command?['watch'], isTrue);
    });

    test('parses "doctor" command', () {
      final result = FlowBrainCli.parse(['doctor']);
      expect(result.command?.name, 'doctor');
    });

    test('parses "doctor" with --config', () {
      final result = FlowBrainCli.parse([
        'doctor',
        '--config=custom.yaml',
      ]);
      expect(result.command?.name, 'doctor');
      expect(result.command?['config'], 'custom.yaml');
    });

    test('parses "pack" with subcommand "install"', () {
      final result = FlowBrainCli.parse(['pack', 'install', 'some-source']);
      expect(result.command?.name, 'pack');
    });

    test('parses "pack" with subcommand "list"', () {
      final result = FlowBrainCli.parse(['pack', 'list']);
      expect(result.command?.name, 'pack');
    });

    test('parses --verbose flag', () {
      final result = FlowBrainCli.parse(['--verbose', 'doctor']);
      expect(result['verbose'], isTrue);
    });

    test('parses --version flag', () {
      final result = FlowBrainCli.parse(['--version']);
      expect(result['version'], isTrue);
    });
  });

  group('FlowBrainError hierarchy', () {
    test('ConfigError is a FlowBrainError', () {
      const err = ConfigError('bad config', path: 'flowbrain.yaml');
      expect(err, isA<FlowBrainError>());
      expect(err.path, 'flowbrain.yaml');
    });

    test('SchemaError is a ConfigError', () {
      const err = SchemaError('invalid schema', path: 'x.yaml');
      expect(err, isA<ConfigError>());
    });

    test('ValidationError from boot is a ConfigError', () {
      const err = ConfigValidationError('missing field', path: 'x.yaml');
      expect(err, isA<ConfigError>());
    });

    test('SecretError is a ConfigError', () {
      const err = SecretError('secret not found', path: 'x.yaml');
      expect(err, isA<ConfigError>());
    });

    test('MigrationError is a ConfigError', () {
      const err = MigrationError('migration failed', path: 'x.yaml');
      expect(err, isA<ConfigError>());
    });

    test('BundleError is a FlowBrainError', () {
      const err = BundleError('bundle broken');
      expect(err, isA<FlowBrainError>());
    });

    test('IntegrityError is a BundleError', () {
      const err = IntegrityError('checksum mismatch');
      expect(err, isA<BundleError>());
    });

    test('SchemaVersionError is a BundleError', () {
      const err = SchemaVersionError('version mismatch');
      expect(err, isA<BundleError>());
    });

    test('RollbackError is a BundleError', () {
      const err = RollbackError('rollback failed');
      expect(err, isA<BundleError>());
    });

    test('RoutingError is a FlowBrainError', () {
      const err = RoutingError('no route');
      expect(err, isA<FlowBrainError>());
    });

    test('McpBindingError is a FlowBrainError', () {
      const err = McpBindingError('binding failed');
      expect(err, isA<FlowBrainError>());
    });
  });

  group('FriendlyErrorFormatter', () {
    test('formats ConfigError with path, line, and suggestion', () {
      const err = ConfigError(
        'unknown key "provider"',
        path: 'flowbrain.yaml',
        line: 12,
        suggestion: 'Did you mean "providers"?',
      );
      final output = FriendlyErrorFormatter.format(err);

      expect(output, contains('flowbrain.yaml'));
      expect(output, contains('12'));
      expect(output, contains('unknown key "provider"'));
      expect(output, contains('Did you mean "providers"?'));
      expect(output, contains('flowbrain doctor'));
    });

    test('formats ConfigError without line gracefully', () {
      const err = ConfigError('missing file', path: 'flowbrain.yaml');
      final output = FriendlyErrorFormatter.format(err);

      expect(output, contains('flowbrain.yaml'));
      expect(output, contains('missing file'));
    });

    test('formats AssemblyError', () {
      const err = AssemblyError('wiring failed');
      final output = FriendlyErrorFormatter.format(err);

      expect(output, contains('wiring failed'));
    });

    test('formats BundleError', () {
      const err = BundleError('integrity check failed');
      final output = FriendlyErrorFormatter.format(err);

      expect(output, contains('integrity check failed'));
    });

    test('formats unknown FlowBrainError with toString fallback', () {
      const err = McpBindingError('port conflict');
      final output = FriendlyErrorFormatter.format(err);

      expect(output, contains('port conflict'));
    });
  });

  group('Exit codes', () {
    test('exitCodeFor returns correct codes per DDD', () {
      expect(exitCodeFor(const FlowBrainError('generic')), 1);
      expect(
          exitCodeFor(const ConfigError('bad', path: 'x')), 2);
      expect(exitCodeFor(const AssemblyError('asm')), 3);
      expect(exitCodeFor(const BundleError('bun')), 4);
      expect(exitCodeFor(const RoutingError('route')), 5);
      expect(exitCodeFor(const McpBindingError('mcp')), 5);
    });
  });
}
