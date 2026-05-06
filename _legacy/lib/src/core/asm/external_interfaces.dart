/// External interface wiring stubs per SDD section 4 / DDD core-asm.md.
///
/// Provides type aliases and placeholder classes for external interface
/// packages (mcp_channel, mcp_ingest, mcp_io, mcp_form, etc.) that
/// will be wired during assembly based on the active RuntimeProfile.
///
/// These are stub definitions. Actual adapters will be implemented when
/// the corresponding interface packages are integrated.
library;

/// Placeholder for the external interface registry.
///
/// During assembly, the Assembler queries the active RuntimeProfile to
/// determine which external interface adapters to instantiate and
/// registers them here for lifecycle management.
class ExternalInterfaces {
  /// Channel interface adapter (mcp_channel).
  final dynamic channel;

  /// Ingest interface adapter (mcp_ingest).
  final dynamic ingest;

  /// IO interface adapter (mcp_io).
  final dynamic io;

  /// Form interface adapter (mcp_form).
  final dynamic form;

  /// Flow runtime adapter (mcp_flow_runtime).
  final dynamic flowRuntime;

  /// Analysis adapter (mcp_analysis).
  final dynamic analysis;

  const ExternalInterfaces({
    this.channel,
    this.ingest,
    this.io,
    this.form,
    this.flowRuntime,
    this.analysis,
  });

  /// Create an empty set of external interfaces (no adapters wired).
  const ExternalInterfaces.none()
      : channel = null,
        ingest = null,
        io = null,
        form = null,
        flowRuntime = null,
        analysis = null;
}
