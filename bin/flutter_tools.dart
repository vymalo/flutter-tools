import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'package:vymalo_flutter_tools/vymalo_flutter_tools.dart';

/// Write secret material to a tightly-locked temp file with a random name.
File _writeSecretTemp(String prefix, String suffix, List<int> bytes) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  if (!Platform.isWindows) {
    Process.runSync('chmod', ['0700', dir.path]);
  }
  final f = File('${dir.path}/$suffix');
  f.writeAsBytesSync(bytes);
  if (!Platform.isWindows) {
    Process.runSync('chmod', ['0600', f.path]);
  }
  return f;
}

/// Write secret text to a tightly-locked temp file with a random name.
File _writeSecretText(String prefix, String suffix, String text) =>
    _writeSecretTemp(prefix, suffix, utf8.encode(text));

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<void>(
          'flutter-tools',
          'Reusable Flutter CI/CD steps for Vymalo projects.',
        )
        ..addCommand(CodegenCommand())
        ..addCommand(VersionStampCommand())
        ..addCommand(AndroidBuildCommand())
        ..addCommand(IosBuildCommand())
        ..addCommand(TestflightSubmitCommand())
        ..addCommand(AppStoreSubmitCommand())
        ..addCommand(PlaySubmitCommand())
        ..addCommand(S3UploadCommand())
        ..addCommand(ReleaseCutCommand())
        ..addCommand(ScreenshotsCommand());

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
      ..addOption(
        'build-number',
        mandatory: true,
        help: 'The +build value (e.g. the CI run number).',
      )
      ..addOption(
        'version',
        help:
            'Marketing x.y.z to set (overrides pubspec; e.g. a git-tag '
            'version). Omit to keep the existing pubspec version.',
      )
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
    final v = a.option('version');
    final config = VersionStampConfig(
      workspace: a.option('workspace')!,
      projectDir: a.option('project-dir')!,
      buildNumber: a.option('build-number')!,
      marketingVersion: (v != null && v.isNotEmpty) ? v : null,
    );
    await StepRunner(
      dryRun: a.flag('dry-run'),
      verbose: _verbose(a),
    ).run(planVersionStamp(config));
    _emitVersionOutputs(config);
  }

  void _emitVersionOutputs(VersionStampConfig c) {
    final pubspec = File(
      resolveIn(resolveIn(c.workspace, c.projectDir), 'pubspec.yaml'),
    );
    final marketing =
        c.marketingVersion ??
        (pubspec.existsSync()
            ? RegExp(
                r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
                multiLine: true,
              ).firstMatch(pubspec.readAsStringSync())?.group(1)
            : null);
    final version = marketing ?? '0.0.0';
    _emitOutput({
      'version': version,
      'build-number': c.buildNumber,
      'full-version': '$version+${c.buildNumber}',
    });
  }
}

