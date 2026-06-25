import 'package:test/test.dart';
import 'package:vymalo_flutter_tools/vymalo_flutter_tools.dart';

void main() {
  group('inferBump', () {
    test('feat → minor', () {
      expect(inferBump('feat(mobile): add a thing'), Bump.minor);
    });

    test('fix → patch', () {
      expect(inferBump('fix: a bug\n\nbody'), Bump.patch);
    });

    test('breaking (!) → major', () {
      expect(inferBump('feat(api)!: drop v1'), Bump.major);
    });

    test('BREAKING CHANGE in the body → major', () {
      expect(inferBump('feat: x\n\nBREAKING CHANGE: removed y'), Bump.major);
    });

    test('major beats minor beats patch when several types are present', () {
      expect(inferBump('fix: a\nfeat: b\nrefactor(core)!: c'), Bump.major);
      expect(inferBump('fix: a\nfeat: b'), Bump.minor);
    });

    test('nothing conventional → patch (a deliberate cut still ships)', () {
      expect(inferBump('ci: tweak\ndocs: readme'), Bump.patch);
    });
  });

  group('nextVersion', () {
    test('patch / minor / major increments', () {
      expect(nextVersion('1.0.0', Bump.patch), '1.0.1');
      expect(nextVersion('1.0.0', Bump.minor), '1.1.0');
      expect(nextVersion('1.2.3', Bump.major), '2.0.0');
    });

    test('integer (not string) increment past 9', () {
      expect(nextVersion('2.9.9', Bump.minor), '2.10.0');
      expect(nextVersion('2.9.9', Bump.patch), '2.9.10');
    });

    test('drops a +build on the base before bumping', () {
      expect(nextVersion('1.2.3+77', Bump.patch), '1.2.4');
    });
  });

  group('baseVersionFromTag', () {
    test('strips the prefix and any +build', () {
      expect(baseVersionFromTag('mobile-v1.4.2', 'mobile-v'), '1.4.2');
      expect(baseVersionFromTag('mobile-v1.4.2+9', 'mobile-v'), '1.4.2');
    });

    test('a different prefix', () {
      expect(baseVersionFromTag('v2.0.0', 'v'), '2.0.0');
    });
  });

  group('computeRelease', () {
    test('from the latest tag + auto bump', () {
      final r = computeRelease(
        tagPrefix: 'mobile-v',
        latestTag: 'mobile-v1.1.0',
        pubspecVersion: '9.9.9',
        bumpInput: 'auto',
        commitLog: 'feat(mobile): new screen',
      );
      expect(r.version, '1.2.0');
      expect(r.tag, 'mobile-v1.2.0');
      expect(r.bump, Bump.minor);
    });

    test('no tag → seeds from the pubspec version', () {
      final r = computeRelease(
        tagPrefix: 'mobile-v',
        latestTag: null,
        pubspecVersion: '1.0.0+7',
        bumpInput: 'patch',
        commitLog: '',
      );
      expect(r.version, '1.0.1');
      expect(r.tag, 'mobile-v1.0.1');
    });

    test('explicit bump overrides the commit inference', () {
      final r = computeRelease(
        tagPrefix: 'mobile-v',
        latestTag: 'mobile-v1.0.0',
        pubspecVersion: '1.0.0',
        bumpInput: 'major',
        commitLog: 'fix: tiny',
      );
      expect(r.version, '2.0.0');
      expect(r.bump, Bump.major);
    });
  });
}
