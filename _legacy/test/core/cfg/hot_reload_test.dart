/// Tests for HotReloader and ConfigDiff.
library;

import 'package:test/test.dart';
import 'package:flowbrain_core/src/core/cfg/hot_reload.dart';
import 'package:flowbrain_core/src/core/cfg/schema/flowbrain_config.dart';

FlowBrainConfig _makeConfig({
  String profile = 'full',
  String llmType = 'claude',
  String storageType = 'memory',
  String apiKey = r'$env:KEY',
  Map<String, AgentDef>? agents,
  List<BundleRef>? bundles,
  PolicyConfig? policy,
  ObservabilityConfig? observability,
}) {
  return FlowBrainConfig(
    configVersion: 1,
    profile: profile,
    providers: ProvidersConfig(
      llm: LlmProviderConfig(
        type: llmType,
        apiKey: SecretRef.parse(apiKey),
      ),
      storage: StorageProviderConfig(type: storageType),
    ),
    agents: agents ?? const {},
    bundles: bundles ?? const [],
    policy: policy ?? const PolicyConfig(),
    observability: observability ?? const ObservabilityConfig(),
  );
}

void main() {
  group('ConfigDiff.compare', () {
    test('no changes yields empty diff', () {
      final a = _makeConfig();
      final b = _makeConfig();
      final diff = ConfigDiff.compare(a, b);

      expect(diff.hasChanges, isFalse);
      expect(diff.hasUnreloadable, isFalse);
      expect(diff.policyChanged, isFalse);
      expect(diff.agentsChanged, isFalse);
      expect(diff.bundlesChanged, isFalse);
      expect(diff.observabilityChanged, isFalse);
    });

    test('profile change is unreloadable', () {
      final a = _makeConfig(profile: 'full');
      final b = _makeConfig(profile: 'skillLlm');
      final diff = ConfigDiff.compare(a, b);

      expect(diff.hasUnreloadable, isTrue);
      expect(diff.unreloadableFields, contains('profile'));
    });

    test('llm type change is unreloadable', () {
      final a = _makeConfig(llmType: 'claude');
      final b = _makeConfig(llmType: 'openai');
      final diff = ConfigDiff.compare(a, b);

      expect(diff.hasUnreloadable, isTrue);
      expect(diff.unreloadableFields, contains('providers.llm.type'));
    });

    test('llm apiKey change is unreloadable', () {
      final a = _makeConfig(apiKey: r'$env:KEY_A');
      final b = _makeConfig(apiKey: r'$env:KEY_B');
      final diff = ConfigDiff.compare(a, b);

      expect(diff.hasUnreloadable, isTrue);
      expect(diff.unreloadableFields, contains('providers.llm.apiKey'));
    });

    test('storage type change is unreloadable', () {
      final a = _makeConfig(storageType: 'memory');
      final b = _makeConfig(storageType: 'sqlite');
      final diff = ConfigDiff.compare(a, b);

      expect(diff.hasUnreloadable, isTrue);
      expect(
          diff.unreloadableFields, contains('providers.storage.type'));
    });

    test('policy change is reloadable', () {
      final a = _makeConfig();
      final b = _makeConfig(
        policy: const PolicyConfig(defaultLanguage: 'ko'),
      );
      final diff = ConfigDiff.compare(a, b);

      expect(diff.hasUnreloadable, isFalse);
      expect(diff.policyChanged, isTrue);
      expect(diff.hasChanges, isTrue);
    });

    test('agents change is reloadable', () {
      final a = _makeConfig();
      final b = _makeConfig(
        agents: {
          'test': AgentDef(name: 'test', skills: ['chat']),
        },
      );
      final diff = ConfigDiff.compare(a, b);

      expect(diff.hasUnreloadable, isFalse);
      expect(diff.agentsChanged, isTrue);
    });

    test('bundles change is reloadable', () {
      final a = _makeConfig();
      final b = _makeConfig(
        bundles: [const BundleRef(source: 'test-bundle')],
      );
      final diff = ConfigDiff.compare(a, b);

      expect(diff.hasUnreloadable, isFalse);
      expect(diff.bundlesChanged, isTrue);
    });

    test('observability change is reloadable', () {
      final a = _makeConfig();
      final b = _makeConfig(
        observability: const ObservabilityConfig(
          exporters: ['log'],
          logLevel: LogLevel.debug,
        ),
      );
      final diff = ConfigDiff.compare(a, b);

      expect(diff.hasUnreloadable, isFalse);
      expect(diff.observabilityChanged, isTrue);
    });
  });

  group('HotReloader', () {
    late HotReloader reloader;

    setUp(() {
      reloader = HotReloader();
    });

    test('checkReloadability returns diff with no errors for reloadable change',
        () {
      final current = _makeConfig();
      final proposed = _makeConfig(
        policy: const PolicyConfig(defaultLanguage: 'ko'),
      );

      final diff = reloader.checkReloadability(current, proposed);
      expect(diff.hasUnreloadable, isFalse);
      expect(diff.policyChanged, isTrue);
    });

    test('assertReloadable throws ReloadError for unreloadable change', () {
      final current = _makeConfig(profile: 'full');
      final proposed = _makeConfig(profile: 'skillLlm');

      expect(
        () => reloader.assertReloadable(current, proposed),
        throwsA(isA<ReloadError>()),
      );
    });

    test('assertReloadable does not throw for reloadable change', () {
      final current = _makeConfig();
      final proposed = _makeConfig(
        agents: {
          'new-agent': AgentDef(name: 'new-agent', skills: ['chat']),
        },
      );

      // Should not throw
      reloader.assertReloadable(current, proposed);
    });
  });
}