/// iOS build command.
///
/// ### Security note
/// The macOS `security` CLI has no stdin alternative for password flags
/// (`-p`, `-P`, `-k`). Passwords appear briefly in the process argv and
/// are visible to other processes via `ps(1)` during execution. This is
/// a macOS platform limitation. Mitigations applied:
/// - Passwords are redacted from all CLI tool logs (redactable RunStep).
/// - The runtime-generated keychain password is registered with
///   `::add-mask::` for GitHub Actions log masking.
/// - An ephemeral keychain is used and deleted in a `finally` block.
/// - Recommendation: use ephemeral runners or single-tenant self-hosted
///   runners for iOS builds.
class IosBuildCommand extends Command<void> {
  IosBuildCommand() {
    argParser
      ..addOption('workspace', defaultsTo: Directory.current.path)
      ..addOption('project-dir', defaultsTo: 'mobile')
      ..addOption(
        'app-id',
        defaultsTo: 'com.vymalo.vymalo',
        help: 'Bundle identifier.',
      )
      ..addMultiOption(
        'dart-define',
        help: 'KEY=VALUE, repeatable → --dart-define=KEY=VALUE.',
      )
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

    var certPath = '';
    var profilePath = '';
    final keychainPath = dryRun
        ? '<keychain>'
        : (() {
            final kcDir = Directory.systemTemp.createTempSync('vymalo-kc');
            if (!Platform.isWindows) {
              Process.runSync('chmod', ['0700', kcDir.path]);
            }
            return '${kcDir.path}/ci.keychain-db';
          })();

    final certB64 = (env['IOS_CERTIFICATE_BASE64'] ?? '').trim();
    final profileB64 = (env['IOS_APPSTORE_PROVISION_PROFILE_BASE64'] ?? '')
        .trim();

    if (!dryRun) {
      if (certB64.isEmpty || profileB64.isEmpty) {
        throw UsageException(
          'iOS build requires IOS_CERTIFICATE_BASE64 and '
          'IOS_APPSTORE_PROVISION_PROFILE_BASE64 to be set.',
          usage,
        );
      }
      if ((env['APPLE_TEAM_ID'] ?? '').trim().isEmpty) {
        throw UsageException(
          'iOS build requires APPLE_TEAM_ID to be set.',
          usage,
        );
      }
      final certFile = _writeSecretTemp(
        'vymalo-cert',
        'cert.p12',
        base64.decode(certB64.replaceAll(RegExp(r'\s'), '')),
      );
      certPath = certFile.path;
      final profileFile = _writeSecretTemp(
        'vymalo-prof',
        'profile.mobileprovision',
        base64.decode(profileB64.replaceAll(RegExp(r'\s'), '')),
      );
      profilePath = profileFile.path;
    }

    final rand = Random.secure();
    final keychainPassword = List.generate(
      24,
      (_) => rand.nextInt(16).toRadixString(16),
    ).join();

    // Mask the runtime-generated password in GitHub Actions logs.
    if (Platform.environment['GITHUB_ACTIONS'] == 'true') {
      stdout.writeln('::add-mask::$keychainPassword');
    }

    final config = IosBuildConfig(
      workspace: a.option('workspace')!,
      projectDir: a.option('project-dir')!,
      appId: a.option('app-id')!,
      teamId: (env['APPLE_TEAM_ID'] ?? '').trim(),
      profileName: (env['IOS_APPSTORE_PROFILE_NAME'] ?? 'Vymalo App Store')
          .trim(),
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
      await StepRunner(
        dryRun: dryRun,
        verbose: _verbose(a),
      ).run(planIosBuild(config));
    } finally {
      if (!dryRun) {
        final del = await Process.run('security', [
          'delete-keychain',
          keychainPath,
        ]);
        if (del.exitCode != 0) {
          stderr.writeln(
            'Warning: failed to delete keychain '
            '$keychainPath (exit ${del.exitCode}): '
            '${(del.stderr as String).trim()}',
          );
        }
        final kcDir = File(keychainPath).parent;
        if (kcDir.existsSync()) kcDir.deleteSync(recursive: true);
        for (final p in [certPath, profilePath]) {
          final parent = File(p).parent;
          if (parent.existsSync()) parent.deleteSync(recursive: true);
        }
      }
    }

    _emitIosBuildOutputs(config);
  }

  void _emitIosBuildOutputs(IosBuildConfig c) {
    final ipaDir = Directory(
      resolveIn(resolveIn(c.workspace, c.projectDir), 'build/ios/ipa'),
    );
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
      ..addOption(
        'workspace',
        help: 'Repo root the other paths resolve against.',
        defaultsTo: Directory.current.path,
      )
      ..addOption('project-dir', defaultsTo: 'mobile', help: 'Flutter app dir.')
      ..addOption(
        'api-dir',
        defaultsTo: 'mobile/api',
        help: 'Generated OpenAPI client dir.',
      )
      ..addOption(
        'codegen-tool-dir',
        defaultsTo: 'mobile/tool/openapi_codegen',
        help: 'Dir whose build_runner drives the OpenAPI Generator CLI.',
      )
      ..addOption(
        'api-pubspec-template',
        defaultsTo: '',
        help:
            'Tracked pubspec template copied to <api-dir>/pubspec.yaml. '
            'When set, takes precedence over --sdk-floor.',
      )
      ..addOption(
        'sdk-floor',
        defaultsTo: '>=3.12.0 <4.0.0',
        help: 'SDK constraint forced into the generated API pubspec.',
      )
      ..addFlag(
        'clean',
        defaultsTo: true,
        help: 'Drop pubspec.lock + build_runner clean before the API build.',
      )
      ..addFlag(
        'upgrade-dart-style',
        defaultsTo: false,
        help: 'dart pub upgrade dart_style before the API build.',
      )
      ..addOption('dart', defaultsTo: 'dart')
      ..addOption('flutter', defaultsTo: 'flutter')
      ..addFlag(
        'verbose',
        defaultsTo: false,
        help: 'Stream command output live.',
      )
      ..addFlag(
        'dry-run',
        defaultsTo: false,
        help: 'Print the plan without executing it.',
      );
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
    await StepRunner(
      dryRun: a.flag('dry-run'),
      verbose: _verbose(a),
    ).run(planCodegen(config));
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
      ..addOption(
        'artifacts',
        defaultsTo: 'both',
        allowed: ['apk', 'aab', 'both'],
      )
      ..addMultiOption(
        'dart-define',
        help: 'KEY=VALUE, repeatable → --dart-define=KEY=VALUE.',
      )
      ..addOption('flutter', defaultsTo: 'flutter')
      ..addFlag(
        'verbose',
        defaultsTo: false,
        help: 'Stream command output live.',
      )
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
      final f = _writeSecretTemp('vymalo-ks', 'signing.keystore', bytes);
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
      await StepRunner(
        dryRun: a.flag('dry-run'),
        verbose: _verbose(a),
      ).run(planAndroidBuild(config));
    } finally {
      if (keystorePath.isNotEmpty) {
        final ksDir = File(keystorePath).parent;
        if (ksDir.existsSync()) ksDir.deleteSync(recursive: true);
        // key.properties — only written when signing; clean it even on
        // build failure. Never touch a caller-owned file on unsigned builds.
        final keyPropsPath = resolveIn(
          resolveIn(config.workspace, config.projectDir),
          'android/key.properties',
        );
        final keyProps = File(keyPropsPath);
        if (keyProps.existsSync()) keyProps.deleteSync();
      }
    }
    _emitOutputs(config);
  }

  void _emitOutputs(AndroidBuildConfig c) {
    final appDir = resolveIn(c.workspace, c.projectDir);
    final lines = <String>['signed=${c.signed}'];
    if (c.artifacts.contains(AndroidArtifact.apk)) {
      lines.add(
        'apk-path='
        '${resolveIn(appDir, androidArtifactPath(AndroidArtifact.apk, signed: c.signed))}',
      );
    }
    if (c.signed && c.artifacts.contains(AndroidArtifact.aab)) {
      lines.add(
        'aab-path='
        '${resolveIn(appDir, androidArtifactPath(AndroidArtifact.aab, signed: c.signed))}',
      );
    }
    _emitOutput({
      for (final l in lines)
        l.split('=').first: l.split('=').sublist(1).join('='),
    });
  }
}

