import 'step.dart';

/// Inputs for an S3 (or S3-compatible, e.g. MinIO) upload. Credentials come from
/// the standard AWS environment (`AWS_ACCESS_KEY_ID`, …) — never config here.
class S3UploadConfig {
  const S3UploadConfig({
    required this.file,
    required this.bucket,
    required this.key,
    this.endpoint = '',
    this.expiresIn = 604800, // 7 days
    this.aws = 'aws',
  });

  /// Absolute path to the file to upload.
  final String file;
  final String bucket;

  /// Object key within the bucket (e.g. `mobile/<run>/app.aab`).
  final String key;

  /// Custom endpoint for S3-compatible stores (MinIO). Empty = real AWS S3.
  final String endpoint;

  /// Presigned-URL lifetime in seconds.
  final int expiresIn;

  final String aws;
}

/// The `--endpoint-url <url>` pair, or empty when targeting real AWS S3.
List<String> endpointFlag(S3UploadConfig c) =>
    c.endpoint.isEmpty ? const [] : ['--endpoint-url', c.endpoint];

String s3Uri(S3UploadConfig c) => 's3://${c.bucket}/${c.key}';

/// Plan the upload itself (`aws s3 cp`). Bucket-ensure (head-bucket || mb) and
/// `aws s3 presign` are handled in the command — the former needs conditional
/// logic, the latter needs to capture stdout (the URL).
List<Step> planS3Upload(S3UploadConfig c) => [
      RunStep(
        label: 'aws s3 cp → ${s3Uri(c)}',
        executable: c.aws,
        args: [
          's3',
          'cp',
          c.file,
          s3Uri(c),
          ...endpointFlag(c),
          '--no-progress',
        ],
        workingDir: '.',
      ),
    ];

/// `aws s3 presign` args to fetch the shareable URL.
List<String> presignArgs(S3UploadConfig c) => [
      's3',
      'presign',
      s3Uri(c),
      '--expires-in',
      '${c.expiresIn}',
      ...endpointFlag(c),
    ];
