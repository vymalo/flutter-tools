import 'step.dart';

/// Inputs for an App Store Connect upload via Fastlane `deliver`
/// (`upload_to_app_store`). Two modes share this one action:
///   • **binary**      — upload the IPA + (optionally) submit it for review;
///   • **screenshots** — `skip_binary_upload` + push the screenshot set.
///
/// `deliver` attaches everything to an EDITABLE App Store version, so
/// [appVersion] (the marketing `x.y.z`) is always required — that version must
/// already exist / be editable on App Store Connect.
///
/// Auth is an App Store Connect API key JSON file (`api_key_path:`), written by
/// the CLI from the environment before planning — the secret never enters a
/// [Step].
class AppStoreSubmitConfig {
  const AppStoreSubmitConfig({
    required this.apiKeyPath,
    required this.appVersion,
    this.ipaPath,
    this.screenshotsPath,
    this.submitForReview = false,
    this.skipBinaryUpload = false,
    this.skipMetadata = true,
    this.skipScreenshots = true,
    this.overwriteScreenshots = false,
    this.force = true,
    this.precheckIncludeInAppPurchases = false,
    this.workingDir = '.',
    this.fastlane = 'fastlane',
  });

  final String apiKeyPath;
  final String appVersion;

  /// IPA to upload (binary mode). Null when `skipBinaryUpload` is true.
  final String? ipaPath;

  /// Directory of screenshots to deliver (screenshots mode).
  final String? screenshotsPath;

  /// Submit the version for App Store review after upload.
  final bool submitForReview;

  final bool skipBinaryUpload;
  final bool skipMetadata;
  final bool skipScreenshots;
  final bool overwriteScreenshots;

  /// Skip deliver's HTML preview confirmation prompt (non-interactive CI).
  final bool force;
  final bool precheckIncludeInAppPurchases;

  final String workingDir;
  final String fastlane;
}

/// Plan a single `fastlane run upload_to_app_store …` invocation.
List<Step> planAppStoreSubmit(AppStoreSubmitConfig c) {
  final args = <String>[
    'run',
    'upload_to_app_store',
    'api_key_path:${c.apiKeyPath}',
    'app_version:${c.appVersion}',
    if (c.ipaPath != null) 'ipa:${c.ipaPath}',
    if (c.screenshotsPath != null) 'screenshots_path:${c.screenshotsPath}',
    'skip_binary_upload:${c.skipBinaryUpload}',
    'skip_metadata:${c.skipMetadata}',
    'skip_screenshots:${c.skipScreenshots}',
    if (c.overwriteScreenshots) 'overwrite_screenshots:true',
    'submit_for_review:${c.submitForReview}',
    'force:${c.force}',
    'precheck_include_in_app_purchases:${c.precheckIncludeInAppPurchases}',
    // No metadata in CI → deliver's precheck has nothing to validate; disable it
    // so a screenshots/binary-only upload doesn't fail the precheck step.
    'run_precheck_before_submit:false',
  ];

  return [
    RunStep(
      label: 'fastlane deliver → App Store'
          '${c.submitForReview ? ' (submit for review)' : ''}',
      executable: c.fastlane,
      args: args,
      workingDir: c.workingDir,
    ),
  ];
}