/// Write an App Store Connect API key JSON file (`{key_id, issuer_id, key}`)
/// from the environment, for fastlane's `api_key_path:`. Returns its path.
/// APP_STORE_CONNECT_KEY_ID / _ISSUER_ID / _API_KEY_BASE64 (base64 of the .p8).
String _writeAscApiKeyJson() {
  final env = Platform.environment;
  final p8 = utf8.decode(
    base64.decode(
      (env['APP_STORE_CONNECT_API_KEY_BASE64'] ?? '').replaceAll(
        RegExp(r'\s'),
        '',
      ),
    ),
  );
  final f = _writeSecretText(
    'asc-key',
    'key.json',
    jsonEncode({
      'key_id': (env['APP_STORE_CONNECT_KEY_ID'] ?? '').trim(),
      'issuer_id': (env['APP_STORE_CONNECT_ISSUER_ID'] ?? '').trim(),
      'key': p8,
      'in_house': false,
    }),
  );
  return f.path;
}

/// Find the first built `.ipa` under `<workspace>/<projectDir>/build/ios/ipa`.
String _findIpa(String workspace, String projectDir) {
  final dir = Directory(
    resolveIn(resolveIn(workspace, projectDir), 'build/ios/ipa'),
  );
  if (!dir.existsSync()) return '';
  final hits = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.ipa'));
  return hits.isEmpty ? '' : hits.first.path;
}

/// Resolve the marketing version (`x.y.z`) from `<projectDir>/pubspec.yaml`.
String _pubspecVersion(String workspace, String projectDir) {
  final f = File(resolveIn(resolveIn(workspace, projectDir), 'pubspec.yaml'));
  if (!f.existsSync()) return '';
  return RegExp(
        r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
        multiLine: true,
      ).firstMatch(f.readAsStringSync())?.group(1) ??
      '';
}

/// `flutter-tools testflight-submit` — upload an IPA to TestFlight via Fastlane
/// pilot. ASC API key from the environment.
class TestflightSubmitCommand extends Command<void> {
  TestflightSubmitCommand() {
    argParser
      ..addOption('workspace', defaultsTo: Directory.current.path)
      ..addOption('project-dir', defaultsTo: 'mobile')
      ..addOption('ipa', help: 'IPA path. Default: first under build/ios/ipa.')
      ..addOption('fastlane', defaultsTo: 'fastlane')
      ..addFlag('skip-waiting', defaultsTo: true)
      ..addFlag('verbose', defaultsTo: false)
      ..addFlag('dry-run', defaultsTo: false);
  }

