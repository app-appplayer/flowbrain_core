/// FlowBrain Core — MOD-CORE-001 KnowledgeSystem (flowbrain wrapper).
///
/// Wraps `mcp_knowledge`'s `KnowledgeSystem`, exposes the five Knowledge
/// Subsystem facades verbatim through getter delegation, and adds the Agent
/// Subsystem (`agents`). See:
///
///   - `os/core/flowbrain/docs/03_DDD/01-knowledge-system.md`
///   - FR-FBCORE-SYS-001..007, FR-FBCORE-PROD-007
library;

import 'package:mcp_bundle/mcp_bundle.dart' as mb;
import 'package:mcp_knowledge/mcp_knowledge.dart' as kn;

import '../agent/agent_facade.dart';
import '../agent/agent_models.dart';
import '../agent/agent_registry.dart';
import '../agent/agent_runtime.dart';
import '../agent/agent_subsystem.dart';
import 'knowledge_config.dart';
import 'knowledge_ports.dart';

// Re-export Knowledge Subsystem types so consumers can use them via
// `package:flowbrain_core/flowbrain_core.dart` alone.
export 'package:mcp_knowledge/mcp_knowledge.dart'
    show
        FactFacade,
        SkillFacade,
        ProfileFacade,
        PhilosophyFacade,
        OpsFacade,
        FactGraphRuntime,
        SkillRuntime,
        SkillPorts,
        SkillBundleRegistry,
        MemorySkillRegistry,
        SkillBundle,
        SkillManifest,
        Procedure,
        ProfileRuntime,
        ProfileRegistry,
        Profile,
        EnginePorts,
        AppraisalEnginePort,
        DecisionEnginePort,
        ExpressionEnginePort,
        PhilosophyEngine,
        PhilosophyEvaluator,
        InterventionEngine,
        TensionDetector,
        ReinforcementEngine,
        StateAdjuster,
        ConflictResolver,
        OpsRuntime,
        ConsumedOpsPorts,
        OpsPorts,
        KnowledgeEventBus,
        KnowledgeEvent;

/// FlowBrain `KnowledgeSystem` — single entry point for the entire core.
/// Delegates the five Knowledge Subsystem facades to a wrapped
/// `mcp.KnowledgeSystem` and adds the `agents` (Agent Subsystem) facade.
class KnowledgeSystem {
  KnowledgeSystem({
    required KnowledgeConfig config,
    InfraPorts? infraPorts,
    kn.FactGraphRuntime? factGraph,
    kn.SkillRuntime? skillRuntime,
    kn.ProfileRuntime? profileRuntime,
    kn.PhilosophyEngine? philosophyEngine,
    kn.OpsRuntime? opsRuntime,
    AgentRegistry? agentRegistry,
    AgentRuntime? agentRuntime,
    kn.KnowledgeEventBus? eventBus,
  })  : _config = config,
        _infraPorts = infraPorts ?? InfraPorts(),
        _agentRegistry = agentRegistry,
        _agentRuntime = agentRuntime,
        _wrapped = kn.KnowledgeSystem(
          config: config.internal,
          ports: (infraPorts ?? InfraPorts()).internal,
          factGraph: factGraph,
          skillRuntime: skillRuntime,
          profileRuntime: profileRuntime,
          philosophyEngine: philosophyEngine,
          opsRuntime: opsRuntime,
          eventBus: eventBus,
        ) {
    agents = (agentRegistry != null && agentRuntime != null)
        ? AgentFacade(runtime: agentRuntime)
        : AgentFacade.stub();
  }

  // ── Defaults / stub / withAgents factories ──────────────────────────────

  /// `KnowledgeConfig.defaults` + L0 auto-wire + in-memory infra. Agent
  /// Subsystem is **not** activated.
  factory KnowledgeSystem.defaults({
    InfraPorts? infraPorts,
    kn.FactGraphRuntime? factGraph,
    kn.SkillRuntime? skillRuntime,
    kn.ProfileRuntime? profileRuntime,
    kn.PhilosophyEngine? philosophyEngine,
    kn.OpsRuntime? opsRuntime,
  }) {
    return KnowledgeSystem(
      config: KnowledgeConfig.defaults,
      infraPorts: infraPorts ?? InfraPorts.inMemory(),
      factGraph: factGraph,
      skillRuntime: skillRuntime,
      profileRuntime: profileRuntime,
      philosophyEngine: philosophyEngine,
      opsRuntime: opsRuntime,
    );
  }

