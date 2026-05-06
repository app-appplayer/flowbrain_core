/// FlowBrain Core — Agent Subsystem models, enums, and value classes.
///
/// All Agent-related types defined here are flowbrain's own — independent of
/// `mcp_knowledge`. See:
///
///   - `os/core/flowbrain/docs/03_DDD/11-agent-facade.md`
///   - `os/core/flowbrain/docs/03_DDD/12-agent-registry.md`
///   - FR-FBCORE-AGT-001..006
library;

import 'dart:convert';

// ============================================================================
// Enums (FR-FBCORE-AGT-002, AGT-005, AGT-006, plus ForkPolicy / ReviewVerdict /
// ReviewSeverity).
// ============================================================================

/// Agent role — metadata controlling which AgentFacade methods are callable.
///
/// All three roles share the same self-contained Agent model (own LLM context,
/// own ModelSpec, own forked 4-axis instances). Only method routing differs.
enum AgentRole {
  /// Default. May be invoked via `ask`/`stream`. Cannot `route` or `review`.
  worker,

  /// May `route` requests to other agents. Cannot `review`.
  manager,

  /// May `review` other agents' replies. Cannot `route`.
  reviewer,
}

/// 4-axis identifier — Knowledge Subsystem domain assigned to an agent
/// via fork (FR-FBCORE-AGT-005).
enum AgentAxis {
  skill,
  profile,
  philosophy,
  facts,
}

/// Growth event kind — categorizes evolution recorded by Growth Tracker
/// (FR-FBCORE-AGT-006).
enum GrowthKind {
  /// Skill usage pattern variation (increments `skillCandidateCount`).
  variation,

  /// Profile fine adjustment (increments `profileAdjustmentCount`).
  adjustment,

  /// Philosophy / ethos revision (increments `philosophyRevisionCount`).
  revision,
}

/// Fork policy — controls when deep copy occurs at assignment.
enum ForkPolicy {
  /// Deep copy at assignment time. Higher upfront cost, lower latency on
  /// later mutation. Default.
  eagerFull,

  /// Defer deep copy until first mutation. Lower upfront cost, higher
  /// latency at first mutation.
  copyOnWrite,
}

/// Reviewer verdict (parsed from reviewer LLM response).
enum ReviewVerdict { pass, fail, revise }

/// Reviewer severity — optional, used when verdict is `fail` or `revise`.
enum ReviewSeverity { low, medium, high }

// ============================================================================
// ForkSource — sealed source for assign/transfer (FR-FBCORE-AGT-040+).
// ============================================================================

/// Origin of a fork operation. An agent's owned 4-axis instance can be
/// created from either the workspace pool (a Knowledge Subsystem facade
/// entry) or another agent's already-evolved owned fork. Sealed so the
/// callsite (and pattern matching) makes the choice explicit.
///
/// String encoding round-trips via [encode] / [ForkSource.decode] so
/// `OwnedFork.source` can be persisted in any `KvStoragePort` adapter
/// without loss.
sealed class ForkSource {
  const ForkSource();

  /// Stable string form. `pool:<id>` for [PoolForkSource], `agent:<agentId>/<axis>/<forkedRef>`
  /// for [AgentForkSource]. Idempotent across encode/decode.
  String encode();

  /// Decode the canonical string form back into a sealed instance. Returns
  /// `null` when the input does not match either encoding (caller decides
  /// whether to fall back or surface an error).
  static ForkSource? decode(String s) {
    if (s.startsWith('pool:')) {
      return PoolForkSource(s.substring(5));
    }
    if (s.startsWith('agent:')) {
      // agent:<agentId>/<axis>/<forkedRef>
      final body = s.substring(6);
      final firstSlash = body.indexOf('/');
      if (firstSlash <= 0) return null;
      final secondSlash = body.indexOf('/', firstSlash + 1);
      if (secondSlash <= firstSlash + 1) return null;
      final agentId = body.substring(0, firstSlash);
      final axisName = body.substring(firstSlash + 1, secondSlash);
      final forkedRef = body.substring(secondSlash + 1);
      final axis = AgentAxis.values.firstWhere(
        (a) => a.name == axisName,
        orElse: () => AgentAxis.skill,
      );
      return AgentForkSource(
        agentId: agentId,
        axis: axis,
        forkedRef: forkedRef,
      );
    }
    return null;
  }

