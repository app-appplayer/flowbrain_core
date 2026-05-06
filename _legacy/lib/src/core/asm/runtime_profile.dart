/// RuntimeProfile — defines 6 deployment profiles per DDD §3.3 / SDD §5.5.
///
/// Each profile determines which optional runtimes are activated and
/// which ports are required at boot time.
library;

import 'errors.dart';

/// Runtime profile controlling which optional runtimes and ports
/// are activated during FlowBrain assembly.
enum RuntimeProfile {
  /// Full orchestration — all 5 runtimes active.
  full,

  /// Skill + LLM only, no RAG or fact graph.
  skillLlm,

  /// Skill + LLM + MCP server/client.
  skillLlmMcp,

  /// Skill + LLM + RAG (fact graph for retrieval).
  skillLlmRag,

  /// Read-only — facts/claims/entities queries only.
  readOnly,

  /// Ingest-only — evidence ingestion and candidate creation only.
  ingestOnly;

  /// Whether this profile requires a FactGraphRuntime.
  bool get needsFactGraph => switch (this) {
        readOnly || ingestOnly || full || skillLlmRag => true,
        _ => false,
      };

  /// Whether this profile requires a SkillRuntime.
  bool get needsSkill => this != readOnly && this != ingestOnly;

  /// Whether this profile requires a ProfileRuntime.
  bool get needsProfile => this == full;

  /// Whether this profile requires a PhilosophyEngine.
  bool get needsPhilosophy => this == full;

  /// Whether this profile requires an OpsRuntime.
  bool get needsOps => this == full;

  /// List of port type names required by this profile.
  List<String> get requiredPorts => switch (this) {
        full => const [
            'FactsPort',
            'ClaimsPort',
            'EntitiesPort',
            'CandidatesPort',
            'PatternsPort',
            'SummariesPort',
            'EvidencePort',
            'SkillRuntimePort',
            'SkillRegistryPort',
            'ClaimsPort',
            'RunsPort',
            'AppraisalPort',
            'DecisionPort',
            'MetricsPort',
            'ProfileSummariesPort',
            'PhilosophyPort',
            'EthosStorePort',
            'WorkflowPort',
            'PipelinePort',
            'RunbookPort',
            'ScheduleTriggerPort',
            'AuditPort',
            'LlmPort',
            'StoragePort',
            'EventPort',
            'NotificationPort',
            'ApprovalPort',
            'MetricPort',
          ],
        skillLlm => const [
            'LlmPort',
            'SkillRuntimePort',
            'SkillRegistryPort',
            'StoragePort',
          ],
        skillLlmMcp => const [
            'LlmPort',
            'SkillRuntimePort',
            'SkillRegistryPort',
            'StoragePort',
            'McpPort',
          ],
        skillLlmRag => const [
            'LlmPort',
            'SkillRuntimePort',
            'SkillRegistryPort',
            'StoragePort',
            'RetrievalPort',
            'ContextBundlePort',
          ],
        readOnly => const [
            'FactsPort',
            'ClaimsPort',
            'EntitiesPort',
            'StoragePort',
          ],
        ingestOnly => const [
            'EvidencePort',
            'FactsPort',
            'CandidatesPort',
            'StoragePort',
          ],
      };

  /// Parse a profile string into a [RuntimeProfile].
  ///
  /// Accepts both camelCase enum names ('skillLlm') and snake_case
  /// variants ('skill_llm'). Throws [ValidationError] for unknown values.
  static RuntimeProfile fromString(String s) => values.firstWhere(
        (p) => p.name.toLowerCase() == s.replaceAll('_', '').toLowerCase(),
        orElse: () => throw ValidationError('Unknown profile: $s'),
      );
}
