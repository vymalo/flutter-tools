import 'package:test/test.dart';
import 'package:vymalo_flutter_tools/vymalo_flutter_tools.dart';

IosBuildConfig _cfg() => const IosBuildConfig(
      workspace: '/w',
      appId: 'com.vymalo.vymalo',
      teamId: 'TEAM123',
      profileName: 'Vymalo App Store',
      certPath: '/tmp/c.p12',
      certPassword: 'p12pass',
      profilePath: '/tmp/p.mobileprovision',
      keychainPath: '/tmp/ci.keychain-db',
      keychainPassword: 'kcpass',
      dartDefines: ['MEDUSA_BASE_URL=https://api.vymalo.com'],
    );

void main() {
  group('planIosBuild', () {
    test('step order mirrors the build_ipa_appstore lane', () {
      final labels = planIosBuild(_cfg()).map((s) => s.label).toList();
      expect(labels, [
        'Create CI keychain',
        'Default keychain',
        'Add keychain to the search list',
        'Unlock keychain',
        'Keychain settings (no auto-lock)',
        'Import distribution certificate',
        'Grant key partition list',
        'Import Apple WWDR G3',
        'Import Apple WWDR G4',
        'Import Apple WWDR G5',
        'Import Apple WWDR G6',
        'Install provisioning profile',
        'Force manual code-signing settings',
        'Write ExportOptions.plist',
        'flutter build ipa (release, --no-codesign)',
        'xcodebuild -exportArchive (sign + export App Store IPA)',
      ]);
    });

    test(
        'adds the keychain to the user search list (else exportArchive can '
        'not find the identity)', () {
      final step = planIosBuild(_cfg())
          .whereType<RunStep>()
          .firstWhere((s) => s.label == 'Add keychain to the search list');
      expect(step.executable, 'sh');
      expect(step.args.last, contains('security list-keychains -d user -s'));
      expect(step.args.last, contains('/tmp/ci.keychain-db'));
    });

    test('WWDR imports are best-effort (allowFailure)', () {
      final wwdr = planIosBuild(_cfg())
          .whereType<RunStep>()
          .where((s) => s.label.startsWith('Import Apple WWDR'));
      expect(wwdr, hasLength(4));
      expect(wwdr.every((s) => s.allowFailure), isTrue);
    });

    test('flutter build uses --no-codesign + dart-defines', () {
      final build = planIosBuild(_cfg())
          .whereType<RunStep>()
          .firstWhere((s) => s.executable == 'flutter');
      expect(build.args, [
        'build',
        'ipa',
        '--release',
        '--no-codesign',
        '--dart-define=MEDUSA_BASE_URL=https://api.vymalo.com',
      ]);
      expect(build.workingDir, '/w/mobile');
    });

    test('xcodebuild exports the archive to build/ios/ipa', () {
      final x = planIosBuild(_cfg())
          .whereType<RunStep>()
          .firstWhere((s) => s.executable == 'xcodebuild');
      expect(
          x.args,
          containsAllInOrder([
            '-exportArchive',
            '-archivePath',
            '/w/mobile/build/ios/archive/Runner.xcarchive',
            '-exportOptionsPlist',
            '/tmp/ci.keychain-db.ExportOptions.plist',
            '-exportPath',
            '/w/mobile/build/ios/ipa',
          ]));
    });

    test('ExportOptions.plist is app-store + manual + Apple Distribution', () {
      final plist = planIosBuild(_cfg()).whereType<WriteFileStep>().single;
      expect(plist.path, '/tmp/ci.keychain-db.ExportOptions.plist');
      expect(plist.contents, contains('<string>app-store</string>'));
      expect(plist.contents, contains('<key>com.vymalo.vymalo</key>'));
      expect(plist.contents, contains('<string>Vymalo App Store</string>'));
      expect(plist.contents, contains('TEAM123'));
      expect(plist.contents, contains('<string>manual</string>'));
    });

    test('code-signing settings target all three build configurations', () {
      final css = planIosBuild(_cfg())
          .whereType<RunStep>()
          .firstWhere((s) => s.args.contains('update_code_signing_settings'));
      expect(css.args, contains('build_configurations:Debug,Release,Profile'));
      expect(css.args, contains('code_sign_identity:Apple Distribution'));
      expect(css.args, contains('use_automatic_signing:false'));
    });
  });
}
