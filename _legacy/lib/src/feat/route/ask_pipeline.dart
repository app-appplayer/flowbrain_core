/// Ask pipeline for FEAT-ROUTE.
///
/// Orchestrates the full ask flow: route -> philosophy check ->
/// skill execute -> profile apply -> philosophy intervene -> learn ->
/// return [AskResult].
///
/// This implementation is deliberately minimal. It depends only on
/// [AgentRouter] for routing. Full KnowledgeSystem integration (philosophy,
/// skill, profile facades) is wired by the FlowBrain assembler — here we
/// provide optional hooks so the pipeline can operate in degraded mode
/// (routing-only) when facades are not yet available.
library;

import 'package:logging/logging.dart';
import 'package:mcp_bundle/mcp_bundle.dart'
    show
        SkillResult,
        CandidateRecord,
        InterventionPoint,
        PipelineContext,
        InterventionResult;

import '../../core/asm/ask_result.dart';
import 'agent_router.dart';

// Re-export AskResult so existing importers of this file still see it.
export '../../core/asm/ask_result.dart' show AskResult;

final _log = Logger('AskPipeline');

// ── Facade hooks (optional) ──────────────────────────────────────────────

/// Hook for philosophy prohibition checks.
typedef ProhibitionCheckFn = Future<ProhibitionCheckResult> Function(
  String content,
  Map<String, dynamic> context,
);

/// Hook for skill execution.
typedef SkillExecuteFn = Future<SkillResult> Function(
  String skillId,
  Map<String, dynamic> inputs, {
  String? entityId,
});

/// Hook for profile application.
typedef ProfileApplyFn = Future<String> Function(
  String profileId, {
  required String entityId,
  String? content,
});

/// Hook for philosophy pipeline intervention.
typedef InterventionFn = Future<InterventionResult> Function(
  InterventionPoint point,
  PipelineContext context,
);

/// Hook for candidate learning.
typedef LearnFn = Future<void> Function(List<CandidateRecord> candidates);

/// Simplified prohibition check result for the pipeline.
class ProhibitionCheckResult {
  /// Whether a hard (blocking) violation was found.
  final bool hasHardViolation;

  const ProhibitionCheckResult({this.hasHardViolation = false});
}

// ── Pipeline ─────────────────────────────────────────────────────────────

/// High-level ask pipeline: route -> optional philosophy/skill/profile
/// pipeline steps -> return result.
///
/// When facade hooks are null, the corresponding step is skipped (degraded
/// mode). This allows the pipeline to operate with just routing when
/// KnowledgeSystem is not fully wired.
class AskPipeline {
  /// Agent router for request -> agent resolution.
  final AgentRouter router;

  /// Optional: philosophy prohibition check.
  final ProhibitionCheckFn? checkProhibitions;

  /// Optional: skill execution.
  final SkillExecuteFn? executeSkill;

  /// Optional: profile application.
  final ProfileApplyFn? applyProfile;

  /// Optional: philosophy pipeline intervention.
  final InterventionFn? intervene;

  /// Optional: candidate learning.
  final LearnFn? learn;

  AskPipeline({
    required this.router,
    this.checkProhibitions,
    this.executeSkill,
    this.applyProfile,
    this.intervene,
    this.learn,
  });

  /// Execute the full ask pipeline.
  Future<AskResult> run(String request, {String? traceId}) async {
    final tid = traceId ?? _generateTraceId();
    _log.fine('AskPipeline.run start traceId=$tid');

    try {
      // Step 1: Route
      final agent = await router.resolve(request);
      _log.fine('Resolved agent=${agent.id} traceId=$tid');

      // Step 2: Pre-intervention (prohibition check)
      if (checkProhibitions != null) {
        final checked = await checkProhibitions!(
          request,
          {'agentId': agent.id},
        );
        if (checked.hasHardViolation) {
          throw StateError('Hard prohibition violation for request');
        }
      }

      // Step 3: Skill execution
      SkillResult? skillResult;
      String output = '';
      if (executeSkill != null && agent.skills.isNotEmpty) {
        final primarySkill = agent.skills.first;
        skillResult = await executeSkill!(
          primarySkill,
          {
            'request': request,
            'agentId': agent.id,
            'scopes': agent.factGraphScopes,
          },
          entityId: agent.id,
        );
        output = skillResult.metadata.custom?['output'] as String? ?? '';
      }

      // Step 4: Profile application
      if (applyProfile != null && output.isNotEmpty) {
        output = await applyProfile!(
          agent.profileId,
          entityId: agent.id,
          content: output,
        );
      }

      // Step 5: Post-intervention
      if (intervene != null && output.isNotEmpty) {
        final interventionResult = await intervene!(
          InterventionPoint.postGeneration,
          PipelineContext(
            pipelineId: tid,
            currentPoint: InterventionPoint.postGeneration,
            generatedOutput: output,
            skillContext: {'agentId': agent.id},
          ),
        );
        if (interventionResult.modified &&
            interventionResult.modifications != null) {
          final revised =
              interventionResult.modifications!['revisedContent'] as String?;
          if (revised != null) output = revised;
        }
      }

      // Step 6: Learning
      if (learn != null && output.isNotEmpty) {
        try {
          await learn!([
            CandidateRecord(
              id: '',
              workspaceId: 'default',
              type: 'flowbrain.ask',
              content: {'output': output, 'request': request},
              confidence: 0.5,
              createdAt: DateTime.now(),
            ),
          ]);
        } catch (e) {
          _log.warning('Learning step failed (non-fatal): $e');
        }
      }

      _log.fine('AskPipeline.run complete traceId=$tid');
      return AskResult(
        response: output,
        agentId: agent.id,
        traceId: tid,
        skillResult: skillResult,
      );
    } catch (e) {
      _log.severe('AskPipeline.run failed traceId=$tid: $e');
      rethrow;
    }
  }
}

/// Generate a simple trace id.
String _generateTraceId() =>
    'fb-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
