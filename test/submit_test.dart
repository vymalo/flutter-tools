import 'package:test/test.dart';
import 'package:vymalo_flutter_tools/vymalo_flutter_tools.dart';

void main() {
  test('planTestflightSubmit emits one upload_to_testflight run', () {
    final steps = planTestflightSubmit(
      const TestflightSubmitConfig(
        ipaPath: '/b/app.ipa',
        apiKeyPath: '/t/asc.json',
        workingDir: '/w/mobile',
      ),
    );
    expect(steps, hasLength(1));
    final r = steps.single as RunStep;
    expect(r.executable, 'fastlane');
    expect(r.args, [
      'run',
      'upload_to_testflight',
      'api_key_path:/t/asc.json',
      'ipa:/b/app.ipa',
      'skip_waiting_for_build_processing:true',
    ]);
    expect(r.workingDir, '/w/mobile');
  });

  group('planAppStoreSubmit', () {
    test('binary mode: ipa + submit_for_review, no screenshots path', () {
      final r =
          planAppStoreSubmit(
                const AppStoreSubmitConfig(
                  apiKeyPath: '/t/asc.json',
                  appVersion: '1.2.3',
                  ipaPath: '/b/app.ipa',
                  submitForReview: true,
                ),
              ).single
              as RunStep;
      expect(
        r.args,
        containsAll([
          'run',
          'upload_to_app_store',
          'api_key_path:/t/asc.json',
          'app_version:1.2.3',
          'ipa:/b/app.ipa',
          'submit_for_review:true',
          'skip_binary_upload:false',
          'run_precheck_before_submit:false',
        ]),
      );
      expect(r.args.any((x) => x.startsWith('screenshots_path:')), isFalse);
    });

    test('screenshots mode: skip binary + screenshots path + overwrite', () {
      final r =
          planAppStoreSubmit(
                const AppStoreSubmitConfig(
                  apiKeyPath: '/t/asc.json',
                  appVersion: '1.2.3',
                  skipBinaryUpload: true,
                  skipScreenshots: false,
                  overwriteScreenshots: true,
                  screenshotsPath: '/s',
                ),
              ).single
              as RunStep;
      expect(
        r.args,
        containsAll([
          'skip_binary_upload:true',
          'skip_screenshots:false',
          'overwrite_screenshots:true',
          'screenshots_path:/s',
          'app_version:1.2.3',
        ]),
      );
      expect(r.args.any((x) => x.startsWith('ipa:')), isFalse);
    });
  });
}
