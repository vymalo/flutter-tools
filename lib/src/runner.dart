import 'dart:io';

import 'step.dart';

/// Executes a [Step] plan in order and throws [StepFailure] on the first
/// non-zero exit (fail-fast, like `set -euo pipefail`).
///
/// Logs are **quiet by default** (chronic-style): a command's output is
/// captured and only replayed if it FAILS — so a green run shows just a tick per
/// step. Set [verbose] (or run with GitHub step-debug, `RUNNER_DEBUG=1`) to
/// stream everything live.
class StepRunner {
  StepRunner({this.dryRun = false, bool? verbose, void Function(String)? log})
      : verbose = verbose ?? Platform.environment['RUNNER_DEBUG'] == '1',
        _log = log ?? stdout.writeln;

  /// Print the plan instead of executing it.
  final bool dryRun;

  /// Stream child output live instead of hiding it until a failure.
  final bool verbose;

  final void Function(String) _log;

  Future<void> run(List<Step> steps) async {
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      _log('[${i + 1}/${steps.length}] ${step.label}');
      if (dryRun) {
        _log('  · $step');
        continue;
      }
      await _execute(step);
    }
  }

  Future<void> _execute(Step step) async {
    switch (step) {
      case RunStep():
        await _run(step);
      case WriteFileStep():
        final f = File(step.path);
        await f.parent.create(recursive: true);
        await f.writeAsString(step.contents);
        _log('  ✓ wrote ${step.path}');
      case CopyFileStep():
        final dest = File(step.to);
        await dest.parent.create(recursive: true);
        await File(step.from).copy(step.to);
        _log('  ✓ copied -> ${step.to}');
      case DeleteFileStep():
        final f = File(step.path);
        if (f.existsSync()) await f.delete();
      case PatchSdkFloorStep():
        final f = File(step.path);
        if (!f.existsSync()) throw StepFailure(step, 66); // EX_NOINPUT
        f.writeAsStringSync(
          f.readAsStringSync().replaceFirst(
                RegExp(r'''sdk:\s*['"][^'"]*['"]'''),
                "sdk: '${step.sdkFloor}'",
              ),
        );
        _log('  ✓ patched ${step.path}');
      case PatchVersionStep():
        final f = File(step.path);
        if (!f.existsSync()) throw StepFailure(step, 66); // EX_NOINPUT
        final content = f.readAsStringSync();
        final m =
            RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true)
                .firstMatch(content);
        if (m == null) throw StepFailure(step, 65); // EX_DATAERR
        f.writeAsStringSync(content.replaceFirst(
          RegExp(r'^version:.*$', multiLine: true),
          'version: ${m.group(1)}+${step.buildNumber}',
        ));
        _log('  ✓ stamped ${step.path} -> ${m.group(1)}+${step.buildNumber}');
    }
  }

  Future<void> _run(RunStep step) async {
    final sw = Stopwatch()..start();
    final cmd = '${step.executable} ${step.args.join(' ')}';

    if (verbose) {
      _log('  \$ $cmd  (${step.workingDir})');
      final proc = await Process.start(
        step.executable,
        step.args,
        workingDirectory: step.workingDir,
        mode: ProcessStartMode.inheritStdio,
        runInShell: Platform.isWindows,
      );
      final code = await proc.exitCode;
      if (code != 0) throw StepFailure(step, code);
      return;
    }

    // Quiet: buffer stdout+stderr, replay only if the command fails.
    final proc = await Process.start(
      step.executable,
      step.args,
      workingDirectory: step.workingDir,
      runInShell: Platform.isWindows,
    );
    final out = <int>[];
    final err = <int>[];
    final pumping = Future.wait([
      proc.stdout.forEach(out.addAll),
      proc.stderr.forEach(err.addAll),
    ]);
    final code = await proc.exitCode;
    await pumping;

    if (code != 0) {
      _log('  ✗ $cmd  (exit $code)');
      stdout.add(out);
      stderr.add(err);
      throw StepFailure(step, code);
    }
    _log('  ✓ ${sw.elapsed.inSeconds}s  ·  $cmd');
  }
}
