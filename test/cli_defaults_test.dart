import 'dart:io';

import 'package:test/test.dart';

void main() {
  const commandsWithProjectDir = [
    'version-stamp',
    'ios-build',
    'codegen',
    'android-build',
    'testflight-submit',
    'app-store-submit',
    'release-cut',
    'screenshots',
  ];

  group('CLI --project-dir defaults', () {
    for (final cmd in commandsWithProjectDir) {
      test('$cmd defaults --project-dir to "."', () {
        final res = Process.runSync(Platform.resolvedExecutable, [
          'bin/flutter_tools.dart',
          cmd,
          '--help',
        ]);
        expect(res.exitCode, 0, reason: '${res.stderr}');
        final out = res.stdout as String;
        expect(
          out,
          matches(RegExp(r'--project-dir[\s\S]*?\(defaults to "\."\)')),
        );
        expect(out, isNot(contains('(defaults to "mobile")')));
      });
    }

    test('codegen defaults --api-dir to "api" and --codegen-tool-dir to '
        '"tool/openapi_codegen"', () {
      final res = Process.runSync(Platform.resolvedExecutable, [
        'bin/flutter_tools.dart',
        'codegen',
        '--help',
      ]);
      expect(res.exitCode, 0, reason: '${res.stderr}');
      final out = res.stdout as String;
      expect(out, matches(RegExp(r'--api-dir[\s\S]*?\(defaults to "api"\)')));
      expect(
        out,
        matches(
          RegExp(
            r'--codegen-tool-dir[\s\S]*?\(defaults to "tool/openapi_codegen"\)',
          ),
        ),
      );
    });

    test('release-cut preserves --tag-prefix default "mobile-v"', () {
      final res = Process.runSync(Platform.resolvedExecutable, [
        'bin/flutter_tools.dart',
        'release-cut',
        '--help',
      ]);
      expect(res.exitCode, 0, reason: '${res.stderr}');
      final out = res.stdout as String;
      expect(
        out,
        matches(RegExp(r'--tag-prefix[\s\S]*?\(defaults to "mobile-v"\)')),
      );
    });

    test('version-stamp CLI resolves root pubspec.yaml by default', () {
      final dir = Directory.systemTemp.createTempSync('cli_vstamp_root');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(
        '${dir.path}/pubspec.yaml',
      ).writeAsStringSync('name: root_app\nversion: 1.2.3+1\n');

      final res = Process.runSync(Platform.resolvedExecutable, [
        'bin/flutter_tools.dart',
        'version-stamp',
        '--workspace',
        dir.path,
        '--build-number',
        '42',
        '--dry-run',
      ]);
      expect(res.exitCode, 0, reason: '${res.stderr}');
      final out = res.stdout as String;
      expect(out, contains('version=1.2.3'));
      expect(out, contains('full-version=1.2.3+42'));
    });

    test('release-cut CLI normalizes "." and "./" git-log scoping', () {
      final dir = Directory.systemTemp.createTempSync('cli_relcut_root');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(
        '${dir.path}/pubspec.yaml',
      ).writeAsStringSync('name: root_app\nversion: 1.0.0+1\n');
      Process.runSync('git', ['init'], workingDirectory: dir.path);
      Process.runSync('git', [
        'config',
        'user.name',
        'Test',
      ], workingDirectory: dir.path);
      Process.runSync('git', [
        'config',
        'user.email',
        'test@example.com',
      ], workingDirectory: dir.path);
      Process.runSync('git', ['add', '.'], workingDirectory: dir.path);
      Process.runSync('git', [
        'commit',
        '-m',
        'feat: initial root feature',
      ], workingDirectory: dir.path);

      for (final projectDirFlag in [null, '.', './']) {
        final args = [
          'bin/flutter_tools.dart',
          'release-cut',
          '--workspace',
          dir.path,
          if (projectDirFlag != null) ...['--project-dir', projectDirFlag],
        ];
        final res = Process.runSync(Platform.resolvedExecutable, args);
        expect(res.exitCode, 0, reason: '${res.stderr}');
        final out = res.stdout as String;
        expect(out, contains('bump=minor'));
        expect(out, contains('version=1.1.0'));
      }
    });
  });
}
