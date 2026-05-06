/// Tests for FlowBrain class per DDD §3.1.
library;

import 'package:test/test.dart';
import 'package:flowbrain_core/src/core/asm/flowbrain.dart';
import 'package:flowbrain_core/src/core/asm/runtime_profile.dart';
import 'package:flowbrain_core/src/core/asm/ask_result.dart';
import 'package:flowbrain_core/src/core/cfg/schema/flowbrain_config.dart';

/// Build a minimal FlowBrainConfig for testing.
FlowBrainConfig _testConfig(String profile) {
  return FlowBrainConfig(
    configVersion: 1,
    profile: profile,
    providers: ProvidersConfig(
      llm: LlmProviderConfig(
        type: 'stub',
        apiKey: InlineSecret('test-key'),
      ),
      storage: StorageProviderConfig(type: 'memory'),
    ),
  );
}

void main() {
  group('FlowBrain', () {
    group('boot', () {
      test('boots with stub config and full profile', () async {
        final config = _testConfig('full');
        final fb = await FlowBrain.boot(config: config);

        expect(fb, isNotNull);
        expect(fb.profile, RuntimeProfile.full);
        expect(fb.config, same(config));
        expect(fb.knowledge, isNotNull);
      });

      test('boots with readOnly profile', () async {
        final config = _testConfig('readOnly');
        final fb = await FlowBrain.boot(config: config);

        expect(fb.profile, RuntimeProfile.readOnly);
      });

      test('boots with skillLlm profile', () async {
        final config = _testConfig('skillLlm');
        final fb = await FlowBrain.boot(config: config);

        expect(fb.profile, RuntimeProfile.skillLlm);
      });
    });

    group('ask', () {
      test('returns AskResult with response', () async {
        final config = _testConfig('full');
        final fb = await FlowBrain.boot(config: config);

        final result = await fb.ask('test request');
        expect(result, isA<AskResult>());
        expect(result.traceId, isNotEmpty);
      });

      test('passes traceId through', () async {
        final config = _testConfig('full');
        final fb = await FlowBrain.boot(config: config);

        final result = await fb.ask('test', traceId: 'custom-trace');
        expect(result.traceId, 'custom-trace');
      });
    });

    group('shutdown', () {
      test('shuts down gracefully', () async {
        final config = _testConfig('full');
        final fb = await FlowBrain.boot(config: config);

        // Should not throw.
        await fb.shutdown();
      });

      test('can shut down immediately after boot', () async {
        final config = _testConfig('ingestOnly');
        final fb = await FlowBrain.boot(config: config);
        await fb.shutdown();
      });
    });

    group('reload', () {
      test('reload completes without error', () async {
        final config = _testConfig('full');
        final fb = await FlowBrain.boot(config: config);

        // Stub reload should complete without error.
        await fb.reload();
      });
    });
  });
}
