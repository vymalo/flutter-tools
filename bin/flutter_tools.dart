import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'package:vymalo_flutter_tools/vymalo_flutter_tools.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<void>(
    'flutter-tools',
    'Reusable Flutter CI/CD steps for Vymalo projects.',
  )
    ..addCommand(CodegenCommand())
    ..addCommand(VersionStampCommand())
    ..addCommand(AndroidBuildCommand())
    ..addCommand(IosBuildCommand())
    ..addCommand(PlaySubmitCommand())
    ..addCommand(S3UploadCommand());

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

/// `flutter-tools version-stamp` — rewrite pubspec `version:` to `x.y.z+<build>`
/// (marketing version left intact), then emit the resolved version as outputs.
class VersionStampCommand extends Command<void> {
  VersionStampCommand() {
    argParser
      ..addOption('workspace', defaultsTo: Directory.current.path)
      ..addOption('project-dir', defaultsTo: 'mobile')
      ..addOption('build-number',
          mandatory: true, help: 'The +build value (e.g. the CI run number).')
      ..addFlag('verbose', defaultsTo: false)
      ..addFlag('dry-run', defaultsTo: false);
  }

  @override
  final String name = 'version-stamp';
  @override
  final String description =
      'Stamp a build number into pubspec.yaml (version: x.y.z+<build>).';

  @override
  Future<void> run() async {
    final a = argResults!;
    final config = VersionStampConfig(
      workspace: a.option('workspace')!,
      projectDir: a.option('project-dir')!,
      buildNumber: a.option('build-number')!,
    );
    await StepRunner(dryRun: a.flag('dry-run'), verbose: _verbose(a))
        .run(planVersionStamp(config));
    _emitVersionOutputs(config);
  }

  void _emitVersionOutputs(VersionStampConfig c) {
    final pubspec =
        File(resolveIn(resolveIn(c.workspace, c.projectDir), 'pubspec.yaml'));
    final marketing = pubspec.existsSync()
        ? RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true)
            .firstMatch(pubspec.readAsStringSync())
            ?.group(1)
        : null;
    final version = marketing ?? '0.0.0';
    _emitOutput({
      'version': version,
      'build-number': c.buildNumber,
      'full-version': '$version+${c.buildNumber}',
    });
  }
}

/// `flutter-tools ios-build` — signed App Store IPA. Signing material comes from
/// the environment (never flags): IOS_CERTIFICATE_BASE64 / _PASSWORD,
/// IOS_APPSTORE_PROVISION_PROFILE_BASE64, APPLE_TEAM_ID, IOS_APPSTORE_PROFILE_NAME.
class IosBuildCommand extends Command<void> {
  IosBuildCommand() {
    argParser
      ..addOption('workspace', defaultsTo: Directory.current.path)
      ..addOption('project-dir', defaultsTo: 'mobile')
      ..addOption('app-id',
          defaultsTo: 'com.vymalo.vymalo', help: 'Bundle identifier.')
      ..addMultiOption('dart-define',
          help: 'KEY=VALUE, repeatable → --dart-define=KEY=VALUE.')
      ..addOption('flutter', defaultsTo: 'flutter')
      ..addOption('fastlane', defaultsTo: 'fastlane')
      ..addFlag('verbose', defaultsTo: false)
      ..addFlag('dry-run', defaultsTo: false);
  }

  @override
  final String name = 'ios-build';
  @override
  final String description =
      'Build a signed App Store IPA (cert/profile/keychain from the environment).';