  @override
  String toString() => encode();
}

/// Fork from a Knowledge Subsystem pool entry (the workspace seed
/// definition). [poolId] is the same id used by the underlying facade —
/// e.g. `'editor-default'` for `system.skill`/`system.profile`/`system.philosophy`,
/// or a query hash for `system.facts`.
class PoolForkSource extends ForkSource {
  const PoolForkSource(this.poolId);
  final String poolId;

  @override
  String encode() => 'pool:$poolId';

  @override
  bool operator ==(Object other) =>
      other is PoolForkSource && other.poolId == poolId;

  @override
  int get hashCode => Object.hash('pool', poolId);
}

/// Fork from another agent's already-evolved owned instance. This is the
/// "transfer" path — agent B receives the result of agent A's growth as
/// its own starting point and continues evolving from there. [axis] is
/// included in the encoding so cross-axis confusion is impossible.
class AgentForkSource extends ForkSource {
  const AgentForkSource({
    required this.agentId,
    required this.axis,
    required this.forkedRef,
  });

  final String agentId;
  final AgentAxis axis;
  final String forkedRef;

  @override
  String encode() => 'agent:$agentId/${axis.name}/$forkedRef';

  @override
  bool operator ==(Object other) =>
      other is AgentForkSource &&
      other.agentId == agentId &&
      other.axis == axis &&
      other.forkedRef == forkedRef;

  @override
  int get hashCode => Object.hash('agent', agentId, axis, forkedRef);
}

// ============================================================================
// IntegratedAxisEntry — workspace-level 4-axis integrated view.
// ============================================================================

/// One entry in a workspace's integrated axis listing. Combines pool
/// starters (Knowledge Subsystem seed definitions) and every agent's owned
/// fork into a single union view, so any agent (new or existing) can pick
/// any entry — pool starter or another agent's evolved instance — as the
/// source for a new fork. Returned by `agents.listIntegrated(workspaceId, axis)`.
class IntegratedAxisEntry {
  const IntegratedAxisEntry({
    required this.source,
    required this.displayLabel,
    this.ownerAgentId,
    this.lineage = const [],
  });

  /// Sealed source — distinguishes pool starters from agent-owned forks.
  final ForkSource source;

  /// Human-readable label used by UIs / pickers. Typically the pool id or
  /// the agent's displayName + a short version tag.
  final String displayLabel;

  /// `null` when this entry is a pool starter; the agent id when it is an
  /// owned fork.
  final String? ownerAgentId;

  /// Origin chain (oldest first). Pool starters have an empty lineage;
  /// agent-owned forks accumulate one entry per assign/transfer hop —
  /// `[pool:editor-default, agent:A/skill/A::editor-default]`.
  final List<String> lineage;

  bool get isPool => source is PoolForkSource;
  bool get isAgentOwned => source is AgentForkSource;
}

// ============================================================================
// Model classes — Agent + ModelSpec + AgentGrowth.
// ============================================================================

/// Per-agent LLM provider+model selector. One agent owns exactly one
/// ModelSpec — provider mixing within an agent is not supported in this spec
/// revision (FR-FBCORE-AGT-003).
class ModelSpec {
  const ModelSpec({
    required this.provider,
    required this.model,
    this.maxTokens,
    this.temperature,
  });

  /// Stub provider for tests / smoke runs.
  factory ModelSpec.stub({String model = 'stub-1'}) =>
      ModelSpec(provider: 'stub', model: model);

  /// Provider key — e.g. `'anthropic'`, `'openai'`, `'gemini'`, `'stub'`.
  /// Used for `infraPorts.llmProviders[provider]` lookup.
  final String provider;

  /// Model identifier — e.g. `'claude-sonnet-4-6'`, `'gpt-5'`.
  final String model;

  final int? maxTokens;
  final double? temperature;

