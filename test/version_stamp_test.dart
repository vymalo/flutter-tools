import 'dart:io';

import 'package:test/test.dart';
import 'package:vymalo_flutter_tools/vymalo_flutter_tools.dart';

void main() {
  group('planVersionStamp', () {
    test('emits a single PatchVersionStep at <projectDir>/pubspec.yaml', () {
      final steps = planVersionStamp(
        const VersionStampConfig(workspace: '/w', buildNumber: '42'),
      );
      expect(steps, hasLength(1));
      final patch = steps.single as PatchVersionStep;
      expect(patch.path, '/w/mobile/pubspec.yaml');
      expect(patch.buildNumber, '42');
    });

    test('honours a custom project-dir', () {
      final steps = planVersionStamp(
        const VersionStampConfig(
          workspace: '/w',
          projectDir: 'app',
          buildNumber: '7',
        ),
      );
      expect((steps.single as PatchVersionStep).path, '/w/app/pubspec.yaml');
    });

    test('passes the marketing-version override through to the step', () {
      final patch =
          planVersionStamp(
                const VersionStampConfig(
                  workspace: '/w',
                  buildNumber: '7',
                  marketingVersion: '2.5.0',
                ),
              ).single
              as PatchVersionStep;
      expect(patch.marketingVersion, '2.5.0');
    });

    test('marketingVersion defaults to null (keep existing)', () {
      final patch =
          planVersionStamp(
                const VersionStampConfig(workspace: '/w', buildNumber: '7'),
              ).single
              as PatchVersionStep;
      expect(patch.marketingVersion, isNull);
    });
  });

  group('PatchVersionStep execution', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('vstamp'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<String> stamp(
      String initial,
      String build, {
      String? marketing,
    }) async {
      final f = File('${dir.path}/pubspec.yaml')..writeAsStringSync(initial);
      await StepRunner(log: (_) {}).run([
        PatchVersionStep(
          label: 's',
          path: f.path,
          buildNumber: build,
          marketingVersion: marketing,
        ),
      ]);
      return f.readAsStringSync();
    }

    test(
      'replaces an existing +build, keeping the marketing version',
      () async {
        final out = await stamp('name: vymalo\nversion: 1.2.3+9\n', '42');
        expect(out, contains('version: 1.2.3+42'));
        expect(out, contains('name: vymalo'));
      },
    );

    test('adds a +build when none is present', () async {
      final out = await stamp('version: 1.0.0\n', '5');
      expect(out, contains('version: 1.0.0+5'));
    });

    test('throws when there is no semver version line', () async {
      expect(stamp('name: x\n', '1'), throwsA(isA<StepFailure>()));
    });

    test('marketingVersion override rewrites x.y.z + stamps build', () async {
      final out = await stamp(
        'name: v\nversion: 1.2.3+9\n',
        '88',
        marketing: '2.0.0',
      );
      expect(out, contains('version: 2.0.0+88'));
    });

    test('marketingVersion override works even when the file version is '
        'non-semver, as long as a version: line exists', () async {
      final out = await stamp('version: 0.0.0-dev\n', '3', marketing: '1.5.0');
      expect(out, contains('version: 1.5.0+3'));
    });

    test(
      'throws with an override when there is no version: line at all',
      () async {
        expect(
          stamp('name: x\n', '1', marketing: '1.0.0'),
          throwsA(isA<StepFailure>()),
        );
      },
    );
  });
}