  @override
  Future<void> run() async {
    final a = argResults!;
    final env = Platform.environment;
    final dryRun = a.flag('dry-run');

    final tmp = Directory.systemTemp.path;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final certPath = '$tmp/vymalo-$stamp.p12';
    final profilePath = '$tmp/vymalo-$stamp.mobileprovision';
    final keychainPath = '$tmp/vymalo-ci-$stamp.keychain-db';

    if (!dryRun) {
      File(certPath).writeAsBytesSync(base64.decode(
          (env['IOS_CERTIFICATE_BASE64'] ?? '').replaceAll(RegExp(r'\s'), '')));
      File(profilePath).writeAsBytesSync(base64.decode(
          (env['IOS_APPSTORE_PROVISION_PROFILE_BASE64'] ?? '')
              .replaceAll(RegExp(r'\s'), '')));
    }

    final rand = Random.secure();
    final keychainPassword =
        List.generate(24, (_) => rand.nextInt(16).toRadixString(16)).join();

    final config = IosBuildConfig(
      workspace: a.option('workspace')!,
      projectDir: a.option('project-dir')!,
      appId: a.option('app-id')!,
      teamId: (env['APPLE_TEAM_ID'] ?? '').trim(),
      profileName:
          (env['IOS_APPSTORE_PROFILE_NAME'] ?? 'Vymalo App Store').trim(),
      certPath: certPath,
      certPassword: (env['IOS_CERTIFICATE_PASSWORD'] ?? '').trim(),
      profilePath: profilePath,
      keychainPath: keychainPath,
      keychainPassword: keychainPassword,
      dartDefines: a.multiOption('dart-define'),
      flutter: a.option('flutter')!,
      fastlane: a.option('fastlane')!,
    );

    try {
      await StepRunner(dryRun: dryRun, verbose: _verbose(a))
          .run(planIosBuild(config));
    } finally {
      if (!dryRun) {
        await Process.run('security', ['delete-keychain', keychainPath]);
        for (final p in [
          certPath,
          profilePath,
          '$keychainPath.ExportOptions.plist',
        ]) {
          final f = File(p);
          if (f.existsSync()) f.deleteSync();
        }
      }
    }

    _emitIosBuildOutputs(config);
  }

  void _emitIosBuildOutputs(IosBuildConfig c) {
    final ipaDir = Directory(
        resolveIn(resolveIn(c.workspace, c.projectDir), 'build/ios/ipa'));
    var ipa = '';
    if (ipaDir.existsSync()) {
      final hits = ipaDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.ipa'));
      if (hits.isNotEmpty) ipa = hits.first.path;
    }
    _emitOutput({'ipa-path': ipa});
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
    _emitOutput({
      for (final l in lines)
        l.split('=').first: l.split('=').sublist(1).join('='),
    });
  }
}

/// Append `name=value` pairs to $GITHUB_OUTPUT (or print them locally).
void _emitOutput(Map<String, String> outputs) {
  final body = outputs.entries.map((e) => '${e.key}=${e.value}').join('\n');
  final outFile = Platform.environment['GITHUB_OUTPUT'];
  if (outFile != null && outFile.isNotEmpty) {
    File(outFile).writeAsStringSync('$body\n', mode: FileMode.append);
  } else {
    for (final e in outputs.entries) {
      stdout.writeln('output: ${e.key}=${e.value}');
    }
  }
}

/// `flutter-tools play-submit` — upload an AAB to a Google Play track via
/// Fastlane `supply`. Service account from GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64
/// (or GOOGLE_PLAY_SERVICE_ACCOUNT_JSON plaintext).
class PlaySubmitCommand extends Command<void> {
  PlaySubmitCommand() {
    argParser
      ..addOption('aab', mandatory: true, help: 'Path to the .aab to upload.')
      ..addOption('package-name', mandatory: true)
      ..addOption('track', defaultsTo: 'internal')
      ..addOption('release-status',
          defaultsTo: 'completed',
          allowed: ['completed', 'draft', 'halted', 'inProgress'])
      ..addOption('rollout', help: 'Staged-rollout fraction, e.g. 0.2.')
      ..addFlag('skip-upload-apk', defaultsTo: true)
      ..addFlag('skip-upload-metadata', defaultsTo: true)
      ..addFlag('skip-upload-changelogs', defaultsTo: true)
      ..addFlag('skip-upload-images', defaultsTo: true)
      ..addFlag('skip-upload-screenshots', defaultsTo: true)
      ..addFlag('changes-not-sent-for-review', defaultsTo: false)
      ..addOption('fastlane', defaultsTo: 'fastlane')
      ..addFlag('verbose', defaultsTo: false)
      ..addFlag('dry-run', defaultsTo: false);
  }

  @override
  final String name = 'play-submit';
  @override
  final String description =
      'Upload an AAB to a Google Play track (Fastlane supply).';

