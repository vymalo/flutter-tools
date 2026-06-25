import 'package:test/test.dart';
import 'package:vymalo_flutter_tools/vymalo_flutter_tools.dart';

void main() {
  group('planAndroidBuild', () {
    test('signed build: key.properties → apk(release) + aab → cleanup', () {
      final steps = planAndroidBuild(
        const AndroidBuildConfig(
          workspace: '/w',
          signed: true,
          keystorePath: '/tmp/ks.keystore',
          keystorePassword: 'sp',
          keyAlias: 'al',
          keyPassword: 'kp',
          buildNumber: '42',
        ),
      );

      expect(steps.map((s) => s.label), [
        'Write android/key.properties',
        'flutter build apk (release)',
        'flutter build appbundle (release)',
        'Remove android/key.properties',
      ]);

      final keyProps = steps.whereType<WriteFileStep>().single;
      expect(keyProps.path, '/w/mobile/android/key.properties');
      expect(keyProps.contents, contains('storeFile=/tmp/ks.keystore'));
      expect(keyProps.contents, contains('keyAlias=al'));

      final apk = steps.whereType<RunStep>().first;
      expect(apk.executable, 'flutter');
      expect(apk.args, ['build', 'apk', '--release', '--build-number=42']);
      expect(apk.workingDir, '/w/mobile');
    });

    test('unsigned build: debug APK only, no key.properties, no AAB', () {
      final steps = planAndroidBuild(const AndroidBuildConfig(workspace: '/w'));
      expect(steps.whereType<WriteFileStep>(), isEmpty);
      expect(steps.whereType<DeleteFileStep>(), isEmpty);
      final runs = steps.whereType<RunStep>().toList();
      expect(runs.single.args, ['build', 'apk', '--debug']);
    });

    test('dart-defines are emitted on every build command', () {
      final steps = planAndroidBuild(
        const AndroidBuildConfig(
          workspace: '/w',
          signed: true,
          dartDefines: ['MEDUSA_BASE_URL=https://api.x', 'KEY=v'],
        ),
      );
      for (final r in steps.whereType<RunStep>()) {
        expect(
          r.args,
          containsAll([
            '--dart-define=MEDUSA_BASE_URL=https://api.x',
            '--dart-define=KEY=v',
          ]),
        );
      }
    });

    test('artifacts=apk skips the appbundle even when signed', () {
      final steps = planAndroidBuild(
        const AndroidBuildConfig(
          workspace: '/w',
          signed: true,
          artifacts: {AndroidArtifact.apk},
        ),
      );
      expect(steps.where((s) => s.label.contains('appbundle')), isEmpty);
    });

    test('artifact paths differ by signing', () {
      expect(
        androidArtifactPath(AndroidArtifact.apk, signed: true),
        endsWith('app-release.apk'),
      );
      expect(
        androidArtifactPath(AndroidArtifact.apk, signed: false),
        endsWith('app-debug.apk'),
      );
      expect(
        androidArtifactPath(AndroidArtifact.aab, signed: true),
        endsWith('app-release.aab'),
      );
    });
  });
}
