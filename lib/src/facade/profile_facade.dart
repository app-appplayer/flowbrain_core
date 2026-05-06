/// FlowBrain Core — MOD-CORE-007 ProfileFacade
///
/// 3-Pillar (Appraisal → Decision → Expression) entry point.
/// Delegates to `ProfileRuntime`. Re-exports `ProfileFacade` from
/// `mcp_knowledge`. See:
///
///   - `os/core/flowbrain/docs/03_DDD/07-profile-facade.md`
///   - FR-FBCORE-PRF-001..005
library;

export 'package:mcp_knowledge/mcp_knowledge.dart' show ProfileFacade;