  /// Zero-config smoke — every infra port stubbed, L1~L3 + Ops + Agent
  /// subsystem all null.
  factory KnowledgeSystem.stub() => KnowledgeSystem(
        config: KnowledgeConfig.defaults,
        infraPorts: InfraPorts.inMemory(),
      );

  /// Smoke wiring with the Agent Subsystem activated. `LlmPort` defaults to
  /// `StubLlmPort()` when neither `llm` nor `llmProviders` is supplied so
  /// host code can immediately call `system.agents.ask(...)`.
  factory KnowledgeSystem.withAgents({
    KnowledgeConfig? config,
    InfraPorts? infraPorts,
    LlmPort? llm,
    Map<String, LlmPort>? llmProviders,
    kn.FactGraphRuntime? factGraph,
    kn.SkillRuntime? skillRuntime,
    kn.ProfileRuntime? profileRuntime,
    kn.PhilosophyEngine? philosophyEngine,
    kn.OpsRuntime? opsRuntime,
  }) {
    final cfg = config ?? KnowledgeConfig.defaults;
    final base = infraPorts ?? InfraPorts.inMemory();
    final infra = base.copyWith(
      llm: llm ?? base.llm ?? StubLlmPort(),
      llmProviders: llmProviders ?? base.llmProviders,
    );
    final bus = kn.KnowledgeEventBus();

    late final KnowledgeSystem system;
    final subsystem = AgentSubsystem.create(
      knowledgeSystemRef: () => system,
      infraPorts: infra,
      eventBus: bus,
      config: cfg.agent,
    );
    system = KnowledgeSystem(
      config: cfg,
      infraPorts: infra,
      factGraph: factGraph,
      skillRuntime: skillRuntime,
      profileRuntime: profileRuntime,
      philosophyEngine: philosophyEngine,
      opsRuntime: opsRuntime,
      agentRegistry: subsystem.registry,
      agentRuntime: subsystem.runtime,
      eventBus: bus,
    );
    return system;
  }

  // ── State ────────────────────────────────────────────────────────────────

  final kn.KnowledgeSystem _wrapped;
  final KnowledgeConfig _config;
  final InfraPorts _infraPorts;
  final AgentRegistry? _agentRegistry;
  final AgentRuntime? _agentRuntime;

  /// Agent Subsystem facade — stub when `agentRegistry`/`agentRuntime` are
  /// null (FR-FBCORE-RES-001(d)).
  late final AgentFacade agents;

  // ── Knowledge Subsystem getter delegations ──────────────────────────────

  kn.FactFacade get facts => _wrapped.facts;
  kn.SkillFacade get skill => _wrapped.skill;
  kn.ProfileFacade get profile => _wrapped.profile;
  kn.PhilosophyFacade get philosophy => _wrapped.philosophy;
  kn.OpsFacade get ops => _wrapped.ops;

  KnowledgeConfig get config => _config;
  InfraPorts get infraPorts => _infraPorts;
  kn.KnowledgeEventBus get eventBus => _wrapped.eventBus;

  kn.FactGraphRuntime get factGraph => _wrapped.factGraph;
  kn.SkillRuntime? get skillRuntime => _wrapped.skillRuntime;
  kn.ProfileRuntime? get profileRuntime => _wrapped.profileRuntime;
  kn.PhilosophyEngine? get philosophyEngine => _wrapped.philosophyEngine;
  kn.OpsRuntime? get opsRuntime => _wrapped.opsRuntime;

  /// Workspace-level ethos store, surfaced from the wrapped
  /// `KnowledgePorts.ethosStore` (mcp_knowledge ≥ 0.2.1). Multi-ethos
  /// agent forks read from here when wired. Hosts wire it via
  /// `KnowledgePorts(ethosStore: ...)` (or `InfraPorts.copyWith`) —
  /// flowbrain takes no extra ctor argument.
  EthosStorePort? get ethosStore => _infraPorts.ethosStore;

  AgentRegistry? get agentRegistry => _agentRegistry;
  AgentRuntime? get agentRuntime => _agentRuntime;

  bool get isAgentSubsystemActivated =>
      _agentRegistry != null && _agentRuntime != null;

  // ── Bundle import ───────────────────────────────────────────────────────

