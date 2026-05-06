import 'secret_ref.dart';

/// MCP transport protocol.
enum McpTransport { http, stdio, sse }

/// Authentication sealed hierarchy for MCP connections.
sealed class Auth {
  const Auth();

  factory Auth.fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      'oauth2' => OAuth2Auth(
          clientId: json['clientId'] as String,
          clientSecret: json['clientSecret'] != null
              ? SecretRef.parse(json['clientSecret'] as String)
              : null,
          scopes: (json['scopes'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              [],
        ),
      'bearer' => BearerAuth(
          token: SecretRef.parse(json['token'] as String),
        ),
      'none' => const NoAuth(),
      _ => const NoAuth(),
    };
  }

  Map<String, dynamic> toJson();
}

/// OAuth2 authentication.
class OAuth2Auth extends Auth {
  final String clientId;
  final SecretRef? clientSecret;
  final List<String> scopes;

  const OAuth2Auth({
    required this.clientId,
    this.clientSecret,
    this.scopes = const [],
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'oauth2',
        'clientId': clientId,
        if (clientSecret != null) 'clientSecret': clientSecret!.toJson(),
        'scopes': scopes,
      };
}

/// Bearer token authentication.
class BearerAuth extends Auth {
  final SecretRef token;
  const BearerAuth({required this.token});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'bearer',
        'token': token.toJson(),
      };
}

/// No authentication.
class NoAuth extends Auth {
  const NoAuth();

  @override
  Map<String, dynamic> toJson() => {'type': 'none'};
}

/// Reference to an MCP server in configuration.
class McpServerRef {
  final String id;
  final McpTransport transport;
  final int? port;
  final String? host;
  final Auth? auth;

  const McpServerRef({
    required this.id,
    required this.transport,
    this.port,
    this.host,
    this.auth,
  });

  factory McpServerRef.fromJson(Map<String, dynamic> json) {
    return McpServerRef(
      id: json['id'] as String,
      transport: McpTransport.values.byName(json['transport'] as String),
      port: json['port'] as int?,
      host: json['host'] as String?,
      auth: json['auth'] != null
          ? Auth.fromJson(json['auth'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'transport': transport.name,
        if (port != null) 'port': port,
        if (host != null) 'host': host,
        if (auth != null) 'auth': auth!.toJson(),
      };
}

/// Reference to an MCP client in configuration.
class McpClientRef {
  final String id;
  final McpTransport transport;
  final String? url;
  final List<String>? command;
  final Auth? auth;

  const McpClientRef({
    required this.id,
    required this.transport,
    this.url,
    this.command,
    this.auth,
  });

  factory McpClientRef.fromJson(Map<String, dynamic> json) {
    return McpClientRef(
      id: json['id'] as String,
      transport: McpTransport.values.byName(json['transport'] as String),
      url: json['url'] as String?,
      command: (json['command'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      auth: json['auth'] != null
          ? Auth.fromJson(json['auth'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'transport': transport.name,
        if (url != null) 'url': url,
        if (command != null) 'command': command,
        if (auth != null) 'auth': auth!.toJson(),
      };
}
