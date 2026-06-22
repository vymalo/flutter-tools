import 'dart:io';

import 'package:args/command_runner.dart';

import 'package:vymalo_flutter_tools/src/codegen.dart';
import 'package:vymalo_flutter_tools/src/runner.dart';
import 'package:vymalo_flutter_tools/src/step.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<void>(
    'flutter-tools',
    'Reusable Flutter CI/CD steps for Vymalo projects.',
  )..addCommand(CodegenCommand());

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64); // EX_USAGE
  } on StepFailure catch (e) {
    stderr.writeln('\n✗ $e');
    exit(1);
  }
}

/// `flutter-tools codegen` — the layered OpenAPI + build_runner codegen.
class CodegenCommand extends Command<void> {
  CodegenCommand() {
    argParser
      ..addOption('workspace',
          help: 'Repo root the other paths resolve against.',
          defaultsTo: Directory.current.path)
      ..addOption('project-dir', defaultsTo: 'mobile', help: 'Flutter app dir.')
      ..addOption('api-dir',
          defaultsTo: 'mobile/api', help: 'Generated OpenAPI client dir.')
      ..addOption('codegen-tool-dir',
          defaultsTo: 'mobile/tool/openapi_codegen',
          help: 'Dir whose build_runner drives the OpenAPI Generator CLI.')
      ..addOption('api-pubspec-template',
          defaultsTo: '',
          help: 'Tracked pubspec template copied to <api-dir>/pubspec.yaml. '
              'When set, takes precedence over --sdk-floor.')
      ..addOption('sdk-floor',
          defaultsTo: '>=3.12.0 <4.0.0',
          help: 'SDK constraint forced into the generated API pubspec.')
      ..addFlag('clean',
          defaultsTo: true,
          help: 'Drop pubspec.lock + build_runner clean before the API build '
              '(robust on persistent runners).')
      ..addFlag('upgrade-dart-style',
          defaultsTo: false,
          help: 'dart pub upgrade dart_style before the API build.')
      ..addOption('dart', defaultsTo: 'dart')
      ..addOption('flutter', defaultsTo: 'flutter')
      ..addFlag('dry-run',
          defaultsTo: false, help: 'Print the plan without executing it.');
  }

  @override
  final String name = 'codegen';
  @override
  final String description =
      'Run the layered codegen: OpenAPI client + API *.g.dart + app build_runner.';

  @override
  Future<void> run() async {
    final a = argResults!;
    final config = CodegenConfig(
      workspace: a.option('workspace')!,
      projectDir: a.option('project-dir')!,
      apiDir: a.option('api-dir')!,
      codegenToolDir: a.option('codegen-tool-dir')!,
      apiPubspecTemplate: a.option('api-pubspec-template')!,
      sdkFloor: a.option('sdk-floor')!,
      clean: a.flag('clean'),
      upgradeDartStyle: a.flag('upgrade-dart-style'),
      dart: a.option('dart')!,
      flutter: a.option('flutter')!,
    );
    await StepRunner(dryRun: a.flag('dry-run')).run(planCodegen(config));
  }
}
