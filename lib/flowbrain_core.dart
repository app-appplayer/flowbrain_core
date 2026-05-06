/// FlowBrain Core — base knowledge + agent system for the judgment &
/// knowledge domain in the MakeMind ecosystem.
///
/// Two subsystems:
///
///   - **Knowledge Subsystem** — four-layer knowledge structure (L0
///     FactGraph → L1 Skill → L2 Profile → L3 Philosophy) plus Ops, with
///     5 facades wrapped from `mcp_knowledge`.
///   - **Agent Subsystem** — flowbrain-native. Self-contained agents with
///     own LLM context, own model, own forked 4-axis instances, and
///     worker / manager / reviewer roles.
///
/// Hosts (e.g. Ops, standard MCP servers, derivative OS cores) import
/// **only** this library — `mcp_knowledge` and the five domain packages
/// stay as internal technical stack:
///
/// ```dart
/// import 'package:flowbrain_core/flowbrain_core.dart';
///
/// final system = KnowledgeSystem.withAgents();
/// await system.agents.createAgent(
///   id: 'sara',
///   displayName: 'Sara',
///   role: AgentRole.worker,
///   model: ModelSpec(provider: 'stub', model: 'stub-1'),
///   workspaceId: 'default',
/// );
/// final reply = await system.agents.ask('sara', 'hello');
/// await system.shutdown();
/// ```
///
library;

// ============================================================================
// FlowBrain wrapper classes (own surface).
// ============================================================================
export 'src/system/knowledge_system.dart';
export 'src/system/knowledge_config.dart';
export 'src/system/knowledge_ports.dart';

// ============================================================================
// Agent Subsystem (100% flowbrain-native).
// ============================================================================
export 'src/agent/agent_facade.dart';
export 'src/agent/agent_registry.dart';
export 'src/agent/agent_runtime.dart';
export 'src/agent/conversation_store.dart';
export 'src/agent/fork_engine.dart';
export 'src/agent/growth_tracker.dart';
export 'src/agent/manager_router.dart';
export 'src/agent/reviewer_engine.dart';
export 'src/agent/agent_subsystem.dart';
export 'src/agent/agent_models.dart';
export 'src/agent/agent_event.dart';
export 'src/agent/agent_exception.dart';
export 'src/agent/agent_config.dart';
export 'src/agent/agent_lifecycle_fact.dart';

// ============================================================================
// Re-exports surfaced earlier in this library:
//
//   - 5 Knowledge facades + Runtime types + KnowledgeEventBus / EventBus
//     KnowledgeEvent → from `src/system/knowledge_system.dart`.
//   - All standard ports + DTOs + InfraPorts → from
//     `src/system/knowledge_ports.dart`.
//   - 9 Knowledge sub-config types + LogLevel → from
//     `src/system/knowledge_config.dart`.
// ============================================================================

// ============================================================================
// Philosophy domain helper types — surfaced for host-side error handling
// and guidance inspection.
// ============================================================================
export 'package:mcp_knowledge/mcp_knowledge.dart'
    show
        PhilosophyException,
        EthosValidationException,
        ProhibitionViolationException,
        EvaluationException,
        InterventionException,
        TensionResolutionException,
        EvolutionException,
        ProhibitionCheckResults,
        EvaluationContext,
        ConflictStrategy,
        ConflictResolution,
        PatternDirection,
        ReinforcementPattern,
        EvolutionRecord;

// ============================================================================
// Profile / Philosophy wire types — re-exported so hosts can construct
// ProfileRuntime / PhilosophyEngine without taking direct dependencies on
// mcp_profile / mcp_philosophy. Hosts that wire the L2/L3 facades feed the
// resulting runtime/engine into `KnowledgeSystem`'s ctor.
// ============================================================================
export 'package:mcp_knowledge/mcp_knowledge.dart'
    show
        // Profile pillar (L2)
        Profile,
        ProfileBuilder,
        ProfileRegistry,
        ProfileRuntime,
        EnginePorts,
        DefaultRuntimeContext,
        RuntimeProfileContext,
        RuntimeContextBuilder,
        ProfileApplicationResult,
        ProfileApplicationMetadata,
        ProfileNotFoundException,
        // Philosophy pillar (L3)
        PhilosophyEngine,
        KvEthosStoreAdapter,
        DefaultEthosSeeder,
        Ethos,
        EthosScope,
        EthosRecord,
        EthosStorePort,
        StubEthosStorePort,
        ValuePriority,
        Prohibition,
        JudgmentCriterion,
        DirectionalAttitude,
        EthosMetadata;
