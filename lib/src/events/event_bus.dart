/// FlowBrain Core — MOD-CORE-004 KnowledgeEventBus (bus)
///
/// Broadcast `StreamController<KnowledgeEvent>` based bus. Re-exports
/// the `KnowledgeEventBus` from `mcp_knowledge`. See:
///
///   - `os/core/flowbrain/docs/03_DDD/04-event-bus.md`
///   - FR-FBCORE-EVT-001..002, EVT-005..007
library;

export 'package:mcp_knowledge/mcp_knowledge.dart' show KnowledgeEventBus;
