import 'step.dart';

/// Inputs for a TestFlight upload via Fastlane `pilot` (`upload_to_testflight`).
///
/// Auth is an App Store Connect API key passed as a JSON file
/// (`api_key_path:` — `{key_id, issuer_id, key, in_house}`). The CLI writes that
/// JSON from the environment before planning, so the secret never enters a
/// [Step]; this config only carries its path.
class TestflightSubmitConfig {
  const TestflightSubmitConfig({
    required this.ipaPath,
    required this.apiKeyPath,
    this.skipWaitingForBuildProcessing = true,
    this.workingDir = '.',
    this.fastlane = 'fastlane',
  });

  final String ipaPath;
  final String apiKeyPath;
  final bool skipWaitingForBuildProcessing;
  final String workingDir;
  final String fastlane;
}

/// Plan a single `fastlane run upload_to_testflight …` invocation.
List<Step> planTestflightSubmit(TestflightSubmitConfig c) => [
  RunStep(
    label: 'fastlane pilot → TestFlight',
    executable: c.fastlane,
    args: [
      'run',
      'upload_to_testflight',
      'api_key_path:${c.apiKeyPath}',
      'ipa:${c.ipaPath}',
      'skip_waiting_for_build_processing:${c.skipWaitingForBuildProcessing}',
    ],
    workingDir: c.workingDir,
  ),
];
