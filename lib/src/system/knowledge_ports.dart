/// FlowBrain Core — MOD-CORE-002 InfraPorts (flowbrain wrapper).
///
/// Wraps `mcp_knowledge`'s `KnowledgePorts` and adds Agent Subsystem
/// extensions (`llmProviders` multi-provider pool). The `KnowledgePorts`
/// container itself remains untouched in `mcp_knowledge`. See:
///
///   - `os/core/flowbrain/docs/03_DDD/02-infra-ports.md`
///   - FR-FBCORE-INF-001..010
library;

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_knowledge/mcp_knowledge.dart' as kn;

// Re-export every standard port + DTO surfaced by `mcp_knowledge` so hosts
// that import `package:flowbrain_core/flowbrain_core.dart` do not need to touch
// `mcp_bundle` or `mcp_knowledge` directly.
export 'package:mcp_bundle/mcp_bundle.dart'
    show
        // Data / knowledge
        FactsPort,
        StubFactsPort,
        FactRecord,
        FactQuery,
        ClaimsPort,
        StubClaimsPort,
        Claim,
        ClaimQuery,
        ClaimType,
        ClaimStatus,
        EntitiesPort,
        StubEntitiesPort,
        EntityRecord,
        EntityQuery,
        CandidatesPort,
        StubCandidatesPort,
        CandidateRecord,
        CandidateStatus,
        EvidencePort,
        StubEvidencePort,
        EvidenceFragment,
        PatternsPort,
        StubPatternsPort,
        PatternRecord,
        PatternQuery,
        SummariesPort,
        StubSummariesPort,
        SummaryRecord,
        RunsPort,
        StubRunsPort,
        // Context / retrieval
        ContextBundlePort,
        StubContextBundlePort,
        RetrievalPort,
        StubRetrievalPort,
        AssetPort,
        StubAssetPort,
        IndexPort,
        // Execution
        SkillRuntimePort,
        StubSkillRuntimePort,
        SkillRegistryPort,
        McpPort,
        StubMcpPort,
        LlmPort,
        StubLlmPort,
        EmptyLlmPort,
        LlmRequest,
        LlmResponse,
        LlmMessage,
        LlmCapabilities,
        LlmUsage,
        LlmChunk,
        LlmTool,
        LlmToolCall,
        // Evaluation
        MetricsPort,
        StubMetricsPort,
        AppraisalPort,
        StubAppraisalPort,
        DecisionPort,
        StubDecisionPort,
        ExpressionPort,
        StubExpressionPort,
        ProfileSummariesPort,
        // Philosophy
        PhilosophyPort,
        StubPhilosophyPort,
        EthosStorePort,
        StubEthosStorePort,
        // Ops
        WorkflowPort,
        StubWorkflowPort,
        PipelinePort,
        StubPipelinePort,
        ScheduleTriggerPort,
        StubScheduleTriggerPort,
        AuditPort,
        StubAuditPort,
        RunbookPort,
        StubRunbookPort,
        // Cross-cutting
        KvStoragePort,
        InMemoryKvStoragePort,
        ApprovalPort,
        StubApprovalPort,
        NotificationPort,
        StubNotificationPort,
        EventPort,
        InMemoryEventPort,
        MetricPort,
        StubMetricPort,
        // Common DTOs / types
        Period,
        RelativePeriod,
        AbsolutePeriod,
        PeriodUnit,
        PeriodDirection,
        DateRange,
        DecisionAction;

// `KnowledgePorts` itself is also surfaced — advanced hosts that already
// hold a `KnowledgePorts` instance can wrap it via `InfraPorts(knowledgePorts:
// ...)`.
export 'package:mcp_knowledge/mcp_knowledge.dart' show KnowledgePorts;

/// FlowBrain InfraPorts — `KnowledgePorts` wrapper that also exposes the
/// `llmProviders` multi-provider pool used by the Agent Subsystem.
class InfraPorts {
  InfraPorts({
    kn.KnowledgePorts? knowledgePorts,
    this.llmProviders,
  }) : _ports = knowledgePorts ?? const kn.KnowledgePorts();

  /// In-memory smoke wiring — `kvStorage` + `event` are populated. Other
  /// fields remain null so hosts can layer on real adapters via
  /// [copyWith].
  factory InfraPorts.inMemory({Map<String, LlmPort>? llmProviders}) {
    return InfraPorts(
      knowledgePorts: kn.KnowledgePorts(
        kvStorage: InMemoryKvStoragePort(),
        event: InMemoryEventPort(),
      ),
      llmProviders: llmProviders,
    );
  }

  final kn.KnowledgePorts _ports;

  /// Per-provider LLM pool (`Map<provider, LlmPort>`). Used by
  /// `AgentRuntime` — see FR-FBCORE-INF-008..010.
  final Map<String, LlmPort>? llmProviders;

  /// Internal accessor used by the `KnowledgeSystem` wrapper to forward
  /// the underlying `KnowledgePorts` to the wrapped `mcp.KnowledgeSystem`.
  kn.KnowledgePorts get internal => _ports;

  // ── Convenience getters for the seven infra capability ports ────────────
  LlmPort? get llm => _ports.llm;
  KvStoragePort? get kvStorage => _ports.kvStorage;
  McpPort? get mcp => _ports.mcp;
  RetrievalPort? get retrieval => _ports.retrieval;
  NotificationPort? get notification => _ports.notification;
  EventPort? get event => _ports.event;
  MetricPort? get metric => _ports.metric;

  /// Workspace-level ethos store, surfaced from the wrapped
  /// `KnowledgePorts.ethosStore` (mcp_knowledge ≥ 0.2.1). Multi-ethos
  /// agent forks (`ForkEngine` philosophy axis) and the philosophy
  /// pool enumeration (`AgentFacade._poolStarters.philosophy`) read
  /// from here when wired. Hosts wire it once via
  /// `KnowledgePorts(ethosStore: ...)` or `copyWith(ethosStore: ...)`
  /// — flowbrain itself takes no extra ctor argument.
  EthosStorePort? get ethosStore => _ports.ethosStore;

  /// Replace one or more infra-capability ports. Knowledge logic ports
  /// (the other 25 fields on `KnowledgePorts`) cannot be substituted from
  /// outside — pass an entirely new `knowledgePorts` to do so.
  InfraPorts copyWith({
    kn.KnowledgePorts? knowledgePorts,
    LlmPort? llm,
    Map<String, LlmPort>? llmProviders,
    KvStoragePort? kvStorage,
    McpPort? mcp,
    RetrievalPort? retrieval,
    NotificationPort? notification,
    EventPort? event,
    MetricPort? metric,
    EthosStorePort? ethosStore,
  }) {
    final base = knowledgePorts ?? _ports;
    final updated = (llm != null ||
            kvStorage != null ||
            mcp != null ||
            retrieval != null ||
            notification != null ||
            event != null ||
            metric != null ||
            ethosStore != null)
        ? base.copyWith(
            llm: llm,
            kvStorage: kvStorage,
            mcp: mcp,
            retrieval: retrieval,
            notification: notification,
            event: event,
            metric: metric,
            ethosStore: ethosStore,
          )
        : base;
    return InfraPorts(
      knowledgePorts: updated,
      llmProviders: llmProviders ?? this.llmProviders,
    );
  }
}
