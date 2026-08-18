import 'step.dart';

/// Everything the codegen orchestration needs. All paths are RELATIVE to
/// [workspace] (the repo root); the planner resolves them to absolute paths so
/// the steps run correctly no matter the process CWD.
class CodegenConfig {
  const CodegenConfig({
    required this.workspace,
    this.projectDir = 'mobile',
    this.apiDir = 'mobile/api',
    this.codegenToolDir = 'mobile/tool/openapi_codegen',
    this.generateOpenapi = true,
    this.apiPubspecTemplate = '',
    this.sdkFloor = '>=3.12.0 <4.0.0',
    this.clean = true,
    this.upgradeDartStyle = false,
    this.buildRunnerArgs = const ['--delete-conflicting-outputs'],
    this.dart = 'dart',
    this.flutter = 'flutter',
  });

  /// Repo root the relative dirs below are resolved against.
  final String workspace;

  /// Flutter app dir (the `flutter pub get` + riverpod/drift/go_router codegen).
  final String projectDir;

  /// Generated OpenAPI client package dir (its own `build_runner` for *.g.dart).
  final String apiDir;

  /// Sub-project that drives the OpenAPI Generator CLI (writes [apiDir]/*.dart).
  final String codegenToolDir;

  /// Whether to run the OpenAPI-client stage (steps 1-3 below) at all.
  ///
  /// A consumer with no generated OpenAPI client (e.g. one that deleted
  /// [codegenToolDir]/[apiDir] entirely) has no use for this stage, and the
  /// underlying commands hard-fail with a confusing "No such file or
  /// directory" if pointed at a directory that doesn't exist. The `codegen`
  /// action's own CLI layer resolves this from its `generate-openapi`
  /// input — `auto` (the default) checks whether [codegenToolDir] exists on
  /// disk and sets this accordingly; `true`/`false` force it either way. This
  /// field is always an explicit bool by the time it reaches [planCodegen] —
  /// the planner itself stays pure (no I/O) so it's testable without
  /// touching a filesystem.
  final bool generateOpenapi;

  /// Optional tracked template copied to `<apiDir>/pubspec.yaml` before resolve.
  /// When empty, [sdkFloor] is patched into the existing pubspec instead.
  final String apiPubspecTemplate;

  /// SDK constraint forced into the generated API pubspec (the upstream
  /// generator pins a floor too low for the null-aware-element output).
  final String sdkFloor;

  /// `build_runner clean` + drop `pubspec.lock` before the API build — the
  /// robust path on persistent self-hosted runners with stale outputs.
  final bool clean;

  /// `dart pub upgrade dart_style` before the API build — the alternative to
  /// [clean] for the dart_style ↔ copy_with_extension_gen analyzer conflict.
  final bool upgradeDartStyle;

  final List<String> buildRunnerArgs;
  final String dart;
  final String flutter;
}

/// Build the ordered, inspectable plan for the layered codegen.
///
/// Mirrors the proven CI sequence, parameterised:
///   1. OpenAPI Generator CLI  → `<apiDir>/*.dart`            (needs Java)
///   2. materialise/patch the API `pubspec.yaml` SDK floor
///   3. API package `build_runner`  → `<apiDir>/*.g.dart`
///   4. app `flutter pub get` + `build_runner`  → riverpod/drift/go_router code
///
/// Steps 1-3 (the OpenAPI-client stage) are entirely omitted when
/// [CodegenConfig.generateOpenapi] is false — a consumer with no generated
/// OpenAPI client just gets step 4.
List<Step> planCodegen(CodegenConfig c) {
  final toolDir = resolveIn(c.workspace, c.codegenToolDir);
  final apiDir = resolveIn(c.workspace, c.apiDir);
  final projectDir = resolveIn(c.workspace, c.projectDir);
  final apiPubspec = resolveIn(apiDir, 'pubspec.yaml');

  final steps = <Step>[
    if (c.generateOpenapi) ...[
      // 1. Run the OpenAPI Generator CLI via its build_runner driver.
      RunStep(
        label: 'Generate OpenAPI client (Java CLI)',
        executable: c.dart,
        args: const ['pub', 'get'],
        workingDir: toolDir,
      ),
      RunStep(
        label: 'OpenAPI Generator build_runner',
        executable: c.dart,
        args: ['run', 'build_runner', 'build', ...c.buildRunnerArgs],
        workingDir: toolDir,
      ),

      // 2. Make sure the generated API pubspec has a usable SDK floor. A
      //    tracked template wins (also restores the file on runners where
      //    it's gitignored); otherwise patch the floor in place.
      if (c.apiPubspecTemplate.isNotEmpty)
        CopyFileStep(
          label: 'Materialise API pubspec from template',
          from: resolveIn(c.workspace, c.apiPubspecTemplate),
          to: apiPubspec,
        )
      else
        PatchSdkFloorStep(
          label: 'Patch API pubspec SDK floor',
          path: apiPubspec,
          sdkFloor: c.sdkFloor,
        ),

      // 3. Generate the API package's *.g.dart (json_serializable / copy_with).
      if (c.clean)
        DeleteFileStep(
          label: 'Drop stale API pubspec.lock',
          path: resolveIn(apiDir, 'pubspec.lock'),
        ),
      RunStep(
        label: 'API pub get',
        executable: c.dart,
        args: const ['pub', 'get'],
        workingDir: apiDir,
      ),
      if (c.upgradeDartStyle)
        RunStep(
          label: 'Upgrade dart_style',
          executable: c.dart,
          args: const ['pub', 'upgrade', 'dart_style'],
          workingDir: apiDir,
        ),
      if (c.clean)
        RunStep(
          label: 'API build_runner clean',
          executable: c.dart,
          args: const ['run', 'build_runner', 'clean'],
          workingDir: apiDir,
        ),
      RunStep(
        label: 'API build_runner build',
        executable: c.dart,
        args: ['run', 'build_runner', 'build', ...c.buildRunnerArgs],
        workingDir: apiDir,
      ),
    ],

    // 4. App-level codegen (riverpod / drift / go_router).
    RunStep(
      label: 'App flutter pub get',
      executable: c.flutter,
      args: const ['pub', 'get'],
      workingDir: projectDir,
    ),
    RunStep(
      label: 'App build_runner build',
      executable: c.dart,
      args: ['run', 'build_runner', 'build', ...c.buildRunnerArgs],
      workingDir: projectDir,
    ),
  ];

  return steps;
}
