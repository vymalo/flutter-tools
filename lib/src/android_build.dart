import 'step.dart';

/// Which Android artifacts to produce.
enum AndroidArtifact { apk, aab }

/// Inputs for an Android release build. Signing is optional: with no keystore
/// the APK falls back to an unsigned debug build (and the AAB is skipped, since
/// Play requires a signed bundle) — mirroring the original Fastlane lanes.
class AndroidBuildConfig {
  const AndroidBuildConfig({
    required this.workspace,
    this.projectDir = 'mobile',
    this.signed = false,
    this.keystorePath = '',
    this.keystorePassword = '',
    this.keyAlias = '',
    this.keyPassword = '',
    this.buildNumber,
    this.artifacts = const {AndroidArtifact.apk, AndroidArtifact.aab},
    this.dartDefines = const [],
    this.flutter = 'flutter',
  });

  final String workspace;
  final String projectDir;

  /// True when a keystore is available (release signing); false → debug APK.
  final bool signed;

  /// Path to the materialised keystore (the CLI decodes the base64 secret to a
  /// temp file before planning, so the secret never enters a [Step]).
  final String keystorePath;
  final String keystorePassword;
  final String keyAlias;
  final String keyPassword;

  /// `--build-number` (Android versionCode). Null → Flutter's pubspec default.
  final String? buildNumber;

  final Set<AndroidArtifact> artifacts;

  /// `KEY=VALUE` entries, each emitted as `--dart-define=KEY=VALUE`.
  final List<String> dartDefines;

  final String flutter;
}

/// The standard Flutter output path for each artifact, relative to the app dir.
String androidArtifactPath(AndroidArtifact a, {required bool signed}) =>
    switch (a) {
      AndroidArtifact.apk =>
        signed
            ? 'build/app/outputs/flutter-apk/app-release.apk'
            : 'build/app/outputs/flutter-apk/app-debug.apk',
      AndroidArtifact.aab => 'build/app/outputs/bundle/release/app-release.aab',
    };

/// Build the plan: write signing config → `flutter build …` per artifact →
/// remove the signing config. The AAB is only built when signed.
List<Step> planAndroidBuild(AndroidBuildConfig c) {
  final appDir = resolveIn(c.workspace, c.projectDir);
  final keyProps = resolveIn(appDir, 'android/key.properties');
  final defines = [for (final d in c.dartDefines) '--dart-define=$d'];
  final buildNumber = c.buildNumber == null
      ? <String>[]
      : ['--build-number=${c.buildNumber}'];

  List<String> buildArgs(String sub, String mode) => [
    sub,
    mode,
    ...buildNumber,
    ...defines,
  ];

  return [
    if (c.signed)
      WriteFileStep(
        label: 'Write android/key.properties',
        path: keyProps,
        contents:
            'storeFile=${c.keystorePath}\n'
            'storePassword=${c.keystorePassword}\n'
            'keyAlias=${c.keyAlias}\n'
            'keyPassword=${c.keyPassword}\n',
      ),

    if (c.artifacts.contains(AndroidArtifact.apk))
      RunStep(
        label: 'flutter build apk (${c.signed ? "release" : "debug"})',
        executable: c.flutter,
        args: [
          'build',
          ...buildArgs('apk', c.signed ? '--release' : '--debug'),
        ],
        workingDir: appDir,
      ),

    // A release AAB needs signing; skip it on an unsigned build.
    if (c.signed && c.artifacts.contains(AndroidArtifact.aab))
      RunStep(
        label: 'flutter build appbundle (release)',
        executable: c.flutter,
        args: ['build', ...buildArgs('appbundle', '--release')],
        workingDir: appDir,
      ),

    if (c.signed)
      DeleteFileStep(label: 'Remove android/key.properties', path: keyProps),
  ];
}
