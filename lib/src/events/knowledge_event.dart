/// FlowBrain Core — MOD-CORE-004 KnowledgeEventBus (events)
///
/// 13 event types, all `KnowledgeEvent` implementers with `*Event`
/// suffix, exposing `timestamp` and snake_case `type`. Re-exports all
/// event types from `mcp_knowledge`. See:
///
///   - `os/core/flowbrain/docs/03_DDD/04-event-bus.md`
///   - FR-FBCORE-EVT-003, EVT-004, EVT-008
library;

export 'package:mcp_knowledge/mcp_knowledge.dart'
    show
        KnowledgeEvent,
        FactConfirmedEvent,
        CandidateCreatedEvent,
        SummaryRefreshedEvent,
        SkillExecutedEvent,
        ClaimsRecordedEvent,
        ProfileAppliedEvent,
        PhilosophyEvaluatedEvent,
        ProhibitionViolatedEvent,
        TensionDetectedEvent,
        EvolutionProposedEvent,
        BundleLoadedEvent,
        PipelineCompletedEvent,
        SystemShutdownEvent;