  /// Import the two FlowBrain-owned operational sections from a loaded
  /// `mcp_bundle`. Other knowledge sections (skill / profile / fact /
  /// knowledge) are imported by `OpsFacade.loadBundle` on `ops`; callers
  /// typically invoke that first, then this method, when wiring a bundle
  /// into a live system.
  ///
  /// - `bundle.philosophy` → each `Philosophy` becomes an `EthosRecord`
  ///   on `ethosStore` (when wired). Activation policy is left to the
  ///   host — entries land inactive.
  /// - `bundle.agents` → each `AgentDefinition` is registered on the
  ///   Agent Subsystem registry under [workspaceId]. The four-axis
  ///   bindings (`profileIds` / `skillIds` / `factSourceIds` /
  ///   `philosophyIds`) are preserved on `Agent.tags` as comma-separated
  ///   id lists under `bind.<axis>Ids` keys, so downstream tools can
  ///   resolve them at instantiation time.
  ///
  /// No-op for missing sections / missing infra (silent skip). Returns a
  /// summary with counts for diagnostics. Duplicate agent ids inside a
  /// workspace are skipped (no throw) so re-import is idempotent.
  Future<BundleImportSummary> importBundle(
    mb.McpBundle bundle, {
    String workspaceId = 'default',
  }) async {
    var philosophiesAdded = 0;
    var agentsAdded = 0;
    var agentsSkipped = 0;

    final philosophy = bundle.philosophy;
    final store = _infraPorts.ethosStore;
    if (philosophy != null && store != null) {
      for (final p in philosophy.philosophies) {
        await store.putEthos(mb.EthosRecord(
          id: p.id,
          name: p.name,
          version: '1.0.0',
          payload: p.toJson(),
          createdAt: DateTime.now().toUtc(),
          active: false,
        ));
        philosophiesAdded++;
      }
    }

    final agentsSection = bundle.agents;
    final registry = _agentRegistry;
    if (agentsSection != null && registry != null) {
      for (final def in agentsSection.agents) {
        final role = _parseAgentRole(def.role);
        final cfg = def.model;
        final model = cfg != null
            ? ModelSpec(
                provider: cfg.provider ?? 'unknown',
                model: cfg.model ?? 'unknown',
                maxTokens: cfg.maxTokens,
                temperature: cfg.temperature,
              )
            : ModelSpec.stub();
        final tags = <String, String>{
          if (def.profileIds.isNotEmpty)
            'bind.profileIds': def.profileIds.join(','),
          if (def.skillIds.isNotEmpty)
            'bind.skillIds': def.skillIds.join(','),
          if (def.factSourceIds.isNotEmpty)
            'bind.factSourceIds': def.factSourceIds.join(','),
          if (def.philosophyIds.isNotEmpty)
            'bind.philosophyIds': def.philosophyIds.join(','),
        };
        try {
          await registry.create(
            id: def.id,
            displayName: def.name,
            role: role,
            model: model,
            workspaceId: workspaceId,
            systemPrompt: def.systemPrompt,
            tags: tags,
          );
          agentsAdded++;
        } on StateError {
          // Duplicate id under the same workspace — re-import idempotent.
          agentsSkipped++;
        }
      }
    }

    return BundleImportSummary(
      philosophiesAdded: philosophiesAdded,
      agentsAdded: agentsAdded,
      agentsSkipped: agentsSkipped,
    );
  }

  static AgentRole _parseAgentRole(String role) {
    switch (role.toLowerCase()) {
      case 'manager':
        return AgentRole.manager;
      case 'reviewer':
        return AgentRole.reviewer;
      case 'worker':
      default:
        return AgentRole.worker;
    }
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  Future<void> shutdown() async {
    await agents.shutdownInternal();
    await _wrapped.shutdown();
  }
}

/// Counts returned by [KnowledgeSystem.importBundle] for diagnostics.
class BundleImportSummary {
  const BundleImportSummary({
    required this.philosophiesAdded,
    required this.agentsAdded,
    required this.agentsSkipped,
  });

  final int philosophiesAdded;
  final int agentsAdded;

  /// Agents skipped because their id already existed under the workspace.
  final int agentsSkipped;

  @override
  String toString() =>
      'BundleImportSummary(philosophies: $philosophiesAdded, '
      'agents: $agentsAdded, skipped: $agentsSkipped)';
}