  @override
  final String name = 'testflight-submit';
  @override
  final String description = 'Upload an IPA to TestFlight (Fastlane pilot).';

  @override
  Future<void> run() async {
    final a = argResults!;
    final dryRun = a.flag('dry-run');
    final ws = a.option('workspace')!;
    final apiKey = dryRun ? '<asc-key.json>' : _writeAscApiKeyJson();
    final ipa =
        a.option('ipa') ??
        (dryRun
            ? '<build/ios/ipa/app.ipa>'
            : _findIpa(ws, a.option('project-dir')!));
    if (!dryRun && ipa.isEmpty) {
      throw UsageException('No IPA found under build/ios/ipa/.', usage);
    }
    final config = TestflightSubmitConfig(
      ipaPath: ipa,
      apiKeyPath: apiKey,
      skipWaitingForBuildProcessing: a.flag('skip-waiting'),
      workingDir: resolveIn(ws, a.option('project-dir')!),
      fastlane: a.option('fastlane')!,
    );
    try {
      await StepRunner(
        dryRun: dryRun,
        verbose: _verbose(a),
      ).run(planTestflightSubmit(config));
    } finally {
      if (!dryRun) {
        final akDir = File(apiKey).parent;
        if (akDir.existsSync()) akDir.deleteSync(recursive: true);
      }
    }
  }
}

/// `flutter-tools app-store-submit` — upload an IPA and/or screenshots to App
/// Store Connect via Fastlane deliver, optionally submitting for review.
class AppStoreSubmitCommand extends Command<void> {
  AppStoreSubmitCommand() {
    argParser
      ..addOption('workspace', defaultsTo: Directory.current.path)
      ..addOption('project-dir', defaultsTo: 'mobile')
      ..addOption('ipa', help: 'IPA path. Default: first under build/ios/ipa.')
      ..addOption('app-version', help: 'Marketing x.y.z. Default: pubspec.')
      ..addOption(
        'screenshots-path',
        help: 'Screenshots dir (screenshots mode).',
      )
      ..addOption('fastlane', defaultsTo: 'fastlane')
      ..addFlag('submit-for-review', defaultsTo: false)
      ..addFlag('skip-binary-upload', defaultsTo: false)
      ..addFlag('skip-screenshots', defaultsTo: true)
      ..addFlag('overwrite-screenshots', defaultsTo: false)
      ..addFlag('verbose', defaultsTo: false)
      ..addFlag('dry-run', defaultsTo: false);
  }

  @override
  final String name = 'app-store-submit';
  @override
  final String description =
      'Upload IPA/screenshots to App Store Connect (Fastlane deliver).';

  @override
  Future<void> run() async {
    final a = argResults!;
    final dryRun = a.flag('dry-run');
    final ws = a.option('workspace')!;
    final projectDir = a.option('project-dir')!;
    final skipBinary = a.flag('skip-binary-upload');

    final apiKey = dryRun ? '<asc-key.json>' : _writeAscApiKeyJson();
    final version =
        a.option('app-version') ??
        (dryRun ? '<x.y.z>' : _pubspecVersion(ws, projectDir));
    if (!dryRun && version.isEmpty) {
      throw UsageException(
        'Could not resolve app-version (pass --app-version or set pubspec version:).',
        usage,
      );
    }
    final ipa = skipBinary
        ? null
        : (a.option('ipa') ??
              (dryRun ? '<build/ios/ipa/app.ipa>' : _findIpa(ws, projectDir)));
    if (!dryRun && !skipBinary && (ipa == null || ipa.isEmpty)) {
      throw UsageException('No IPA found under build/ios/ipa/.', usage);
    }

    final config = AppStoreSubmitConfig(
      apiKeyPath: apiKey,
      appVersion: version,
      ipaPath: ipa,
      screenshotsPath: a.option('screenshots-path'),
      submitForReview: a.flag('submit-for-review'),
      skipBinaryUpload: skipBinary,
      skipScreenshots: a.flag('skip-screenshots'),
      overwriteScreenshots: a.flag('overwrite-screenshots'),
      workingDir: resolveIn(ws, projectDir),
      fastlane: a.option('fastlane')!,
    );
    try {
      await StepRunner(
        dryRun: dryRun,
        verbose: _verbose(a),
      ).run(planAppStoreSubmit(config));
    } finally {
      if (!dryRun) {
        final akDir = File(apiKey).parent;
        if (akDir.existsSync()) akDir.deleteSync(recursive: true);
      }
    }
  }
}

