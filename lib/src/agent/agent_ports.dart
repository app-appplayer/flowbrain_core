/// FlowBrain Core — the two ports through which an agent reads from and
/// writes to the host's knowledge store (platform spec 30 §5.1).
///
/// The core knows no store. A host that keeps knowledge plugs an adapter in
/// through `InfraPorts`; without one an agent behaves as before.
library;

import 'dart:async';

/// Where in a flow (workflow or process) an agent was called: the third axis
/// of every record (platform spec 12 §0.5). A flow engine runs a step inside
/// [run]; whatever an agent produces during it carries the reference.
class FlowStepRef {
  const FlowStepRef({
    required this.kind,
    required this.flowId,
    this.runId,
    this.stepId,
  });

  /// `workflow` · `behavior`.
  final String kind;
  final String flowId;
  final String? runId;
  final String? stepId;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        'flowId': flowId,
        if (runId != null) 'runId': runId,
        if (stepId != null) 'stepId': stepId,
      };

  static final Object _key = Object();

  /// The step being run in the current async context, if any.
  static FlowStepRef? get current => Zone.current[_key] as FlowStepRef?;

  /// Runs [body] as this step; agents called inside it see [current].
  static T run<T>(FlowStepRef ref, T Function() body) =>
      Zone.current.fork(zoneValues: <Object?, Object?>{_key: ref}).run(body);
}

/// What the store gave an agent for one request.
class AgentContext {
  const AgentContext({required this.text, this.factIds = const <String>[]});

  /// For the system prompt.
  final String text;

  /// Ids of the facts the text was built from — they go on the record of what
  /// the agent then produced.
  final List<String> factIds;
}

/// What an agent is given to read when it takes a request: the work state
/// and the knowledge that bears on it.
abstract class AgentContextPort {
  /// Null when the store has nothing for this request. [workspaceId] is the
  /// agent's workspace — a host that keeps one store per workspace picks it
  /// by that. With [asOf] the context is what the store held at that instant
  /// (a re-interpretation).
  Future<AgentContext?> contextFor(String agentId, String request,
      {String? workspaceId, DateTime? asOf});
}

/// What an agent produced, with the interpretation it came from.
class AgentOutput {
  const AgentOutput({
    required this.kind,
    required this.agentId,
    required this.request,
    required this.content,
    required this.model,
    required this.at,
    this.workspaceId,
    this.flow,
    this.lens = const <String, List<String>>{},
    this.factIds = const <String>[],
    this.extra = const <String, Object?>{},
  });

  /// `ask` · `review` · `route`.
  final String kind;
  final String agentId;

  /// What the agent was asked (for a review, the reply under review).
  final String request;

  /// What it answered (for a review, the verdict as JSON; for a route, the
  /// decision as JSON).
  final String content;
  final String model;
  final DateTime at;

  /// The workspace the agent belongs to.
  final String? workspaceId;

  /// The flow step the agent was called from, when it was called from one.
  final FlowStepRef? flow;

  /// The lens the output was interpreted through: axis name (`profile` ·
  /// `philosophy` · `skill`) → the agent's forked asset refs.
  final Map<String, List<String>> lens;

  /// Ids of the facts the agent read to produce it.
  final List<String> factIds;

  /// Kind-specific fields (a review's `targetAgentId` · `valuePriorityId`).
  final Map<String, Object?> extra;
}

/// Where an agent's outputs are put down. Called after the output exists; a
/// failure is reported as an event and never costs the agent its answer.
abstract class AgentOutputPort {
  Future<void> record(AgentOutput output);
}
