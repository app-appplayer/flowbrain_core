/// FlowBrain Core — MOD-CORE-006 SkillFacade
///
/// 7-step skill execution pipeline entry point. Delegates to
/// `SkillRuntime`. Re-exports `SkillFacade` from `mcp_knowledge`. See:
///
///   - `os/core/flowbrain/docs/03_DDD/06-skill-facade.md`
///   - FR-FBCORE-SKL-001..008
library;

export 'package:mcp_knowledge/mcp_knowledge.dart' show SkillFacade;