/// Append `name=value` pairs to $GITHUB_OUTPUT (or print them locally).
void _emitOutput(Map<String, String> outputs) {
  final body = outputs.entries
      .map((e) => '${e.key}=${e.value.replaceAll('\n', '\\n')}')
      .join('\n');
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
      ..addOption(
        'release-status',
        defaultsTo: 'completed',
        allowed: ['completed', 'draft', 'halted', 'inProgress'],
      )
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
        'Set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64 (or _JSON).',
        usage,
      );
    }
    final json = b64.isNotEmpty
        ? utf8.decode(base64.decode(b64.replaceAll(RegExp(r'\s'), '')))
        : plain;
    final keyFile = _writeSecretText('play-key', 'service-account.json', json);

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
      await StepRunner(
        dryRun: a.flag('dry-run'),
        verbose: _verbose(a),
      ).run(planPlaySubmit(config));
    } finally {
      final ksDir = keyFile.parent;
      if (ksDir.existsSync()) ksDir.deleteSync(recursive: true);
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
      ..addOption(
        'endpoint',
        defaultsTo: '',
        help: 'S3-compatible endpoint URL (e.g. MinIO).',
      )
      ..addOption('expires-in', defaultsTo: '604800')
      ..addFlag(
        'make-bucket',
        defaultsTo: true,
        help: 'Create the bucket if it does not exist.',
      )
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
        ...endpointFlag(config),
      ]);
      if (head.exitCode != 0) {
        final mb = await Process.run(config.aws, [
          's3',
          'mb',
          's3://${config.bucket}',
          ...endpointFlag(config),
        ]);
        if (mb.exitCode != 0) {
          stderr.writeln(mb.stderr);
          exit(1);
        }
      }
    }

    await StepRunner(
      dryRun: dryRun,
      verbose: _verbose(a),
    ).run(planS3Upload(config));

    if (dryRun) {
      _emitOutput({'s3-key': config.key, 's3-url': '<presigned-url>'});
      return;
    }
    final presign = await Process.run(config.aws, presignArgs(config));
    if (presign.exitCode != 0) {
      stderr.writeln(presign.stderr);
      exit(1);
    }
    _emitOutput({
      's3-key': config.key,
      's3-url': (presign.stdout as String).trim(),
    });
  }
}

/// `flutter-tools release-cut` — compute the next release version + tag from
/// conventional commits since the last `<tag-prefix>*` tag (or an explicit bump).
/// Read-only (git reads + pubspec); the action does the tag + GitHub Release.
class ReleaseCutCommand extends Command<void> {
  ReleaseCutCommand() {
    argParser
      ..addOption('workspace', defaultsTo: Directory.current.path)
      ..addOption('project-dir', defaultsTo: 'mobile')
      ..addOption('tag-prefix', defaultsTo: 'mobile-v')
      ..addOption(
        'bump',
        defaultsTo: 'auto',
        allowed: ['auto', 'patch', 'minor', 'major'],
        help: 'auto = infer from conventional commits.',
      )
      ..addOption(
        'ref',
        defaultsTo: 'HEAD',
        help:
            'Commitish being released — the bump scan ends here (default HEAD).',
      );
  }

  @override
  final String name = 'release-cut';
  @override
  final String description =
      'Compute the next release version + tag from '
      'conventional commits since the last tag.';

  @override
  Future<void> run() async {
    final a = argResults!;
    final ws = a.option('workspace')!;
    final projectDir = a.option('project-dir')!;
    final prefix = a.option('tag-prefix')!;
    final ref = a.option('ref')!;

    String git(List<String> args) {
      final r = Process.runSync('git', args, workingDirectory: ws);
      return r.exitCode == 0 ? (r.stdout as String) : '';
    }

    final latestTag = git(['tag', '-l', '$prefix*', '--sort=-v:refname'])
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');

    // Scan up to the commit being released (`ref`), NOT always HEAD — so a release
    // that tags a supplied SHA infers its bump from the commits actually in it.
    final logArgs = <String>['log', '--format=%s%n%b'];
    logArgs.add(latestTag.isNotEmpty ? '$latestTag..$ref' : ref);
    if (projectDir != '.') logArgs.addAll(['--', '$projectDir/']);
    final commitLog = git(logArgs);

    final pubspec = File(resolveIn(resolveIn(ws, projectDir), 'pubspec.yaml'));
    final pubspecVersion = pubspec.existsSync()
        ? (RegExp(
                r'^version:\s*(\S+)',
                multiLine: true,
              ).firstMatch(pubspec.readAsStringSync())?.group(1) ??
              '0.0.0')
        : '0.0.0';

    final result = computeRelease(
      tagPrefix: prefix,
      latestTag: latestTag.isEmpty ? null : latestTag,
      pubspecVersion: pubspecVersion,
      bumpInput: a.option('bump')!,
      commitLog: commitLog,
    );
    stdout.writeln(
      'Baseline '
      '${latestTag.isEmpty ? 'pubspec $pubspecVersion' : latestTag} + '
      '${result.bump.name} → ${result.version} (${result.tag})',
    );
    _emitOutput({
      'version': result.version,
      'tag': result.tag,
      'bump': result.bump.name,
    });
  }
}

