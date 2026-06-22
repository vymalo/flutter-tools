import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'package:vymalo_flutter_tools/vymalo_flutter_tools.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<void>(
    'flutter-tools',
    'Reusable Flutter CI/CD steps for Vymalo projects.',
  )
    ..addCommand(CodegenCommand())
    ..addCommand(AndroidBuildCommand());

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

/// `--verbose` forces live output; otherwise quiet unless GitHub step-debug is
/// on (the StepRunner reads RUNNER_DEBUG when this is null).
bool? _verbose(ArgResults a) => a.flag('verbose') ? true : null;

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
          help: 'Drop pubspec.lock + build_runner clean before the API build.')
      ..addFlag('upgrade-dart-style',
          defaultsTo: false,
          help: 'dart pub upgrade dart_style before the API build.')
      ..addOption('dart', defaultsTo: 'dart')
      ..addOption('flutter', defaultsTo: 'flutter')
      ..addFlag('verbose',
          defaultsTo: false, help: 'Stream command output live.')
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
    await StepRunner(dryRun: a.flag('dry-run'), verbose: _verbose(a))
        .run(planCodegen(config));
  }
}

/// `flutter-tools android-build` — signed Android APK/AAB build. Signing secrets
/// come from the environment (never flags): ANDROID_KEYSTORE_BASE64,
/// ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD. With no
/// keystore the APK falls back to an unsigned debug build.
class AndroidBuildCommand extends Command<void> {
  AndroidBuildCommand() {
    argParser
      ..addOption('workspace', defaultsTo: Directory.current.path)
      ..addOption('project-dir', defaultsTo: 'mobile')
      ..addOption('build-number', help: 'Android versionCode (--build-number).')
      ..addOption('artifacts',
          defaultsTo: 'both', allowed: ['apk', 'aab', 'both'])
      ..addMultiOption('dart-define',
          help: 'KEY=VALUE, repeatable → --dart-define=KEY=VALUE.')
      ..addOption('flutter', defaultsTo: 'flutter')
      ..addFlag('verbose',
          defaultsTo: false, help: 'Stream command output live.')
      ..addFlag('dry-run', defaultsTo: false);
  }

  @override
  final String name = 'android-build';
  @override
  final String description =
      'Build a signed Android APK/AAB (signing secrets from the environment).';

  @override
  Future<void> run() async {
    final a = argResults!;
    final env = Platform.environment;
    final keystoreB64 = (env['ANDROID_KEYSTORE_BASE64'] ?? '').trim();
    final signed = keystoreB64.isNotEmpty;

    var keystorePath = '';
    if (signed) {
      final bytes = base64.decode(keystoreB64.replaceAll(RegExp(r'\s'), ''));
      final f = File(
          '${Directory.systemTemp.path}/vymalo-${DateTime.now().microsecondsSinceEpoch}.keystore');
      f.writeAsBytesSync(bytes);
      keystorePath = f.path;
    }

    final artifacts = switch (a.option('artifacts')) {
      'apk' => {AndroidArtifact.apk},
      'aab' => {AndroidArtifact.aab},
      _ => {AndroidArtifact.apk, AndroidArtifact.aab},
    };

    final config = AndroidBuildConfig(
      workspace: a.option('workspace')!,
      projectDir: a.option('project-dir')!,
      signed: signed,
      keystorePath: keystorePath,
      keystorePassword: (env['ANDROID_KEYSTORE_PASSWORD'] ?? '').trim(),
      keyAlias: (env['ANDROID_KEY_ALIAS'] ?? '').trim(),
      keyPassword: (env['ANDROID_KEY_PASSWORD'] ?? '').trim(),
      buildNumber: a.option('build-number'),
      artifacts: artifacts,
      dartDefines: a.multiOption('dart-define'),
      flutter: a.option('flutter')!,
    );

    try {
      await StepRunner(dryRun: a.flag('dry-run'), verbose: _verbose(a))
          .run(planAndroidBuild(config));
    } finally {
      if (keystorePath.isNotEmpty && File(keystorePath).existsSync()) {
        File(keystorePath).deleteSync();
      }
    }
    _emitOutputs(config);
  }

  void _emitOutputs(AndroidBuildConfig c) {
    final appDir = resolveIn(c.workspace, c.projectDir);
    final lines = <String>['signed=${c.signed}'];
    if (c.artifacts.contains(AndroidArtifact.apk)) {
      lines.add('apk-path='
          '${resolveIn(appDir, androidArtifactPath(AndroidArtifact.apk, signed: c.signed))}');
    }
    if (c.signed && c.artifacts.contains(AndroidArtifact.aab)) {
      lines.add('aab-path='
          '${resolveIn(appDir, androidArtifactPath(AndroidArtifact.aab, signed: c.signed))}');
    }
    final outFile = Platform.environment['GITHUB_OUTPUT'];
    if (outFile != null && outFile.isNotEmpty) {
      File(outFile)
          .writeAsStringSync('${lines.join('\n')}\n', mode: FileMode.append);
    } else {
      for (final l in lines) {
        stdout.writeln('output: $l');
      }
    }
  }
}
