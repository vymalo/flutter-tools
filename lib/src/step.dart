import 'dart:io';

/// One unit of work in a tool plan.
///
/// A plan is just a `List<Step>` — a pure, inspectable value. That separation
/// (plan vs. execute) is what makes the orchestration unit-testable: a test
/// asserts the plan a given config produces, without spawning any process or
/// touching the filesystem.
sealed class Step {
  const Step({required this.label});

  /// Human-readable description shown in logs / `--dry-run`.
  final String label;
}

/// Run an external command (`dart`, `flutter`, `aws`, …) in [workingDir].
class RunStep extends Step {
  const RunStep({
    required super.label,
    required this.executable,
    required this.args,
    required this.workingDir,
    this.allowFailure = false,
  });

  final String executable;
  final List<String> args;
  final String workingDir;

  /// When true, a non-zero exit logs a warning instead of throwing
  /// [StepFailure] — for best-effort steps like importing Apple WWDR
  /// intermediates (some versions 404 or are already present).
  final bool allowFailure;

  @override
  String toString() =>
      'RunStep($label: `$executable ${args.join(' ')}` in $workingDir)';
}

/// Write [contents] to [path], creating parent dirs. Used for the generated
/// API package's `pubspec.yaml` (gitignored on persistent runners, so it must
/// be materialised before `pub get`).
class WriteFileStep extends Step {
  const WriteFileStep({
    required super.label,
    required this.path,
    required this.contents,
  });

  final String path;
  final String contents;

  @override
  String toString() => 'WriteFileStep($label: $path)';
}

/// Copy [from] → [to]. Used to materialise a tracked pubspec template into the
/// gitignored generated-API directory.
class CopyFileStep extends Step {
  const CopyFileStep({
    required super.label,
    required this.from,
    required this.to,
  });

  final String from;
  final String to;

  @override
  String toString() => 'CopyFileStep($label: $from -> $to)';
}

/// Delete [path] if present (e.g. a stale `pubspec.lock` for a fresh resolve).
/// Never fails when the file is absent.
class DeleteFileStep extends Step {
  const DeleteFileStep({required super.label, required this.path});

  final String path;

  @override
  String toString() => 'DeleteFileStep($label: $path)';
}

/// Replace the SDK constraint line in an existing `pubspec.yaml` with
/// `sdk: "<floor>"`. Used when no full template is supplied — just nudges the
/// floor the upstream generator pins too low.
class PatchSdkFloorStep extends Step {
  const PatchSdkFloorStep({
    required super.label,
    required this.path,
    required this.sdkFloor,
  });

  final String path;
  final String sdkFloor;

  @override
  String toString() => 'PatchSdkFloorStep($label: $path -> $sdkFloor)';
}

/// Rewrite the `version:` line of a `pubspec.yaml` to `x.y.z+<buildNumber>` —
/// keeping the marketing `x.y.z` (release-please owns it) and only (re)stamping
/// the `+build` component (CFBundleVersion / versionCode), which the stores
/// require to increase on every upload.
class PatchVersionStep extends Step {
  const PatchVersionStep({
    required super.label,
    required this.path,
    required this.buildNumber,
  });

  final String path;
  final String buildNumber;

  @override
  String toString() => 'PatchVersionStep($label: $path -> +$buildNumber)';
}

/// Thrown when a [RunStep] exits non-zero — fail-fast, like `set -e`.
class StepFailure implements Exception {
  StepFailure(this.step, this.exitCode);

  final Step step;
  final int exitCode;

  @override
  String toString() => 'Step failed (exit $exitCode): ${step.label}';
}

/// Resolve a possibly-relative [path] against [root] into an absolute path.
String resolveIn(String root, String path) {
  if (path.isEmpty) return root;
  final p = path;
  return File(p).isAbsolute ? p : _join(root, p);
}

String _join(String a, String b) {
  final left = a.endsWith('/') ? a.substring(0, a.length - 1) : a;
  final right = b.startsWith('/') ? b.substring(1) : b;
  return '$left/$right';
}