/// `flutter-tools screenshots` — capture store screenshots across a device matrix.
///
/// Imperative orchestration (boot emulators/simulators → `flutter drive` →
/// collect → per-device rescue) — a faithful port of the proven Fastlane lanes,
/// preserving the hard-won gotchas: clean COLD BOOT (`-no-snapshot-load
/// -wipe-data`) so a stale phone-AVD snapshot can't crash the app mid-drive; one
/// drive RETRY for the transient "Service has disappeared" VM-service flake; a
/// per-device try/rescue so one bad device doesn't lose the rest; and FAIL-LOUD
/// on zero collected (a green run with no screenshots is the classic trap).
class ScreenshotsCommand extends Command<void> {
  ScreenshotsCommand() {
    argParser
      ..addOption('workspace', defaultsTo: Directory.current.path)
      ..addOption('project-dir', defaultsTo: 'mobile')
      ..addOption(
        'platform',
        defaultsTo: 'both',
        allowed: ['android', 'ios', 'both'],
      )
      ..addOption('driver', defaultsTo: 'test_driver/integration_test.dart')
      ..addOption(
        'target',
        defaultsTo: 'integration_test/screenshots_test.dart',
      )
      ..addOption('locale', defaultsTo: 'en-US')
      ..addOption('android-home', defaultsTo: '')
      ..addOption(
        'sysimg',
        defaultsTo: 'system-images;android-36;google_apis;arm64-v8a',
      )
      ..addOption(
        'android-devices',
        defaultsTo: '',
        help: 'Override: "avd:profile:class,…".',
      )
      ..addOption(
        'ios-devices',
        defaultsTo: '',
        help: 'Override: "sim|label,…".',
      )
      ..addMultiOption('dart-define', help: 'KEY=VALUE, repeatable.')
      ..addOption('flutter', defaultsTo: 'flutter');
  }

  @override
  final String name = 'screenshots';
  @override
  final String description =
      'Capture store screenshots across an emulator/simulator device matrix.';

  @override
  Future<void> run() async {
    final a = argResults!;
    final appRoot = resolveIn(a.option('workspace')!, a.option('project-dir')!);
    final platform = a.option('platform')!;
    final locale = a.option('locale')!;
    final driver = a.option('driver')!;
    final target = a.option('target')!;
    final flutter = a.option('flutter')!;
    final defines = [
      for (final d in a.multiOption('dart-define')) '--dart-define=$d',
    ];

    final wantAndroid = platform == 'android' || platform == 'both';
    final wantIos = platform == 'ios' || platform == 'both';

    var androidCount = 0;
    var iosCount = 0;
    if (wantAndroid) {
      androidCount = await _captureAndroid(
        appRoot: appRoot,
        devices: parseAndroidDevices(a.option('android-devices')!),
        androidHome: a.option('android-home')!.isNotEmpty
            ? a.option('android-home')!
            : (Platform.environment['ANDROID_HOME'] ??
                  '/opt/homebrew/share/android-commandlinetools'),
        sysimg: a.option('sysimg')!,
        driver: driver,
        target: target,
        flutter: flutter,
        defines: defines,
        locale: locale,
      );
    }
    if (wantIos) {
      iosCount = await _captureIos(
        appRoot: appRoot,
        devices: parseIosDevices(a.option('ios-devices')!),
        driver: driver,
        target: target,
        flutter: flutter,
        defines: defines,
        locale: locale,
      );
    }

    // Where the captures landed + how many, so downstream steps (zip/upload to
    // S3, deliver) can find them. Emitted BEFORE the fail-loud exit, so a partial
    // run still exposes what it got (read them with `if: always()`).
    _emitOutput({
      'android-dir': wantAndroid ? '$appRoot/fastlane/metadata/android' : '',
      'ios-dir': wantIos ? iosScreenshotsDir(appRoot, locale: locale) : '',
      'android-count': '$androidCount',
      'ios-count': '$iosCount',
      'count': '${androidCount + iosCount}',
    });

    // Fail loud: a requested platform that captured nothing is a hollow run.
    final empty = <String>[
      if (wantAndroid && androidCount == 0) 'android',
      if (wantIos && iosCount == 0) 'ios',
    ];
    if (empty.isNotEmpty) {
      stderr.writeln('\n✗ no screenshots captured for: ${empty.join(', ')}');
      exit(65); // EX_DATAERR
    }
  }
}

