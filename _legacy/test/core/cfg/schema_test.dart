import 'package:test/test.dart';
import 'package:flowbrain_core/src/core/cfg/schema/flowbrain_config.dart';

void main() {
  group('SecretRef.parse', () {
    test('parses env reference', () {
      final ref = SecretRef.parse(r'$env:API_KEY');
      expect(ref, isA<EnvSecret>());
      expect((ref as EnvSecret).name, equals('API_KEY'));
    });

    test('parses file reference', () {
      final ref = SecretRef.parse(r'$file:/etc/secret.txt');
      expect(ref, isA<FileSecret>());
      expect((ref as FileSecret).path, equals('/etc/secret.txt'));
    });

    test('parses vault reference', () {
      final ref = SecretRef.parse(r'$vault:my/secret/key');
      expect(ref, isA<VaultSecret>());
      expect((ref as VaultSecret).key, equals('my/secret/key'));
    });

    test('inline secret for bare string', () {
      final ref = SecretRef.parse('sk-123456');
      expect(ref, isA<InlineSecret>());
      expect((ref as InlineSecret).value, equals('sk-123456'));
    });
  });

  group('SecretRef toJson/fromJson', () {
    test('EnvSecret round-trip', () {
      const ref = EnvSecret('MY_VAR');
      final json = ref.toJson();
      expect(json, equals(r'$env:MY_VAR'));
      expect(SecretRef.parse(json), isA<EnvSecret>());
    });

    test('FileSecret round-trip', () {
      const ref = FileSecret('/path/to/file');
      final json = ref.toJson();
      expect(json, equals(r'$file:/path/to/file'));
    });

    test('VaultSecret round-trip', () {
      const ref = VaultSecret('secret/key');
      final json = ref.toJson();
      expect(json, equals(r'$vault:secret/key'));
    });
  });

  group('McpServerRef', () {
    test('fromJson and toJson round-trip', () {
      final json = {
        'id': 'local-mcp',
        'transport': 'http',
        'port': 8080,
        'host': 'localhost',
      };
      final ref = McpServerRef.fromJson(json);
      expect(ref.id, equals('local-mcp'));
      expect(ref.transport, equals(McpTransport.http));
      expect(ref.port, equals(8080));
      expect(ref.host, equals('localhost'));

      final out = ref.toJson();
      expect(out['id'], equals('local-mcp'));
      expect(out['transport'], equals('http'));
    });

    test('stdio transport', () {
      final json = {'id': 'stdio-srv', 'transport': 'stdio'};
      final ref = McpServerRef.fromJson(json);
      expect(ref.transport, equals(McpTransport.stdio));
    });
  });

  group('McpClientRef', () {
    test('fromJson with bearer auth', () {
      final json = {
        'id': 'remote',
        'transport': 'http',
        'url': 'https://mcp.example.com',
        'auth': {
          'type': 'bearer',
          'token': r'$env:MCP_TOKEN',
        },
      };
      final ref = McpClientRef.fromJson(json);
      expect(ref.id, equals('remote'));
      expect(ref.auth, isA<BearerAuth>());
      final bearer = ref.auth as BearerAuth;
      expect(bearer.token, isA<EnvSecret>());
    });

    test('fromJson with no auth', () {
      final json = {
        'id': 'local',
        'transport': 'stdio',
        'command': ['npx', 'mcp-server'],
      };
      final ref = McpClientRef.fromJson(json);
      expect(ref.auth, isNull);
      expect(ref.command, equals(['npx', 'mcp-server']));
    });
  });

  group('Auth', () {
    test('NoAuth round-trip', () {
      const auth = NoAuth();
      final json = auth.toJson();
      expect(json['type'], equals('none'));
      expect(Auth.fromJson(json), isA<NoAuth>());
    });

    test('OAuth2Auth round-trip', () {
      final auth = OAuth2Auth(
        clientId: 'my-client',
        clientSecret: const EnvSecret('CLIENT_SECRET'),
        scopes: ['read', 'write'],
      );
      final json = auth.toJson();
      expect(json['type'], equals('oauth2'));
      final restored = Auth.fromJson(json);
      expect(restored, isA<OAuth2Auth>());
    });
  });

  group('AgentDef', () {
    test('fromJson and toJson round-trip', () {
      final json = {
        'name': 'TestAgent',
        'skills': ['skill1', 'skill2'],
        'profileId': 'default',
        'options': {'temperature': 0.7},
      };
      final agent = AgentDef.fromJson(json);
      expect(agent.name, equals('TestAgent'));
      expect(agent.skills, equals(['skill1', 'skill2']));
      expect(agent.profileId, equals('default'));

      final out = agent.toJson();
      expect(out['name'], equals('TestAgent'));
    });

    test('defaults for optional fields', () {
      final json = {'name': 'MinimalAgent'};
      final agent = AgentDef.fromJson(json);
      expect(agent.skills, isEmpty);
      expect(agent.profileId, isNull);
      expect(agent.options, isEmpty);
    });
  });

  group('FlowBrainConfig', () {
    test('fromJson with minimal config', () {
      final json = _minimalConfig();
      final config = FlowBrainConfig.fromJson(json);
      expect(config.configVersion, equals(1));
      expect(config.profile, equals('full'));
      expect(config.providers.llm.type, equals('claude'));
    });

    test('toJson round-trip preserves structure', () {
      final json = _minimalConfig();
      final config = FlowBrainConfig.fromJson(json);
      final out = config.toJson();
      expect(out['configVersion'], equals(1));
      expect(out['profile'], equals('full'));
    });

    test('defaults are applied', () {
      final json = _minimalConfig();
      final config = FlowBrainConfig.fromJson(json);
      expect(config.observability.logLevel, equals(LogLevel.info));
      expect(config.observability.logFormat, equals(LogFormat.text));
    });

    test('extensions preserved', () {
      final json = _minimalConfig();
      json['extensions'] = {'custom_key': 'custom_value'};
      final config = FlowBrainConfig.fromJson(json);
      expect(config.extensions['custom_key'], equals('custom_value'));
    });
  });

  group('Enums', () {
    test('LogLevel values', () {
      expect(LogLevel.values.length, greaterThanOrEqualTo(4));
      expect(LogLevel.info, isNotNull);
    });

    test('LogFormat values', () {
      expect(LogFormat.text, isNotNull);
      expect(LogFormat.json, isNotNull);
    });

    test('AuditLevel values', () {
      expect(AuditLevel.none, isNotNull);
      expect(AuditLevel.basic, isNotNull);
      expect(AuditLevel.full, isNotNull);
    });

    test('AutoUpdatePolicy values', () {
      expect(AutoUpdatePolicy.manual, isNotNull);
      expect(AutoUpdatePolicy.notify, isNotNull);
      expect(AutoUpdatePolicy.auto, isNotNull);
    });
  });
}

Map<String, dynamic> _minimalConfig() => {
      'configVersion': 1,
      'profile': 'full',
      'providers': {
        'llm': {
          'type': 'claude',
          'apiKey': r'$env:ANTHROPIC_API_KEY',
        },
        'storage': {
          'type': 'memory',
        },
      },
    };