  ModelSpec copyWith({
    String? provider,
    String? model,
    int? maxTokens,
    double? temperature,
  }) =>
      ModelSpec(
        provider: provider ?? this.provider,
        model: model ?? this.model,
        maxTokens: maxTokens ?? this.maxTokens,
        temperature: temperature ?? this.temperature,
      );

  Map<String, Object?> toJson() => {
        'provider': provider,
        'model': model,
        if (maxTokens != null) 'maxTokens': maxTokens,
        if (temperature != null) 'temperature': temperature,
      };

  factory ModelSpec.fromJson(Map<String, Object?> json) => ModelSpec(
        provider: json['provider'] as String,
        model: json['model'] as String,
        maxTokens: json['maxTokens'] as int?,
        temperature: (json['temperature'] as num?)?.toDouble(),
      );

  @override
  String toString() => '$provider/$model';

  @override
  bool operator ==(Object other) =>
      other is ModelSpec &&
      other.provider == provider &&
      other.model == model &&
      other.maxTokens == maxTokens &&
      other.temperature == temperature;

  @override
  int get hashCode => Object.hash(provider, model, maxTokens, temperature);
}

/// Agent growth counters — incremented when Growth Tracker detects evolution
/// in agent-owned 4-axis instances. Persisted as part of the Agent model
/// (FR-FBCORE-AGT-004).
class AgentGrowth {
  const AgentGrowth({
    this.skillCandidateCount = 0,
    this.profileAdjustmentCount = 0,
    this.philosophyRevisionCount = 0,
    this.factsAccumulationCount = 0,
    this.lastGrowthAt,
  });

  /// Zero-state factory — used when creating a new Agent.
  static const AgentGrowth zero = AgentGrowth();

  final int skillCandidateCount;
  final int profileAdjustmentCount;
  final int philosophyRevisionCount;
  final int factsAccumulationCount;
  final DateTime? lastGrowthAt;

  AgentGrowth copyWith({
    int? skillCandidateCount,
    int? profileAdjustmentCount,
    int? philosophyRevisionCount,
    int? factsAccumulationCount,
    DateTime? lastGrowthAt,
  }) =>
      AgentGrowth(
        skillCandidateCount: skillCandidateCount ?? this.skillCandidateCount,
        profileAdjustmentCount:
            profileAdjustmentCount ?? this.profileAdjustmentCount,
        philosophyRevisionCount:
            philosophyRevisionCount ?? this.philosophyRevisionCount,
        factsAccumulationCount:
            factsAccumulationCount ?? this.factsAccumulationCount,
        lastGrowthAt: lastGrowthAt ?? this.lastGrowthAt,
      );

  /// Increment the counter associated with [kind]. `factsAccumulationCount`
  /// is incremented separately via [bumpFacts] since the kind enum does not
  /// include a facts variant in this spec revision.
  AgentGrowth bump(GrowthKind kind, {DateTime? at}) {
    final now = at ?? DateTime.now();
    switch (kind) {
      case GrowthKind.variation:
        return copyWith(
          skillCandidateCount: skillCandidateCount + 1,
          lastGrowthAt: now,
        );
      case GrowthKind.adjustment:
        return copyWith(
          profileAdjustmentCount: profileAdjustmentCount + 1,
          lastGrowthAt: now,
        );
      case GrowthKind.revision:
        return copyWith(
          philosophyRevisionCount: philosophyRevisionCount + 1,
          lastGrowthAt: now,
        );
    }
  }

  AgentGrowth bumpFacts({DateTime? at}) => copyWith(
        factsAccumulationCount: factsAccumulationCount + 1,
        lastGrowthAt: at ?? DateTime.now(),
      );

  Map<String, Object?> toJson() => {
        'skillCandidateCount': skillCandidateCount,
        'profileAdjustmentCount': profileAdjustmentCount,
        'philosophyRevisionCount': philosophyRevisionCount,
        'factsAccumulationCount': factsAccumulationCount,
        if (lastGrowthAt != null)
          'lastGrowthAt': lastGrowthAt!.toIso8601String(),
      };

