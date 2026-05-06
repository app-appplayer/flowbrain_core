/// TEST-23 — Multi-profile workspace fork (per-id profile).
///
/// Sister to TEST-22 (multi-ethos). Verifies that a [ProfileRegistry]
/// wired through `KnowledgeSystem.profileRuntime` lets `ForkEngine`
/// resolve different `Profile`s for different agents on the same
/// workspace by id, surface them in `listIntegrated`, and rejects
/// missing-id assignments (no fallback for profiles — unlike the
/// philosophy axis which falls back to the active ethos).
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:test/test.dart';

Profile _profile(String id, {String? name}) => Profile(
      id: id,
      name: name ?? id,
      version: '1.0.0',
    );

KnowledgeSystem _build({required ProfileRegistry registry}) {
  final infra = InfraPorts.inMemory().copyWith(
    llm: StubLlmPort(),
    mcp: const StubMcpPort(),
  );
  final eventBus = KnowledgeEventBus();

  final skillRuntime = SkillRuntime(
    registry: MemorySkillRegistry(),
    ports: SkillPorts(llm: StubLlmPort(), mcp: const StubMcpPort()),
  );
  final profileRuntime = ProfileRuntime(
    registry: registry,
    engines: EnginePorts.stub(),
  );

  late final KnowledgeSystem system;
  final subsystem = AgentSubsystem.create(
    knowledgeSystemRef: () => system,
    infraPorts: infra,
    eventBus: eventBus,
    config: AgentConfig.defaults,
  );
  system = KnowledgeSystem(
    config: KnowledgeConfig.defaults,
    infraPorts: infra,
    skillRuntime: skillRuntime,
    profileRuntime: profileRuntime,
    agentRegistry: subsystem.registry,
    agentRuntime: subsystem.runtime,
    eventBus: eventBus,
  );
  return system;
}

void main() {
  group('Multi-profile workspace — per-id profile fork', () {
    test('T-AGT-PROF-001 — listIntegrated enumerates every registry entry',
        () async {
      final registry = ProfileRegistry();
      registry.register(_profile('analyst'));
      registry.register(_profile('translator'));
      final system = _build(registry: registry);

      final entries =
          await system.agents.listIntegrated('w1', AgentAxis.profile);
      final pool = entries.where((e) => e.isPool).toList();

      expect(pool.length, 2);
      final ids = pool.map((e) => e.source.encode()).toSet();
      expect(ids, containsAll([
        'pool:analyst',
        'pool:translator',
      ]));
    });

    test('T-AGT-PROF-002 — different agents fork different profiles by id',
        () async {
      final registry = ProfileRegistry();
      registry.register(_profile('analyst', name: 'Analyst'));
      registry.register(_profile('translator', name: 'Translator'));
      final system = _build(registry: registry);

      await system.agents.createAgent(
        id: 'data_ops',
        displayName: 'data_ops',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );
      await system.agents.createAgent(
        id: 'l10n',
        displayName: 'l10n',
        model: ModelSpec.stub(),
        workspaceId: 'w1',
      );

      await system.agents.assignProfileFromPool('data_ops', 'analyst');
      await system.agents.assignProfileFromPool('l10n', 'translator');

      // Each agent's owned profile fork derives from a distinct
      // profile id — surfaces in listIntegrated as agent-owned entries
      // whose lineage chain points at different pool seeds.
      final entries =
          await system.agents.listIntegrated('w1', AgentAxis.profile);
      final owned = entries.where((e) => e.isAgentOwned).toList();
      expect(owned.length, 2);
      final lineageById = {
        for (final e in owned) e.ownerAgentId: e.lineage.first,
      };
      expect(lineageById['data_ops'], 'pool:analyst');
      expect(lineageById['l10n'], 'pool:translator');
    });

    test(
      'T-AGT-PROF-003 — registry miss raises StateError',
      () async {
        final registry = ProfileRegistry();
        registry.register(_profile('analyst'));
        final system = _build(registry: registry);

        await system.agents.createAgent(
          id: 'a1',
          displayName: 'a1',
          model: ModelSpec.stub(),
          workspaceId: 'w1',
        );

        // Unknown profile id — no fallback (unlike philosophy). The
        // assignment surfaces the registry miss as a StateError so
        // hosts can react explicitly instead of silently storing a
        // stub fork.
        await expectLater(
          () => system.agents.assignProfileFromPool('a1', 'unknown-profile'),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
