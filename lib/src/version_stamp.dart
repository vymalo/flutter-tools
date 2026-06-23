import 'step.dart';

/// Inputs for stamping a build number into `pubspec.yaml`.
///
/// The marketing version (`x.y.z`) is owned elsewhere (e.g. release-please); we
/// only (re)write the `+build` component so every store upload gets a unique,
/// increasing build number (CFBundleVersion / versionCode). The build number is
/// never committed — it's stamped at build time from the CI run number.
class VersionStampConfig {
  const VersionStampConfig({
    required this.workspace,
    this.projectDir = 'mobile',
    required this.buildNumber,
  });

  final String workspace;
  final String projectDir;

  /// The `+build` value to stamp (typically the CI run number).
  final String buildNumber;
}

/// Plan: patch `<projectDir>/pubspec.yaml` `version:` to `x.y.z+<buildNumber>`.
List<Step> planVersionStamp(VersionStampConfig c) {
  final pubspec =
      resolveIn(resolveIn(c.workspace, c.projectDir), 'pubspec.yaml');
  return [
    PatchVersionStep(
      label: 'Stamp build number into pubspec.yaml (+${c.buildNumber})',
      path: pubspec,
      buildNumber: c.buildNumber,
    ),
  ];
}
