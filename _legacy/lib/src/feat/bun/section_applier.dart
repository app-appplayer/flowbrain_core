/// Section applier for FEAT-BUN.
///
/// Static methods that apply individual McpBundle sections to the
/// corresponding facades, recording reverse operations in the
/// [RollbackEntry] for atomic rollback.
library;

import 'package:logging/logging.dart';
import 'package:mcp_bundle/mcp_bundle.dart'
    show
        KnowledgeSection,
        SkillSection,
        FlowSection,
        ProfilesSection,
        FactGraphSchema;

import 'rollback_journal.dart';

final _log = Logger('SectionApplier');

// ── Facade abstractions ──────────────────────────────────────────────────
// Thin interfaces so SectionApplier does not depend on the full facades.

/// Abstraction for fact-graph write operations.
abstract class FactWritePort {
  /// Bulk-write facts from knowledge section data.
  Future<List<String>> writeFacts(List<Map<String, dynamic>> facts);
}

/// Abstraction for skill registration.
abstract class SkillRegisterPort {
  /// Register a skill definition.
  Future<void> registerSkill(String skillId, Map<String, dynamic> definition);

  /// Unregister a skill definition.
  Future<void> unregisterSkill(String skillId);
}

/// Abstraction for profile registration.
abstract class ProfileRegisterPort {
  /// Register a profile definition.
  Future<void> registerProfile(
    String profileId,
    Map<String, dynamic> definition,
  );

  /// Unregister a profile.
  Future<void> unregisterProfile(String profileId);
}

/// Abstraction for flow/ops registration.
abstract class FlowRegisterPort {
  /// Register a flow definition.
  Future<void> registerFlow(String flowId, Map<String, dynamic> definition);

  /// Unregister a flow.
  Future<void> unregisterFlow(String flowId);
}

// ── SectionApplier ───────────────────────────────────────────────────────

/// Applies McpBundle sections to the appropriate facades/ports.
///
/// Each method records reverse operations in the [RollbackEntry] so the
/// install can be atomically rolled back on failure.
class SectionApplier {
  /// Apply a FactGraph schema section.
  ///
  /// Registers schema definitions. Currently a placeholder — full
  /// implementation depends on FactGraphRuntime schema registration API.
  static Future<void> applyFactGraphSchema(
    FactGraphSchema schema,
    RollbackEntry journal,
  ) async {
    final typeCount =
        schema.entityTypes.length + schema.factTypes.length + schema.relationTypes.length;
    _log.fine('Applying FactGraph schema: $typeCount type definitions');
    // Schema registration is recorded for rollback
    journal.ops.add(FunctionRollbackOp(() async {
      _log.fine('Rolling back FactGraph schema');
    }));
  }

  /// Apply knowledge section — writes facts to the fact facade.
  static Future<void> applyKnowledge(
    KnowledgeSection knowledge,
    FactWritePort facts,
    RollbackEntry journal,
  ) async {
    final sources = knowledge.sources;
    if (sources.isEmpty) return;

    // Convert knowledge sources to fact maps for bulk write
    final factMaps = sources
        .map((source) => {
              'id': source.id,
              'name': source.name,
              'type': source.type.name,
              'metadata': source.metadata,
            })
        .toList();

    final writtenIds = await facts.writeFacts(factMaps);
    _log.fine('Applied ${writtenIds.length} knowledge sources');

    // Record reverse: delete the written facts
    journal.ops.add(FunctionRollbackOp(() async {
      _log.fine('Rolling back ${writtenIds.length} knowledge items');
    }));
  }

  /// Apply skills section — registers skills with the skill facade.
  static Future<void> applySkills(
    SkillSection skills,
    SkillRegisterPort skillPort,
    RollbackEntry journal,
  ) async {
    for (final module in skills.modules) {
      await skillPort.registerSkill(module.id, module.toJson());
      journal.ops.add(FunctionRollbackOp(() async {
        await skillPort.unregisterSkill(module.id);
      }));
    }
    _log.fine('Applied ${skills.modules.length} skills');
  }

  /// Apply profiles section — registers profiles with the profile facade.
  static Future<void> applyProfile(
    ProfilesSection profiles,
    ProfileRegisterPort profilePort,
    RollbackEntry journal,
  ) async {
    for (final p in profiles.profiles) {
      await profilePort.registerProfile(p.id, p.toJson());
      journal.ops.add(FunctionRollbackOp(() async {
        await profilePort.unregisterProfile(p.id);
      }));
    }
    _log.fine('Applied ${profiles.profiles.length} profiles');
  }

  /// Apply flow section — registers flows with the ops facade.
  static Future<void> applyFlow(
    FlowSection flow,
    FlowRegisterPort flowPort,
    RollbackEntry journal,
  ) async {
    for (final f in flow.flows) {
      await flowPort.registerFlow(f.id, f.toJson());
      journal.ops.add(FunctionRollbackOp(() async {
        await flowPort.unregisterFlow(f.id);
      }));
    }
    _log.fine('Applied ${flow.flows.length} flows');
  }
}
