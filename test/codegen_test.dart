import 'package:test/test.dart';
import 'package:vymalo_flutter_tools/vymalo_flutter_tools.dart';

void main() {
  group('planCodegen', () {
    test('default plan is the proven layered sequence', () {
      final steps = planCodegen(const CodegenConfig(workspace: '/w'));
      final labels = steps.map((s) => s.label).toList();

      expect(labels, [
        'Generate OpenAPI client (Java CLI)',
        'OpenAPI Generator build_runner',
        'Patch API pubspec SDK floor',
        'Drop stale API pubspec.lock',
        'API pub get',
        'API build_runner clean',
        'API build_runner build',
        'App flutter pub get',
        'App build_runner build',
      ]);
    });

    test('resolves relative dirs against the workspace', () {
      final steps = planCodegen(const CodegenConfig(workspace: '/w'));
      final toolGet = steps.whereType<RunStep>().first;
      expect(toolGet.workingDir, '/w/mobile/tool/openapi_codegen');

      final appGet = steps.whereType<RunStep>().firstWhere(
        (s) => s.label == 'App flutter pub get',
      );
      expect(appGet.workingDir, '/w/mobile');
      expect(appGet.executable, 'flutter');
    });

    test('a pubspec template replaces the SDK-floor patch with a copy', () {
      final steps = planCodegen(
        const CodegenConfig(
          workspace: '/w',
          apiPubspecTemplate: 'mobile/openapi/api-pubspec.yaml',
        ),
      );
      expect(steps.whereType<PatchSdkFloorStep>(), isEmpty);
      final copy = steps.whereType<CopyFileStep>().single;
      expect(copy.from, '/w/mobile/openapi/api-pubspec.yaml');
      expect(copy.to, '/w/mobile/api/pubspec.yaml');
    });

    test('clean=false drops the lock-delete + build_runner clean steps', () {
      final steps = planCodegen(
        const CodegenConfig(workspace: '/w', clean: false),
      );
      expect(steps.whereType<DeleteFileStep>(), isEmpty);
      expect(steps.where((s) => s.label == 'API build_runner clean'), isEmpty);
    });

    test('upgradeDartStyle injects the upgrade before the API build', () {
      final steps = planCodegen(
        const CodegenConfig(workspace: '/w', upgradeDartStyle: true),
      );
      final labels = steps.map((s) => s.label).toList();
      expect(labels, contains('Upgrade dart_style'));
      expect(
        labels.indexOf('Upgrade dart_style'),
        lessThan(labels.indexOf('API build_runner build')),
      );
    });

    test('custom build-runner args propagate to every build_runner build', () {
      final steps = planCodegen(
        const CodegenConfig(
          workspace: '/w',
          buildRunnerArgs: ['--delete-conflicting-outputs', '--verbose'],
        ),
      );
      final builds = steps.whereType<RunStep>().where(
        (s) => s.args.contains('build_runner') && s.args.contains('build'),
      );
      expect(builds, isNotEmpty);
      for (final b in builds) {
        expect(
          b.args,
          containsAll(['--delete-conflicting-outputs', '--verbose']),
        );
      }
    });
  });
}