/// Run a process live (inherited stdio), optionally with a hard timeout (kill on
/// expiry → exit 124). Returns the exit code.
Future<int> _runLive(
  String exe,
  List<String> args, {
  String? cwd,
  Duration? timeout,
}) async {
  final p = await Process.start(
    exe,
    args,
    workingDirectory: cwd,
    mode: ProcessStartMode.inheritStdio,
  );
  if (timeout == null) return p.exitCode;
  try {
    return await p.exitCode.timeout(timeout);
  } on TimeoutException {
    p.kill(ProcessSignal.sigkill);
    return 124;
  }
}

/// `flutter drive` with ONE retry — the integration_test VM service occasionally
/// drops mid-run ("ext.flutter.driver: (112) Service has disappeared").
Future<void> _driveScreenshots(
  String flutter,
  String driver,
  String target,
  String device,
  List<String> defines, {
  required String cwd,
}) async {
  for (var attempt = 1; ; attempt++) {
    // Run from the app dir — driver/target are relative paths, and the driver
    // shim writes PNGs to <cwd>/screenshots/ (which the collector reads).
    final rc = await _runLive(flutter, [
      'drive',
      '--driver=$driver',
      '--target=$target',
      '-d',
      device,
      ...defines,
    ], cwd: cwd);
    if (rc == 0) return;
    if (attempt >= 2) throw StateError('flutter drive failed (exit $rc)');
    stdout.writeln('⚠ flutter drive failed (exit $rc); retrying once…');
  }
}

/// Move every PNG the driver wrote to `<appRoot>/screenshots/` into [targetDir],
/// renaming via [name], then clear the staging dir. Returns the count moved.
int _collectScreenshots(
  String appRoot,
  String targetDir, {
  String Function(String basename)? name,
}) {
  final staging = Directory('$appRoot/screenshots');
  if (!staging.existsSync()) return 0;
  Directory(targetDir).createSync(recursive: true);
  var n = 0;
  for (final f in staging.listSync().whereType<File>()) {
    if (!f.path.endsWith('.png')) continue;
    final base = f.uri.pathSegments.last;
    f.copySync('$targetDir/${name == null ? base : name(base)}');
    n++;
  }
  staging.deleteSync(recursive: true);
  return n;
}

int _countPngs(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return 0;
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.png'))
      .length;
}

