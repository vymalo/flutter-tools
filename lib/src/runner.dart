import 'dart:io';

import 'step.dart';

/// Executes a [Step] plan in order, streaming child output to this process's
/// stdout/stderr and throwing [StepFailure] on the first non-zero exit
/// (fail-fast, like `set -euo pipefail`).
class StepRunner {
  StepRunner({this.dryRun = false, void Function(String)? log})
      : _log = log ?? stdout.writeln;

  /// When true, print the plan instead of executing it.
  final bool dryRun;
  final void Function(String) _log;

  Future<void> run(List<Step> steps) async {
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      _log('\n[${i + 1}/${steps.length}] ${step.label}');
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
        _log(
            '  \$ ${step.executable} ${step.args.join(' ')}  (${step.workingDir})');
        final proc = await Process.start(
          step.executable,
          step.args,
          workingDirectory: step.workingDir,
          mode: ProcessStartMode.inheritStdio,
          runInShell: Platform.isWindows,
        );
        final code = await proc.exitCode;
        if (code != 0) throw StepFailure(step, code);

      case WriteFileStep():
        final f = File(step.path);
        await f.parent.create(recursive: true);
        await f.writeAsString(step.contents);

      case CopyFileStep():
        final dest = File(step.to);
        await dest.parent.create(recursive: true);
        await File(step.from).copy(step.to);

      case DeleteFileStep():
        final f = File(step.path);
        if (f.existsSync()) await f.delete();

      case PatchSdkFloorStep():
        final f = File(step.path);
        if (!f.existsSync()) {
          throw StepFailure(step, 66); // EX_NOINPUT — nothing to patch
        }
        final patched = f.readAsStringSync().replaceFirst(
              RegExp(r'''sdk:\s*['"][^'"]*['"]'''),
              "sdk: '${step.sdkFloor}'",
            );
        f.writeAsStringSync(patched);
    }
  }
}
