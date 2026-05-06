/// TEST-02 — KnowledgeSystem.importBundle (FlowBrain wiring for the
/// two FlowBrain-owned bundle sections: PhilosophySection + AgentsSection).
library;

import 'package:flowbrain_core/flowbrain_core.dart';
import 'package:mcp_bundle/mcp_bundle.dart' as mb;
import 'package:test/test.dart';

class _MapEthosStore implements EthosStorePort {
  final Map<String, mb.EthosRecord> _byId = {};
  String? _activeId;

  @override
  Future<mb.EthosRecord?> getEthos(String id) async => _byId[id];

  @override
  Future<void> putEthos(mb.EthosRecord ethos) async {
    _byId[ethos.id] = ethos;
  }

  @override
  Future<List<mb.EthosRecord>> listEthos({int? limit}) async {
    final all = _byId.values.toList();
    return limit == null ? all : all.take(limit).toList();
  }

  @override
  Future<void> activateEthos(String id) async {
    _activeId = id;
  }

  @override
  Future<String?> getActiveEthosId() async => _activeId;
}

mb.McpBundle _bundle({
  List<mb.Philosophy>? philosophies,
  List<mb.AgentDefinition>? agents,
}) {
  return mb.McpBundle(
    manifest: const mb.BundleManifest(
      id: 'test-bundle',
      name: 'Test',
      version: '1.0.0',
    ),
    philosophy: philosophies != null
        ? mb.PhilosophySection(philosophies: philosophies)
        : null,
    agents:
        agents != null ? mb.AgentsSection(agents: agents) : null,
  );
}

