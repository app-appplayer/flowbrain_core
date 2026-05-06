import 'dart:io';

import 'package:test/test.dart';
import 'package:flowbrain_core/src/core/cfg/schema/flowbrain_config.dart';
import 'package:flowbrain_core/src/core/cfg/secret_resolver.dart';

void main() {
  group('SecretResolver', () {
    test('resolves env secret from environment', () async {
      final resolver = SecretResolver(
        environmentOverrides: {'TEST_KEY': 'test-value-123'},
      );
      final config = _buildConfig(
        apiKey: const EnvSecret('TEST_KEY'),
      );
      final secrets = await resolver.resolveAll(config);
      final value = secrets.get(const EnvSecret('TEST_KEY'));
      expect(value, isNotNull);
      expect(value!.reveal(), equals('test-value-123'));
    });

    test('env secret throws when variable not set', () async {
      final resolver = SecretResolver(
        environmentOverrides: {},
      );
      final config = _buildConfig(
        apiKey: const EnvSecret('NONEXISTENT_VAR_XYZ'),
      );
      expect(
        () => resolver.resolveAll(config),
        throwsA(isA<SecretError>()),
      );
    });

    test('resolves file secret', () async {
      final tmpDir = Directory.systemTemp.createTempSync('secret_test_');
      try {
        final secretFile = File('${tmpDir.path}/secret.txt');
        secretFile.writeAsStringSync('  file-secret-value  \n');

        final resolver = SecretResolver();
        final config = _buildConfig(
          apiKey: FileSecret(secretFile.path),
        );
        final secrets = await resolver.resolveAll(config);
        final value = secrets.get(FileSecret(secretFile.path));
        expect(value!.reveal(), equals('file-secret-value'));
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('resolves vault secret through adapter', () async {
      final adapter = _TestVaultAdapter({'my/key': 'vault-value'});
      final resolver = SecretResolver(vaultAdapters: [adapter]);
      final config = _buildConfig(
        apiKey: const VaultSecret('my/key'),
      );
      final secrets = await resolver.resolveAll(config);
      final value = secrets.get(const VaultSecret('my/key'));
      expect(value!.reveal(), equals('vault-value'));
    });

    test('vault secret throws when key not found', () async {
      final adapter = _TestVaultAdapter({});
      final resolver = SecretResolver(vaultAdapters: [adapter]);
      final config = _buildConfig(
        apiKey: const VaultSecret('missing/key'),
      );
      expect(
        () => resolver.resolveAll(config),
        throwsA(isA<SecretError>()),
      );
    });

    test('inline secret resolves with fromInline flag', () async {
      final resolver = SecretResolver();
      final config = _buildConfig(
        apiKey: const InlineSecret('plain-text'),
      );
      final secrets = await resolver.resolveAll(config);
      final value = secrets.get(const InlineSecret('plain-text'));
      expect(value!.reveal(), equals('plain-text'));
      expect(value.fromInline, isTrue);
    });
  });

  group('SecretValue masking', () {
    test('toString returns masked value', () {
      final sv = SecretValue('super-secret');
      expect(sv.toString(), equals('***'));
    });

    test('reveal exposes plaintext', () {
      final sv = SecretValue('super-secret');
      expect(sv.reveal(), equals('super-secret'));
    });
  });
}

FlowBrainConfig _buildConfig({required SecretRef apiKey}) {
  return FlowBrainConfig(
    configVersion: 1,
    profile: 'full',
    providers: ProvidersConfig(
      llm: LlmProviderConfig(
        type: 'claude',
        apiKey: apiKey,
      ),
      storage: const StorageProviderConfig(type: 'memory'),
    ),
    bundles: const [],
    agents: const {},
    observability: ObservabilityConfig(),
    policy: PolicyConfig(),
    extensions: const {},
  );
}

class _TestVaultAdapter implements VaultAdapter {
  final Map<String, String> _secrets;
  _TestVaultAdapter(this._secrets);

  @override
  String get name => 'test';

  @override
  Future<String?> read(String key) async => _secrets[key];
}
