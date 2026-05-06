/// FlowBrain Core — MOD-CORE-005 FactFacade
///
/// Orchestrates the L0 Evidence → L1 Candidate/Fact/Entity → L2
/// Claim/Summary → L3 Pattern cycle by delegating to
/// `FactGraphRuntime`. Re-exports `FactFacade` from `mcp_knowledge`.
/// See:
///
///   - `os/core/flowbrain/docs/03_DDD/05-fact-facade.md`
///   - FR-FBCORE-FCT-001..013
library;

export 'package:mcp_knowledge/mcp_knowledge.dart' show FactFacade;
