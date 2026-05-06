/// FlowBrain Core — `AgentSubsystem.create` wiring helper.
///
/// Builds the four cooperating components (AgentRegistry, ConversationStore,
/// ForkEngine, AgentRuntime) from a single set of inputs so that
/// `KnowledgeSystem.withAgents` and host-side wire code can stay short.
library;

import 'package:mcp_knowledge/mcp_knowledge.dart' show KnowledgeEventBus;

import '../system/knowledge_ports.dart';
import 'agent_config.dart';
import 'agent_exception.dart';
import 'agent_registry.dart';
import 'agent_runtime.dart';
import 'conversation_store.dart';
import 'fork_engine.dart';

/// Bundle of components produced by [AgentSubsystem.create]. Hosts pass the
/// `registry` and `runtime` into the wrapping `KnowledgeSystem`.
class AgentSubsystem {
  AgentSubsystem._({
    required this.registry,
    required this.runtime,
  });

  final AgentRegistry registry;
  final AgentRuntime runtime;

  ConversationStore get conversationStore => runtime.conversationStore;
  ForkEngine get forkEngine => runtime.forkEngine;

  /// Wire all four components. Throws
  /// `ConversationStoreUnavailableException` when `infraPorts.kvStorage`
  /// is null (per FR-FBCORE-AGT-072).
  static AgentSubsystem create({
    required Object Function() knowledgeSystemRef,
    required InfraPorts infraPorts,
    required KnowledgeEventBus eventBus,
    required AgentConfig config,
  }) {
    final kv = infraPorts.kvStorage;
    if (kv == null) {
      throw const ConversationStoreUnavailableException(
        'KvStoragePort missing — Agent Subsystem requires kvStorage',
      );
    }
    final registry = AgentRegistry(
      kvStorage: kv,
      knowledgeSystemRef: knowledgeSystemRef,
      config: config,
      eventBus: eventBus,
    );
    final conversationStore = ConversationStore(
      kvStorage: kv,
      config: config,
    );
    final forkEngine = ForkEngine(
      registry: registry,
      eventBus: eventBus,
      config: config,
    );
    final runtime = AgentRuntime(
      registry: registry,
      conversationStore: conversationStore,
      forkEngine: forkEngine,
      config: config,
      eventBus: eventBus,
      defaultLlm: infraPorts.llm,
      llmProviders: infraPorts.llmProviders,
    );
    return AgentSubsystem._(registry: registry, runtime: runtime);
  }
}
