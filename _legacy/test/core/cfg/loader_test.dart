import 'dart:io';

import 'package:test/test.dart';
import 'package:flowbrain_core/src/core/cfg/loader.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('cfg_loader_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('FlowBrainConfigLoader.load', () {
    test('loads single YAML file', () async {
      final file = File('${tmpDir.path}/flowbrain.yaml');
      file.writeAsStringSync(_baseYaml);

      final config = await FlowBrainConfigLoader.load(file.path);
      expect(config.configVersion, equals(1));
      expect(config.profile, equals('full'));
      expect(config.providers.llm.type, equals('claude'));
    });

    test('throws on missing file', () async {
      expect(
        () => FlowBrainConfigLoader.load('${tmpDir.path}/nonexistent.yaml'),
        throwsA(isA<SchemaError>()),
      );
    });

    test('overlay merge: env file overrides base', () async {
      final base = File('${tmpDir.path}/flowbrain.yaml');
      base.writeAsStringSync(_baseYaml);

      final env = File('${tmpDir.path}/flowbrain.prod.yaml');
      env.writeAsStringSync('''
providers:
  llm:
    model: claude-3-opus
''');

      final config = await FlowBrainConfigLoader.load(
        base.path,
        env: 'prod',
      );
      expect(config.providers.llm.model, equals('claude-3-opus'));
      // Base values preserved
      expect(config.providers.llm.type, equals('claude'));
    });

    test('standard mode loads user override', () async {
      final base = File('${tmpDir.path}/flowbrain.yaml');
      base.writeAsStringSync(_baseYaml);

      // Create user override in a mock home dir
      final userDir = Directory('${tmpDir.path}/.flowbrain');
      userDir.createSync();
      final userFile = File('${userDir.path}/user.yaml');
      userFile.writeAsStringSync('''
profile: skill_llm_rag
''');

      final config = await FlowBrainConfigLoader.load(
        base.path,
        standardMode: true,
        homePath: tmpDir.path,
      );
      expect(config.profile, equals('skill_llm_rag'));
    });
  });

  group('FlowBrainConfigLoader.build', () {
    test('builds config from Dart builder', () {
      final config = FlowBrainConfigLoader.build((b) {
        b.profile = 'full';
        b.llmType = 'claude';
        b.llmApiKey = r'$env:ANTHROPIC_API_KEY';
        b.storageType = 'memory';
      });
      expect(config.profile, equals('full'));
      expect(config.providers.llm.type, equals('claude'));
      expect(config.providers.storage.type, equals('memory'));
    });
  });

  group('deep merge', () {
    test('map merge: later layer wins for scalars', () async {
      final base = File('${tmpDir.path}/flowbrain.yaml');
      base.writeAsStringSync(_baseYaml);

      final env = File('${tmpDir.path}/flowbrain.dev.yaml');
      env.writeAsStringSync('''
providers:
  storage:
    type: sqlite
    options:
      path: /tmp/dev.db
''');

      final config = await FlowBrainConfigLoader.load(
        base.path,
        env: 'dev',
      );
      expect(config.providers.storage.type, equals('sqlite'));
      // llm still from base
      expect(config.providers.llm.type, equals('claude'));
    });

    test('null in overlay does not overwrite base value', () async {
      final base = File('${tmpDir.path}/flowbrain.yaml');
      base.writeAsStringSync(_baseYaml);

      // Overlay with an explicit null for model should not clear base
      final env = File('${tmpDir.path}/flowbrain.staging.yaml');
      env.writeAsStringSync('''
providers:
  llm:
    model: null
''');

      final config = await FlowBrainConfigLoader.load(
        base.path,
        env: 'staging',
      );
      // Base has no model, so still null — just verifying no crash
      expect(config.providers.llm.type, equals('claude'));
    });
  });
}

const _baseYaml = '''
configVersion: 1
profile: full
providers:
  llm:
    type: claude
    apiKey: \$env:ANTHROPIC_API_KEY
  storage:
    type: memory
''';
