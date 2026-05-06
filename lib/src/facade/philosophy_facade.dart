/// FlowBrain Core — MOD-CORE-008 PhilosophyFacade
///
/// Value-alignment layer entry point. Delegates to `PhilosophyEngine`
/// and exposes 7 methods (`evaluate`, `checkProhibitions`,
/// `intervene`, `getEthos`, `detectTensions`, `proposeFeedback`,
/// `evaluateAndAdjust`). Entity variants
/// (`checkProhibitionsForEntity`, `detectTensionsForEntity`) are
/// engine-level only — access them via `system.philosophyEngine`.
/// See:
///
///   - `os/core/flowbrain/docs/03_DDD/08-philosophy-facade.md`
///   - FR-FBCORE-PHL-001..007
library;

export 'package:mcp_knowledge/mcp_knowledge.dart' show PhilosophyFacade;
