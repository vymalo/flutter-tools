import 'step.dart';

/// Inputs for a signed App Store IPA build.
///
/// Mirrors the proven `build_ipa_appstore` Fastlane lane: build the archive
/// UNSIGNED with Flutter (`--no-codesign`, the flutter/flutter#176636 workaround
/// — flutter_tools' signing pre-check rejects "Apple Distribution" certs), then
/// sign + export with `xcodebuild -exportArchive` against a CI keychain.
///
/// Secrets never enter a [Step] as a flag: the CLI command decodes the base64
/// cert/profile to temp files and generates the ephemeral keychain name +
/// password BEFORE planning, and passes only the paths here.
class IosBuildConfig {
  const IosBuildConfig({
    required this.workspace,
    this.projectDir = 'mobile',
    required this.appId,
    required this.teamId,
    required this.profileName,
    required this.certPath,
    required this.certPassword,
    required this.profilePath,
    required this.keychainPath,
    required this.keychainPassword,
    this.dartDefines = const [],
    this.flutter = 'flutter',
    this.fastlane = 'fastlane',
  });

  final String workspace;
  final String projectDir;

  /// Bundle identifier, e.g. `com.vymalo.vymalo`.
  final String appId;

  /// 10-char Apple Developer team id.
  final String teamId;

  /// Display name of the App Store provisioning profile.
  final String profileName;

  /// Temp path of the decoded distribution `.p12`.
  final String certPath;
  final String certPassword;

  /// Temp path of the decoded App Store `.mobileprovision`.
  final String profilePath;

  /// Ephemeral CI keychain path + password (created, then deleted by the CLI).
  final String keychainPath;
  final String keychainPassword;

  /// `KEY=VALUE` entries, each emitted as `--dart-define=KEY=VALUE`.
  final List<String> dartDefines;

  final String flutter;
  final String fastlane;
}

/// Apple WWDR intermediate cert versions to import (the leaf P12 may chain to
/// any of these depending on when it was issued; import all, best-effort).
const _wwdrVersions = ['G3', 'G4', 'G5', 'G6'];

/// The App Store ExportOptions.plist (manual signing, Apple Distribution).
String iosExportOptionsPlist(
        {required String teamId,
        required String appId,
        required String profileName}) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0">\n'
    '<dict>\n'
    '  <key>method</key>\n'
    '  <string>app-store</string>\n'
    '  <key>teamID</key>\n'
    '  <string>$teamId</string>\n'
    '  <key>provisioningProfiles</key>\n'
    '  <dict>\n'
    '    <key>$appId</key>\n'
    '    <string>$profileName</string>\n'
    '  </dict>\n'
    '  <key>signingStyle</key>\n'
    '  <string>manual</string>\n'
    '  <key>signingCertificate</key>\n'
    '  <string>Apple Distribution</string>\n'
    '  <key>stripSwiftSymbols</key>\n'
    '  <true/>\n'
    '</dict>\n'
    '</plist>\n';