  factory AgentGrowth.fromJson(Map<String, Object?> json) => AgentGrowth(
        skillCandidateCount: json['skillCandidateCount'] as int? ?? 0,
        profileAdjustmentCount: json['profileAdjustmentCount'] as int? ?? 0,
        philosophyRevisionCount: json['philosophyRevisionCount'] as int? ?? 0,
        factsAccumulationCount: json['factsAccumulationCount'] as int? ?? 0,
        lastGrowthAt: json['lastGrowthAt'] != null
            ? DateTime.parse(json['lastGrowthAt'] as String)
            : null,
      );
}

/// Agent — self-contained unit with own LLM conversation context, own model,
/// own forked 4-axis instances, and own growth (FR-FBCORE-AGT-001).
///
/// The 4-axis instances themselves are stored separately in `AgentRegistry`'s
/// owned-axis storage (`agent_owned_<axis>/<agentId>/<forkedRef>`); this
/// model only carries identity and the growth counters.
class Agent {
  const Agent({
    required this.id,
    required this.displayName,
    required this.role,
    required this.model,
    required this.workspaceId,
    required this.createdAt,
    this.systemPrompt,
    this.growth = AgentGrowth.zero,
    this.tags = const {},
  });

  final String id;
  final String displayName;
  final AgentRole role;
  final ModelSpec model;
  final String workspaceId;
  final DateTime createdAt;
  final String? systemPrompt;
  final AgentGrowth growth;
  final Map<String, String> tags;

  Agent copyWith({
    String? displayName,
    AgentRole? role,
    ModelSpec? model,
    String? workspaceId,
    DateTime? createdAt,
    String? systemPrompt,
    AgentGrowth? growth,
    Map<String, String>? tags,
  }) =>
      Agent(
        id: id,
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        model: model ?? this.model,
        workspaceId: workspaceId ?? this.workspaceId,
        createdAt: createdAt ?? this.createdAt,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        growth: growth ?? this.growth,
        tags: tags ?? this.tags,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'displayName': displayName,
        'role': role.name,
        'model': model.toJson(),
        'workspaceId': workspaceId,
        'createdAt': createdAt.toIso8601String(),
        if (systemPrompt != null) 'systemPrompt': systemPrompt,
        'growth': growth.toJson(),
        'tags': tags,
      };

