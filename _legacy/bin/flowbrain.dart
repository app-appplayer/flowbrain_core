/// FlowBrain CLI entrypoint.
///
/// Usage: dart run flowbrain <command> [options]
///
/// Commands:
///   init      Generate a flowbrain.yaml template
///   serve     Boot FlowBrain and start MCP servers
///   doctor    Run diagnostic checks
///   pack      Manage knowledge packs
import 'dart:io';

import 'package:flowbrain_core/src/core/boot/cli.dart';

Future<void> main(List<String> args) async {
  final exitCode = await FlowBrainCli.run(args);
  exit(exitCode);
}
