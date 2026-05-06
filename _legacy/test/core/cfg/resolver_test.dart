/// Tests for the config-to-runtime resolver.
library;

import 'package:test/test.dart';
import 'package:flowbrain_core/src/core/cfg/resolver.dart';
import 'package:flowbrain_core/src/core/cfg/schema/flowbrain_config.dart';
import 'package:flowbrain_core/src/core/asm/errors.dart';

void main() {
  group('LlmHub', () {
    test('can be constructed with required fields', () {
      const hub = LlmHub(llmPort: null);
      expect(hub.llmPort, isNull);
      expect(hub.mcpServers, isNull);
      expect(hub.mcpClients, isNull);
      expect(hub.mcpPortAdapter, isNull);
    });
  });

  group('LlmHubFactory', () {
    test('create returns an LlmHub stub', () async {
      final config = LlmProviderConfig(
        type: 'claude',
        apiKey: SecretRef.parse(r'$env:TEST_KEY'),
      );
      final hub = await LlmHubFactory.create(config);
      expect(hub, isA<LlmHub>());
    });
  });

  group('StorageFactory', () {
    test('create accepts memory type', () async {
      const config = StorageProviderConfig(type: 'memory');
      final result = await StorageFactory.create(config);
      // Stub returns null for memory
      expect(result, isNull);
    });

    test('create accepts sqlite type', () async {
      const config = StorageProviderConfig(type: 'sqlite');
      final result = await StorageFactory.create(config);
      expect(result, isNull);
    });

    test('create throws RuntimeWiringError for unknown type', () async {
      const config = StorageProviderConfig(type: 'unknown_db');
      expect(
        () => StorageFactory.create(config),
        throwsA(isA<RuntimeWiringError>()),
      );
    });
  });
}
