import 'package:test/test.dart';
import 'package:vymalo_flutter_tools/vymalo_flutter_tools.dart';

void main() {
  group('s3-upload', () {
    test('plan is a single aws s3 cp with --no-progress', () {
      final steps = planS3Upload(
        const S3UploadConfig(
          file: '/w/app.aab',
          bucket: 'artifacts',
          key: 'mobile/run/app.aab',
        ),
      );
      final cp = steps.whereType<RunStep>().single;
      expect(cp.executable, 'aws');
      expect(cp.args, [
        's3',
        'cp',
        '/w/app.aab',
        's3://artifacts/mobile/run/app.aab',
        '--no-progress',
      ]);
    });

    test('endpoint flag injected for S3-compatible stores (MinIO)', () {
      const c = S3UploadConfig(
        file: '/w/a',
        bucket: 'b',
        key: 'k',
        endpoint: 'https://minio.local',
      );
      expect(endpointFlag(c), ['--endpoint-url', 'https://minio.local']);
      expect(
        planS3Upload(c).whereType<RunStep>().single.args,
        containsAllInOrder(['--endpoint-url', 'https://minio.local']),
      );
    });

    test('no endpoint flag for real AWS S3', () {
      expect(
        endpointFlag(const S3UploadConfig(file: 'f', bucket: 'b', key: 'k')),
        isEmpty,
      );
    });

    test('presign args carry the expiry (+ endpoint when set)', () {
      expect(
        presignArgs(
          const S3UploadConfig(
            file: 'f',
            bucket: 'b',
            key: 'k',
            expiresIn: 3600,
          ),
        ),
        ['s3', 'presign', 's3://b/k', '--expires-in', '3600'],
      );
    });
  });
}