void main() {
  group('KnowledgeSystem.importBundle', () {
    test('philosophy + agents land in stores when wired', () async {
      final ethosStore = _MapEthosStore();
      final ports = InfraPorts.inMemory().copyWith(ethosStore: ethosStore);
      final system = KnowledgeSystem.withAgents(infraPorts: ports);

      final bundle = _bundle(
        philosophies: [
          const mb.Philosophy(
            id: 'validated-patterns',
            name: 'Validated Patterns First',
            statement: 'Reuse proven patterns before designing new ones.',
            rationale: 'Saves verification cost.',
            examples: [
              mb.PhilosophyExample(description: 'Adopt vibe shell pattern.'),
            ],
          ),
        ],
        agents: [
          const mb.AgentDefinition(
            id: 'ui-designer',
            name: 'UI Designer',
            role: 'worker',
            profileIds: ['p-craftsman'],
            skillIds: ['sk-layout', 'sk-theme'],
            factSourceIds: ['mcp-ui-spec'],
            philosophyIds: ['validated-patterns'],
            systemPrompt: 'Honor the spec.',
            model: mb.AgentModelConfig(
              provider: 'anthropic',
              model: 'claude-opus-4-7',
              temperature: 0.4,
              maxTokens: 4096,
            ),
          ),
        ],
      );

      final summary =
          await system.importBundle(bundle, workspaceId: 'ws-test');

      expect(summary.philosophiesAdded, 1);
      expect(summary.agentsAdded, 1);
      expect(summary.agentsSkipped, 0);

      final ethos = await ethosStore.getEthos('validated-patterns');
      expect(ethos, isNotNull);
      expect(ethos!.name, 'Validated Patterns First');
      expect(ethos.payload['statement'], contains('Reuse proven patterns'));
      expect(ethos.active, isFalse);

      final agent = await system.agentRegistry!.get('ui-designer');
      expect(agent, isNotNull);
      expect(agent!.displayName, 'UI Designer');
      expect(agent.role, AgentRole.worker);
      expect(agent.tags['bind.profileIds'], 'p-craftsman');
      expect(agent.tags['bind.skillIds'], 'sk-layout,sk-theme');
      expect(agent.tags['bind.factSourceIds'], 'mcp-ui-spec');
      expect(agent.tags['bind.philosophyIds'], 'validated-patterns');
      expect(agent.systemPrompt, 'Honor the spec.');
      expect(agent.model.provider, 'anthropic');
      expect(agent.model.model, 'claude-opus-4-7');
      expect(agent.model.temperature, 0.4);
      expect(agent.model.maxTokens, 4096);

      await system.shutdown();
    });

    test('re-import is idempotent — duplicates skipped', () async {
      final ethosStore = _MapEthosStore();
      final ports = InfraPorts.inMemory().copyWith(ethosStore: ethosStore);
      final system = KnowledgeSystem.withAgents(infraPorts: ports);

      final bundle = _bundle(
        agents: [
          const mb.AgentDefinition(id: 'a1', name: 'A1', role: 'worker'),
        ],
      );

      final first = await system.importBundle(bundle, workspaceId: 'w');
      final second = await system.importBundle(bundle, workspaceId: 'w');

      expect(first.agentsAdded, 1);
      expect(first.agentsSkipped, 0);
      expect(second.agentsAdded, 0);
      expect(second.agentsSkipped, 1);

      await system.shutdown();
    });

    test('without infra (stub) — silent skip, summary all zero', () async {
      final system = KnowledgeSystem.stub();
      final bundle = _bundle(
        philosophies: [
          const mb.Philosophy(
            id: 'p1',
            name: 'P',
            statement: 'S',
          ),
        ],
        agents: [
          const mb.AgentDefinition(id: 'a1', name: 'A', role: 'worker'),
        ],
      );
      final summary = await system.importBundle(bundle);
      expect(summary.philosophiesAdded, 0,
          reason: 'no ethosStore wired');
      expect(summary.agentsAdded, 0,
          reason: 'agent subsystem not activated');
      await system.shutdown();
    });

    test('missing sections are no-op', () async {
      final ethosStore = _MapEthosStore();
      final ports = InfraPorts.inMemory().copyWith(ethosStore: ethosStore);
      final system = KnowledgeSystem.withAgents(infraPorts: ports);

      final bundle = _bundle(); // neither philosophy nor agents
      final summary = await system.importBundle(bundle);

      expect(summary.philosophiesAdded, 0);
      expect(summary.agentsAdded, 0);
      expect(summary.agentsSkipped, 0);
      expect(await ethosStore.listEthos(), isEmpty);

      await system.shutdown();
    });

    test('role string maps to AgentRole enum', () async {
      final ports =
          InfraPorts.inMemory().copyWith(ethosStore: _MapEthosStore());
      final system = KnowledgeSystem.withAgents(infraPorts: ports);

      final bundle = _bundle(
        agents: [
          const mb.AgentDefinition(id: 'w', name: 'W', role: 'worker'),
          const mb.AgentDefinition(id: 'm', name: 'M', role: 'manager'),
          const mb.AgentDefinition(id: 'r', name: 'R', role: 'reviewer'),
          const mb.AgentDefinition(id: 'x', name: 'X', role: 'unknown-role'),
        ],
      );

      await system.importBundle(bundle, workspaceId: 'ws');
      final w = await system.agentRegistry!.get('w');
      final m = await system.agentRegistry!.get('m');
      final r = await system.agentRegistry!.get('r');
      final x = await system.agentRegistry!.get('x');

      expect(w!.role, AgentRole.worker);
      expect(m!.role, AgentRole.manager);
      expect(r!.role, AgentRole.reviewer);
      expect(x!.role, AgentRole.worker,
          reason: 'unknown role falls back to worker');

      await system.shutdown();
    });

    test('null model config maps to ModelSpec.stub', () async {
      final ports =
          InfraPorts.inMemory().copyWith(ethosStore: _MapEthosStore());
      final system = KnowledgeSystem.withAgents(infraPorts: ports);

      final bundle = _bundle(
        agents: [
          const mb.AgentDefinition(id: 'a1', name: 'A', role: 'worker'),
        ],
      );
      await system.importBundle(bundle, workspaceId: 'ws');
      final a = await system.agentRegistry!.get('a1');
      expect(a!.model.model, 'stub-1');

      await system.shutdown();
    });
  });
}
