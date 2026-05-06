/// FlowBrain — Knowledge-based OS for the MakeMind ecosystem.
///
/// Assembles `mcp_knowledge` core with external interface packages into
/// a single configurable runtime. Supports Server and Standard deployment.
///
/// ## Quick start
///
/// ```dart
/// import 'package:flowbrain_core/flowbrain_core.dart';
///
/// Future<void> main() async {
///   final config = await FlowBrainConfig.load('./flowbrain.yaml');
///   final fb = await FlowBrain.boot(config: config);
///   await fb.serve();
/// }
/// ```
library flowbrain;

// === CORE-ASM ===
export 'src/core/asm/flowbrain.dart' show FlowBrain;
export 'src/core/asm/runtime_profile.dart' show RuntimeProfile;
export 'src/core/asm/ask_result.dart' show AskResult;
export 'src/core/asm/errors.dart'
    show
        FlowBrainError,
        ValidationError,
        AssemblyError,
        RuntimeWiringError,
        PortMissingError,
        AgentNotFoundError,
        RouteResolutionError;

// === CORE-BOOT (error hierarchy including bundle/config/routing errors) ===
export 'src/core/boot/errors.dart'
    show
        ConfigError,
        SchemaError,
        ConfigValidationError,
        SecretError,
        MigrationError,
        BundleError,
        IntegrityError,
        SchemaVersionError,
        RollbackError,
        RoutingError,
        McpBindingError,
        exitCodeFor,
        FriendlyErrorFormatter;

// === CORE-CFG (stub — will be replaced by CORE-CFG agent) ===
export 'src/core/cfg/schema/flowbrain_config.dart' show FlowBrainConfig;

// === Events ===
export 'src/events/flowbrain_events.dart'
    show
        AgentResolvedEvent,
        AgentAskStartedEvent,
        AgentAskCompletedEvent,
        KflEscalationEvent,
        ConfigReloadedEvent,
        BundleRolledBackEvent,
        CostThresholdExceededEvent,
        ConfigReloadFailedEvent;

// === Re-exports from mcp_knowledge for convenience ===
export 'package:mcp_knowledge/mcp_knowledge.dart'
    show
        KnowledgeSystem,
        KnowledgeConfig,
        KnowledgeEvent,
        KnowledgeEventBus,
        FactFacade,
        SkillFacade,
        ProfileFacade,
        PhilosophyFacade,
        OpsFacade;

// === Re-exports from mcp_bundle for convenience ===
export 'package:mcp_bundle/mcp_bundle.dart' show SkillResult;