  @override
  Future<void> run() async {
    final a = argResults!;
    final env = Platform.environment;
    final b64 = (env['GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64'] ?? '').trim();
    final plain = env['GOOGLE_PLAY_SERVICE_ACCOUNT_JSON'] ?? '';
    if (b64.isEmpty && plain.isEmpty) {
      throw UsageException(
          'Set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64 (or _JSON).', usage);
    }
    final json = b64.isNotEmpty
        ? utf8.decode(base64.decode(b64.replaceAll(RegExp(r'\s'), '')))
        : plain;
    final keyFile = File('${Directory.systemTemp.path}/'
        'play-${DateTime.now().microsecondsSinceEpoch}.json');
    keyFile.writeAsStringSync(json);

    final config = PlaySubmitConfig(
      aabPath: a.option('aab')!,
      packageName: a.option('package-name')!,
      jsonKeyPath: keyFile.path,
      track: a.option('track')!,
      releaseStatus: a.option('release-status')!,
      rollout: a.option('rollout'),
      skipUploadApk: a.flag('skip-upload-apk'),
      skipUploadMetadata: a.flag('skip-upload-metadata'),
      skipUploadChangelogs: a.flag('skip-upload-changelogs'),
      skipUploadImages: a.flag('skip-upload-images'),
      skipUploadScreenshots: a.flag('skip-upload-screenshots'),
      changesNotSentForReview: a.flag('changes-not-sent-for-review'),
      fastlane: a.option('fastlane')!,
    );

    try {
      await StepRunner(dryRun: a.flag('dry-run'), verbose: _verbose(a))
          .run(planPlaySubmit(config));
    } finally {
      if (keyFile.existsSync()) keyFile.deleteSync();
    }
  }
}

/// `flutter-tools s3-upload` — copy a file to S3/MinIO + emit a presigned URL.
/// AWS credentials come from the standard environment.
class S3UploadCommand extends Command<void> {
  S3UploadCommand() {
    argParser
      ..addOption('file', mandatory: true)
      ..addOption('bucket', mandatory: true)
      ..addOption('key', mandatory: true)
      ..addOption('endpoint',
          defaultsTo: '', help: 'S3-compatible endpoint URL (e.g. MinIO).')
      ..addOption('expires-in', defaultsTo: '604800')
      ..addFlag('make-bucket',
          defaultsTo: true, help: 'Create the bucket if it does not exist.')
      ..addOption('aws', defaultsTo: 'aws')
      ..addFlag('verbose', defaultsTo: false)
      ..addFlag('dry-run', defaultsTo: false);
  }

  @override
  final String name = 's3-upload';
  @override
  final String description =
      'Upload a file to S3/MinIO and emit a presigned URL.';

  @override
  Future<void> run() async {
    final a = argResults!;
    final config = S3UploadConfig(
      file: a.option('file')!,
      bucket: a.option('bucket')!,
      key: a.option('key')!,
      endpoint: a.option('endpoint')!,
      expiresIn: int.parse(a.option('expires-in')!),
      aws: a.option('aws')!,
    );
    final dryRun = a.flag('dry-run');

    // head-bucket || mb — conditional, so it lives here, not in the plan.
    if (a.flag('make-bucket') && !dryRun) {
      final head = await Process.run(config.aws, [
        's3api',
        'head-bucket',
        '--bucket',
        config.bucket,
        ...endpointFlag(config)
      ]);
      if (head.exitCode != 0) {
        final mb = await Process.run(config.aws,
            ['s3', 'mb', 's3://${config.bucket}', ...endpointFlag(config)]);
        if (mb.exitCode != 0) {
          stderr.writeln(mb.stderr);
          exit(1);
        }
      }
    }

    await StepRunner(dryRun: dryRun, verbose: _verbose(a))
        .run(planS3Upload(config));

    if (dryRun) {
      _emitOutput({'s3-key': config.key, 's3-url': '<presigned-url>'});
      return;
    }
    final presign = await Process.run(config.aws, presignArgs(config));
    if (presign.exitCode != 0) {
      stderr.writeln(presign.stderr);
      exit(1);
    }
    _emitOutput(
        {'s3-key': config.key, 's3-url': (presign.stdout as String).trim()});
  }
}