Future<int> _captureAndroid({
  required String appRoot,
  required List<AndroidScreenshotDevice> devices,
  required String androidHome,
  required String sysimg,
  required String driver,
  required String target,
  required String flutter,
  required List<String> defines,
  required String locale,
}) async {
  // Clear the previous run's collected images + staging so the fail-loud guard
  // can't pass on stale files.
  for (final d in devices) {
    final dir = Directory(
      androidImagesDir(appRoot, d.imagesClass, locale: locale),
    );
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
  final staging = Directory('$appRoot/screenshots');
  if (staging.existsSync()) staging.deleteSync(recursive: true);

  final emulator = '$androidHome/emulator/emulator';
  final adb = '$androidHome/platform-tools/adb';
  final avdmanager = '$androidHome/cmdline-tools/latest/bin/avdmanager';

  final existing = Process.runSync(emulator, [
    '-list-avds',
  ]).stdout.toString().split('\n').map((s) => s.trim()).toSet();

  for (final d in devices) {
    if (!existing.contains(d.avd)) {
      stdout.writeln("AVD '${d.avd}' not found — creating it (${d.profile})…");
      // Invoke avdmanager directly (no `sh -c` interpolation of the device
      // matrix → no shell-injection surface); answer its prompt via stdin.
      final create = await Process.start(avdmanager, [
        'create',
        'avd',
        '-n',
        d.avd,
        '-k',
        sysimg,
        '-d',
        d.profile,
        '--force',
      ]);
      create.stdin.writeln('no');
      await create.stdin.close();
      await Future.wait([
        create.stdout.drain<void>(),
        create.stderr.drain<void>(),
      ]);
      if (await create.exitCode != 0) {
        stdout.writeln(
          "Skipping ${d.imagesClass}: could not create AVD '${d.avd}'.",
        );
        continue;
      }
    }

    stdout.writeln('Starting AVD ${d.avd} → ${d.imagesClass}…');
    // One emulator at a time (killed below) → console serial is always
    // emulator-5554. Clean cold boot: -no-snapshot-load -wipe-data (avoids the
    // stale-snapshot phone crash); -no-snapshot-save so it never goes stale.
    // Detached: it runs independently and is killed via `adb emu kill` below. Do
    // NOT touch its .exitCode — a detached process throws "Bad state: Process is
    // detached" the instant you await it.
    await Process.start(emulator, [
      '-avd',
      d.avd,
      '-no-window',
      '-no-audio',
      '-no-snapshot-load',
      '-no-snapshot-save',
      '-wipe-data',
      '-no-metrics',
    ], mode: ProcessStartMode.detached);
    try {
      // Target the serial explicitly (one emulator at a time → emulator-5554),
      // so a stray device on the host can't confuse wait-for-device / getprop.
      final wfd = await _runLive(adb, [
        '-s',
        'emulator-5554',
        'wait-for-device',
      ], timeout: const Duration(seconds: 180));
      if (wfd != 0) throw StateError('adb wait-for-device timed out');
      final deadline = DateTime.now().add(const Duration(seconds: 240));
      while (true) {
        final booted = Process.runSync(adb, [
          '-s',
          'emulator-5554',
          'shell',
          'getprop',
          'sys.boot_completed',
        ]).stdout.toString().trim();
        if (booted == '1') break;
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('emulator never reported boot_completed');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      await _driveScreenshots(
        flutter,
        driver,
        target,
        'emulator-5554',
        defines,
        cwd: appRoot,
      );
      final n = _collectScreenshots(
        appRoot,
        androidImagesDir(appRoot, d.imagesClass, locale: locale),
      );
      stdout.writeln('  ✓ collected $n into ${d.imagesClass}');
    } catch (e) {
      // One bad device must not abort the rest — the final guard fails the run
      // if NOTHING was collected.
      stdout.writeln('Skipping ${d.imagesClass}: $e');
    } finally {
      try {
        await _runLive(adb, ['-s', 'emulator-5554', 'emu', 'kill']);
      } catch (_) {}
      // Release the port before the next boot.
      await Future<void>.delayed(const Duration(seconds: 4));
    }
  }

  final shots = _countPngs('$appRoot/fastlane/metadata/android');
  stdout.writeln('Collected $shots Android screenshot(s).');
  return shots;
}

Future<int> _captureIos({
  required String appRoot,
  required List<IosScreenshotDevice> devices,
  required String driver,
  required String target,
  required String flutter,
  required List<String> defines,
  required String locale,
}) async {
  // Clear last run's collected images + delete leftover "vymalo-*" sims.
  final dir = Directory(iosScreenshotsDir(appRoot, locale: locale));
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  final list = Process.runSync('xcrun', [
    'simctl',
    'list',
    'devices',
  ]).stdout.toString();
  for (final m in RegExp(
    r'^\s+vymalo-\S+ \(([-0-9A-Fa-f]+)\)',
    multiLine: true,
  ).allMatches(list)) {
    Process.runSync('xcrun', ['simctl', 'delete', m.group(1)!]);
  }

  for (final d in devices) {
    var udid = '';
    try {
      stdout.writeln('Creating + booting ${d.sim}…');
      // No runtime arg → newest installed iOS. Boot BY UDID (booting by name
      // fails when the named sim doesn't exist / is ambiguous).
      udid = Process.runSync('xcrun', [
        'simctl',
        'create',
        'vymalo-${d.label}',
        d.sim,
      ]).stdout.toString().trim();
      if (udid.isEmpty) {
        throw StateError("device type '${d.sim}' unavailable (no UDID)");
      }
      if (await _runLive('xcrun', ['simctl', 'boot', udid]) != 0) {
        throw StateError('simctl boot failed');
      }
      await _runLive('xcrun', ['simctl', 'bootstatus', udid, '-b']);
      await _driveScreenshots(
        flutter,
        driver,
        target,
        udid,
        defines,
        cwd: appRoot,
      );
      final n = _collectScreenshots(
        appRoot,
        iosScreenshotsDir(appRoot, locale: locale),
        name: (base) => iosDestName(d.label, base),
      );
      stdout.writeln('  ✓ collected $n for ${d.label}');
    } catch (e) {
      stdout.writeln("Skipping iOS device '${d.sim}': $e");
    } finally {
      if (udid.isNotEmpty) {
        try {
          Process.runSync('xcrun', ['simctl', 'shutdown', udid]);
          Process.runSync('xcrun', ['simctl', 'delete', udid]);
        } catch (_) {}
      }
    }
  }

  final shots = _countPngs(iosScreenshotsDir(appRoot, locale: locale));
  stdout.writeln('Captured $shots iOS screenshot(s).');
  return shots;
}
