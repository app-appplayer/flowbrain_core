import 'package:test/test.dart';
import 'package:flowbrain_core/src/core/cfg/schema/flowbrain_config.dart';
import 'package:flowbrain_core/src/core/cfg/validator.dart';

void main() {
  group('ConfigValidator', () {
    test('valid minimal config produces no errors', () {
      final config = _buildConfig();
      final report = ConfigValidator.validate(config);
      expect(report.isValid, isTrue);
      expect(report.errors, isEmpty);
    });

    test('detects inline secret as error', () {
      final config = _buildConfig(
        llmApiKey: const InlineSecret('sk-plaintext-key'),
      );
      final report = ConfigValidator.validate(config);
      expect(report.hasErrors, isTrue);
      expect(
        report.errors.any((e) => e.message.contains('inline secret')),
        isTrue,
      );
    });

    test('inline secret downgraded to warning when allowed', () {
      final config = _buildConfig(
        llmApiKey: const InlineSecret('sk-plaintext-key'),
      );
      final report = ConfigValidator.validate(
        config,
        inlineSecretsAllowed: true,
      );
      expect(report.isValid, isTrue);
      expect(
        report.warnings.any((w) => w.message.contains('inline secret')),
        isTrue,
      );
    });

    test('detects unknown LLM provider type', () {
      final config = _buildConfig(llmType: 'antropic');
      final report = ConfigValidator.validate(config);
      expect(report.hasErrors, isTrue);
      expect(
        report.errors.any((e) => e.message.contains('Unknown LLM provider')),
        isTrue,
      );
    });

    test('accepts known LLM provider types', () {
      for (final type in [
        'claude',
        'openai',
        'gemini',
        'bedrock',
        'cohere',
        'groq',
        'mistral',
        'together',
        'vertex_ai',
        'custom',
      ]) {
        final config = _buildConfig(llmType: type);
        final report = ConfigValidator.validate(config);
        expect(
          report.errors.where((e) => e.message.contains('LLM provider')),
          isEmpty,
          reason: 'Provider "$type" should be accepted',
        );
      }
    });

    test('detects duplicate MCP server ports', () {
      final config = _buildConfig(
        mcpServers: [
          McpServerRef(
            id: 'srv1',
            transport: McpTransport.http,
            port: 8080,
          ),
          McpServerRef(
            id: 'srv2',
            transport: McpTransport.http,
            port: 8080,
          ),
        ],
      );
      final report = ConfigValidator.validate(config);
      expect(
        report.errors.any((e) => e.message.contains('duplicate')),
        isTrue,
      );
    });

    test('detects duplicate MCP client ids', () {
      final config = _buildConfig(
        mcpClients: [
          McpClientRef(
            id: 'same-id',
            transport: McpTransport.http,
            url: 'https://a.com',
          ),
          McpClientRef(
            id: 'same-id',
            transport: McpTransport.http,
            url: 'https://b.com',
          ),
        ],
      );
      final report = ConfigValidator.validate(config);
      expect(
        report.errors.any((e) => e.message.contains('duplicate')),
        isTrue,
      );
    });

    test('http client requires url', () {
      final config = _buildConfig(
        mcpClients: [
          McpClientRef(
            id: 'no-url',
            transport: McpTransport.http,
          ),
        ],
      );
      final report = ConfigValidator.validate(config);
      expect(
        report.errors.any((e) => e.message.contains('url')),
        isTrue,
      );
    });

    test('stdio client requires command', () {
      final config = _buildConfig(
        mcpClients: [
          McpClientRef(
            id: 'no-cmd',
            transport: McpTransport.stdio,
          ),
        ],
      );
      final report = ConfigValidator.validate(config);
      expect(
        report.errors.any((e) => e.message.contains('command')),
        isTrue,
      );
    });

    test('throwIfErrors throws when errors exist', () {
      final config = _buildConfig(llmType: 'nope');
      final report = ConfigValidator.validate(config);
      expect(() => report.throwIfErrors(), throwsA(isA<ValidationError>()));
    });

    test('throwIfErrors is no-op when valid', () {
      final config = _buildConfig();
      final report = ConfigValidator.validate(config);
      report.throwIfErrors(); // should not throw
    });
  });
}

FlowBrainConfig _buildConfig({
  String llmType = 'claude',
  SecretRef llmApiKey = const EnvSecret('ANTHROPIC_API_KEY'),
  List<McpServerRef>? mcpServers,
  List<McpClientRef>? mcpClients,
}) {
  final mcp = (mcpServers != null || mcpClients != null)
      ? LlmMcpConfig(
          servers: mcpServers ?? [],
          clients: mcpClients ?? [],
        )
      : null;

  return FlowBrainConfig(
    configVersion: 1,
    profile: 'full',
    providers: ProvidersConfig(
      llm: LlmProviderConfig(
        type: llmType,
        apiKey: llmApiKey,
        mcp: mcp,
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
