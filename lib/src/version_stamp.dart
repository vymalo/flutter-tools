import 'step.dart';

/// Inputs for stamping a build number into `pubspec.yaml`.
///
/// The `+build` component (CFBundleVersion / versionCode) is always (re)stamped
/// so every store upload gets a unique, increasing build number — never
/// committed, stamped at build time from the CI run number. The marketing
/// `x.y.z` is kept from the file unless [marketingVersion] is supplied (used when
/// a git tag, not a committed pubspec bump, owns the version).
class VersionStampConfig {
  const VersionStampConfig({
    required this.workspace,
    this.projectDir = 'mobile',
    required this.buildNumber,
    this.marketingVersion,
  });

  final String workspace;
  final String projectDir;

  /// The `+build` value to stamp (typically the CI run number).
  final String buildNumber;

  /// Override for the marketing `x.y.z`; null keeps the file's existing version.
  final String? marketingVersion;
}

/// Plan: patch `<projectDir>/pubspec.yaml` `version:` to `x.y.z+<buildNumber>`.
List<Step> planVersionStamp(VersionStampConfig c) {
  final pubspec = resolveIn(
    resolveIn(c.workspace, c.projectDir),
    'pubspec.yaml',
  );
  final target = c.marketingVersion ?? '<keep>';
  return [
    PatchVersionStep(
      label: 'Stamp version into pubspec.yaml ($target+${c.buildNumber})',
      path: pubspec,
      buildNumber: c.buildNumber,
      marketingVersion: c.marketingVersion,
    ),
  ];
}
