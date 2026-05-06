/// Learning loop that stores LLM responses as candidate records.
///
/// When the KFL adapter falls through to the primary model (Tier.miss),
/// the response is persisted via [CandidatesPort] so it can be reviewed
/// and promoted into the knowledge graph.
library;

import 'package:logging/logging.dart';
import 'package:mcp_bundle/mcp_bundle.dart'
    show LlmResponse, CandidatesPort, CandidateRecord;

final _log = Logger('flowbrain.kfl.learning_loop');

/// Stores LLM responses as pending candidates for future knowledge hits.
class LearningLoop {
  /// Optional candidates port — learning is a no-op when null.
  final CandidatesPort? candidates;

  const LearningLoop({this.candidates});

  /// Persist an LLM response as a candidate record.
  ///
  /// Returns silently if [candidates] is null or if storage fails
  /// (warn-level log only; the caller's response is unaffected).
  Future<void> store({
    required String prompt,
    required LlmResponse response,
    String workspaceId = 'default',
  }) async {
    if (candidates == null) return;

    try {
      await candidates!.createCandidates([
        CandidateRecord(
          id: '',
          workspaceId: workspaceId,
          type: 'kfl.learning',
          content: {
            'text': response.content,
            'prompt': prompt,
            'model': response.model ?? 'unknown',
          },
          confidence: _extractConfidence(response),
          createdAt: DateTime.now(),
        ),
      ]);
    } catch (e) {
      _log.warning('Failed to store learning candidate: $e');
    }
  }

  /// Extract a confidence value from the response metadata, falling
  /// back to a sensible default.
  double _extractConfidence(LlmResponse response) {
    final meta = response.metadata;
    if (meta != null && meta.containsKey('confidence')) {
      final raw = meta['confidence'];
      if (raw is num) return raw.toDouble().clamp(0.0, 1.0);
    }
    return 0.7;
  }
}