/// Build the plan: keychain + cert/profile import → code-signing settings →
/// ExportOptions → `flutter build ipa --no-codesign` → `xcodebuild -exportArchive`.
List<Step> planIosBuild(IosBuildConfig c) {
  final appDir = resolveIn(c.workspace, c.projectDir);
  final exportPlist = '${c.keychainPath}.ExportOptions.plist';
  final archivePath = resolveIn(appDir, 'build/ios/archive/Runner.xcarchive');
  final ipaOutDir = resolveIn(appDir, 'build/ios/ipa');
  final xcodeproj = resolveIn(appDir, 'ios/Runner.xcodeproj');
  final defines = [for (final d in c.dartDefines) '--dart-define=$d'];

  RunStep sec(String label, List<String> args, {bool allowFailure = false}) =>
      RunStep(
          label: label,
          executable: 'security',
          args: args,
          workingDir: appDir,
          allowFailure: allowFailure);

  return [
    // ── ephemeral keychain ──
    sec('Create CI keychain',
        ['create-keychain', '-p', c.keychainPassword, c.keychainPath]),
    sec('Default keychain', ['default-keychain', '-s', c.keychainPath]),
    // Add the keychain to the user SEARCH LIST (prepended, keeping the existing
    // entries) — otherwise `xcodebuild -exportArchive` can't find the imported
    // distribution identity ("No signing certificate found"), even though it's the
    // default keychain. This is what Fastlane's create_keychain does internally;
    // the raw `security` port must do it explicitly. `delete-keychain` (cleanup)
    // removes it from the list again.
    RunStep(
      label: 'Add keychain to the search list',
      executable: 'sh',
      args: [
        '-c',
        'security list-keychains -d user -s "${c.keychainPath}" '
            '\$(security list-keychains -d user | sed -e \'s/["]//g\')',
      ],
      workingDir: appDir,
    ),
    sec('Unlock keychain',
        ['unlock-keychain', '-p', c.keychainPassword, c.keychainPath]),
    // Keep it unlocked long enough for the whole build (no auto-lock surprise
    // mid-codesign in a headless session).
    sec('Keychain settings (no auto-lock)',
        ['set-keychain-settings', '-lut', '21600', c.keychainPath]),

    // ── distribution cert ──
    // -A (any app) + -T codesign/xcodebuild grant access without a UI dialog;
    // set-key-partition-list completes that on macOS 13+ headless CI.
    sec('Import distribution certificate', [
      'import',
      c.certPath,
      '-P',
      c.certPassword,
      '-A',
      '-T',
      '/usr/bin/codesign',
      '-T',
      '/usr/bin/xcodebuild',
      '-k',
      c.keychainPath,
    ]),
    sec('Grant key partition list', [
      'set-key-partition-list',
      '-S',
      'apple-tool:,apple:,codesign:',
      '-s',
      '-k',
      c.keychainPassword,
      c.keychainPath,
    ]),

    // ── Apple WWDR intermediates (best-effort; some versions 404 / already present) ──
    for (final g in _wwdrVersions)
      RunStep(
        label: 'Import Apple WWDR $g',
        executable: 'sh',
        args: [
          '-c',
          'curl -sSfL "https://www.apple.com/certificateauthority/AppleWWDRCA$g.cer" '
              '-o "${c.keychainPath}.wwdr$g.cer" '
              '&& security import "${c.keychainPath}.wwdr$g.cer" -k "${c.keychainPath}"',
        ],
        workingDir: appDir,
        allowFailure: true,
      ),

    // ── provisioning profile + code-signing settings (fastlane single-actions) ──
    RunStep(
      label: 'Install provisioning profile',
      executable: c.fastlane,
      args: ['run', 'install_provisioning_profile', 'path:${c.profilePath}'],
      workingDir: appDir,
    ),
    RunStep(
      label: 'Force manual code-signing settings',
      executable: c.fastlane,
      args: [
        'run',
        'update_code_signing_settings',
        'use_automatic_signing:false',
        'team_id:${c.teamId}',
        'bundle_identifier:${c.appId}',
        'profile_name:${c.profileName}',
        'code_sign_identity:Apple Distribution',
        // Force CODE_SIGN_IDENTITY into all three configs — Debug/Release
        // otherwise inherit "Apple Development" from xcconfig and the archive
        // fails. fastlane run splits a comma-separated string into the array.
        'build_configurations:Debug,Release,Profile',
        'path:$xcodeproj',
      ],
      workingDir: appDir,
    ),

    // ── export options + build + export ──
    WriteFileStep(
      label: 'Write ExportOptions.plist',
      path: exportPlist,
      contents: iosExportOptionsPlist(
          teamId: c.teamId, appId: c.appId, profileName: c.profileName),
    ),
    RunStep(
      label: 'flutter build ipa (release, --no-codesign)',
      executable: c.flutter,
      args: ['build', 'ipa', '--release', '--no-codesign', ...defines],
      workingDir: appDir,
    ),
    RunStep(
      label: 'xcodebuild -exportArchive (sign + export App Store IPA)',
      executable: 'xcodebuild',
      args: [
        '-exportArchive',
        '-archivePath',
        archivePath,
        '-exportOptionsPlist',
        exportPlist,
        '-exportPath',
        ipaOutDir,
      ],
      workingDir: appDir,
    ),
  ];
}