  factory Agent.fromJson(Map<String, Object?> json) => Agent(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        role: AgentRole.values.byName(json['role'] as String),
        model: ModelSpec.fromJson(
            (json['model'] as Map).cast<String, Object?>()),
        workspaceId: json['workspaceId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        systemPrompt: json['systemPrompt'] as String?,
        growth: AgentGrowth.fromJson(
            (json['growth'] as Map?)?.cast<String, Object?>() ?? const {}),
        tags: ((json['tags'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, v as String)),
      );
}

// ============================================================================
// Conversation — turn record + token usage.
// ============================================================================

/// One conversation turn (user message + assistant reply pair). Stored per
/// agent in `ConversationStore` under `conv/<agentId>/turns`.
class ConversationTurn {
  const ConversationTurn({
    required this.userMessage,
    required this.assistantReply,
    required this.model,
    required this.timestamp,
    this.tokenUsage,
    this.extra,
  });

  final String userMessage;
  final String assistantReply;
  final String model;
  final DateTime timestamp;
  final TokenUsage? tokenUsage;
  final Map<String, Object?>? extra;

  Map<String, Object?> toJson() => {
        'userMessage': userMessage,
        'assistantReply': assistantReply,
        'model': model,
        'timestamp': timestamp.toIso8601String(),
        if (tokenUsage != null) 'tokenUsage': tokenUsage!.toJson(),
        if (extra != null) 'extra': extra,
      };

  factory ConversationTurn.fromJson(Map<String, Object?> json) =>
      ConversationTurn(
        userMessage: json['userMessage'] as String,
        assistantReply: json['assistantReply'] as String,
        model: json['model'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        tokenUsage: json['tokenUsage'] != null
            ? TokenUsage.fromJson(
                (json['tokenUsage'] as Map).cast<String, Object?>())
            : null,
        extra: (json['extra'] as Map?)?.cast<String, Object?>(),
      );
}

/// Token-usage breakdown returned by the LLM port.
class TokenUsage {
  const TokenUsage({
    required this.promptTokens,
    required this.completionTokens,
    int? totalTokens,
  }) : totalTokens = totalTokens ?? promptTokens + completionTokens;

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  TokenUsage operator +(TokenUsage other) => TokenUsage(
        promptTokens: promptTokens + other.promptTokens,
        completionTokens: completionTokens + other.completionTokens,
      );

  Map<String, Object?> toJson() => {
        'promptTokens': promptTokens,
        'completionTokens': completionTokens,
        'totalTokens': totalTokens,
      };

  factory TokenUsage.fromJson(Map<String, Object?> json) => TokenUsage(
        promptTokens: json['promptTokens'] as int,
        completionTokens: json['completionTokens'] as int,
        totalTokens: json['totalTokens'] as int?,
      );
}

// ============================================================================
// Reply / Token / Routing / Review value classes.
// ============================================================================

/// Result of an agent invocation (`ask`).
class AgentReply {
  const AgentReply({
    required this.id,
    required this.agentId,
    required this.content,
    required this.model,
    required this.timestamp,
    this.tokenUsage,
    this.toolCalls,
    this.finishReason,
  });

  /// Provider-side response identifier (may be empty for stub providers).
  final String id;

  final String agentId;
  final String content;
  final String model;
  final DateTime timestamp;
  final TokenUsage? tokenUsage;

  /// Structured tool invocation requests emitted by the model when the
  /// caller passed `tools:` to `agents.ask` / `agents.stream`. The list is
  /// empty (or null) when the model produced a plain content response.
  final List<AgentToolCall>? toolCalls;

  /// Provider-supplied stop reason — typically `'stop'`, `'length'`, or
  /// `'tool_calls'`.
  final String? finishReason;
}

/// Provider-agnostic tool invocation captured from an LLM response.
class AgentToolCall {
  const AgentToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// Provider-supplied invocation id (used to correlate the eventual tool
  /// result message back to this call).
  final String id;
  final String name;
  final Map<String, Object?> arguments;
}

/// One token from `stream(...)` — emitted incrementally.
class AgentToken {
  const AgentToken({
    required this.agentId,
    required this.delta,
    this.isFinal = false,
  });

  final String agentId;
  final String delta;
  final bool isFinal;
}

/// Manager router decision (FR-FBCORE-AGT-024).
class RoutingDecision {
  const RoutingDecision({
    required this.targetAgentId,
    required this.confidence,
    this.reason,
  });

  final String targetAgentId;
  final double confidence; // 0.0 ~ 1.0
  final String? reason;

  /// Parsing fallback when the manager LLM returns malformed output.
  static const RoutingDecision parseError = RoutingDecision(
    targetAgentId: '',
    confidence: 0.0,
    reason: 'parse_error',
  );

  /// Try to parse a JSON object from raw LLM content. Returns
  /// [parseError] when parsing fails.
  factory RoutingDecision.tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return parseError;
      final target = decoded['targetAgentId'];
      final confidence = decoded['confidence'];
      if (target is! String || confidence is! num) return parseError;
      return RoutingDecision(
        targetAgentId: target,
        confidence: confidence.toDouble(),
        reason: decoded['reason'] as String?,
      );
    } catch (_) {
      return parseError;
    }
  }
}

/// Reviewer engine result (FR-FBCORE-AGT-025).
class ReviewResult {
  const ReviewResult({
    required this.verdict,
    this.severity,
    this.comments,
  });

  final ReviewVerdict verdict;
  final ReviewSeverity? severity;
  final String? comments;

  static const ReviewResult parseError = ReviewResult(
    verdict: ReviewVerdict.fail,
    severity: ReviewSeverity.medium,
    comments: 'parse_error',
  );

  factory ReviewResult.tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return parseError;
      final verdictRaw = decoded['verdict'];
      if (verdictRaw is! String) return parseError;
      final verdict = ReviewVerdict.values.byName(verdictRaw);
      final severityRaw = decoded['severity'] as String?;
      final severity = severityRaw != null
          ? ReviewSeverity.values.byName(severityRaw)
          : null;
      return ReviewResult(
        verdict: verdict,
        severity: severity,
        comments: decoded['comments'] as String?,
      );
    } catch (_) {
      return parseError;
    }
  }
}
