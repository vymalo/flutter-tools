import 'step.dart';

/// Inputs for a Google Play upload via Fastlane `supply`
/// (`upload_to_play_store`). The service-account JSON is decoded by the CLI to a
/// temp file before planning, so the secret never enters a [Step]; this config
/// only carries its path.
class PlaySubmitConfig {
  const PlaySubmitConfig({
    required this.aabPath,
    required this.packageName,
    required this.jsonKeyPath,
    this.track = 'internal',
    this.releaseStatus = 'completed',
    this.rollout,
    this.skipUploadApk = true,
    this.skipUploadMetadata = true,
    this.skipUploadChangelogs = true,
    this.skipUploadImages = true,
    this.skipUploadScreenshots = true,
    this.changesNotSentForReview = false,
    this.workingDir = '.',
    this.fastlane = 'fastlane',
  });

  final String aabPath;
  final String packageName;
  final String jsonKeyPath;

  /// internal | alpha | beta | production (or a custom track name).
  final String track;

  /// completed | draft | halted | inProgress.
  final String releaseStatus;

  /// Staged-rollout fraction (e.g. `0.2`) — only for `inProgress`/`halted`.
  final String? rollout;

  final bool skipUploadApk;
  final bool skipUploadMetadata;
  final bool skipUploadChangelogs;
  final bool skipUploadImages;
  final bool skipUploadScreenshots;

  /// For closed tracks without a review step (managed publishing).
  final bool changesNotSentForReview;

  final String workingDir;
  final String fastlane;
}

/// Plan a single `fastlane run upload_to_play_store …` invocation — runs
/// standalone (no Fastfile/Appfile needed). `key:value` is Fastlane's CLI form.
List<Step> planPlaySubmit(PlaySubmitConfig c) {
  final args = <String>[
    'run',
    'upload_to_play_store',
    'track:${c.track}',
    'aab:${c.aabPath}',
    'package_name:${c.packageName}',
    'json_key:${c.jsonKeyPath}',
    'release_status:${c.releaseStatus}',
    if (c.rollout != null) 'rollout:${c.rollout}',
    'skip_upload_apk:${c.skipUploadApk}',
    'skip_upload_metadata:${c.skipUploadMetadata}',
    'skip_upload_changelogs:${c.skipUploadChangelogs}',
    'skip_upload_images:${c.skipUploadImages}',
    'skip_upload_screenshots:${c.skipUploadScreenshots}',
    if (c.changesNotSentForReview) 'changes_not_sent_for_review:true',
  ];

  return [
    RunStep(
      label: 'fastlane supply → Play ${c.track} (${c.releaseStatus})',
      executable: c.fastlane,
      args: args,
      workingDir: c.workingDir,
    ),
  ];
}
