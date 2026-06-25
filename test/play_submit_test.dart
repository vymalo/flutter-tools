import 'package:test/test.dart';
import 'package:vymalo_flutter_tools/vymalo_flutter_tools.dart';

void main() {
  group('planPlaySubmit', () {
    RunStep only(List<Step> s) => s.whereType<RunStep>().single;

    test('defaults: internal track, completed, AAB-only upload', () {
      final step = only(
        planPlaySubmit(
          const PlaySubmitConfig(
            aabPath: '/w/app.aab',
            packageName: 'com.acme.app',
            jsonKeyPath: '/tmp/key.json',
          ),
        ),
      );
      expect(step.executable, 'fastlane');
      expect(step.args, containsAllInOrder(['run', 'upload_to_play_store']));
      expect(
        step.args,
        containsAll([
          'track:internal',
          'aab:/w/app.aab',
          'package_name:com.acme.app',
          'json_key:/tmp/key.json',
          'release_status:completed',
          'skip_upload_apk:true',
          'skip_upload_changelogs:true',
        ]),
      );
      expect(step.args.where((a) => a.startsWith('rollout:')), isEmpty);
      expect(step.args, isNot(contains('changes_not_sent_for_review:true')));
    });

    test('staged rollout on a production inProgress release', () {
      final step = only(
        planPlaySubmit(
          const PlaySubmitConfig(
            aabPath: '/w/app.aab',
            packageName: 'com.acme.app',
            jsonKeyPath: '/tmp/key.json',
            track: 'production',
            releaseStatus: 'inProgress',
            rollout: '0.2',
          ),
        ),
      );
      expect(
        step.args,
        containsAll([
          'track:production',
          'release_status:inProgress',
          'rollout:0.2',
        ]),
      );
    });

    test('changes-not-sent-for-review toggles the flag', () {
      final step = only(
        planPlaySubmit(
          const PlaySubmitConfig(
            aabPath: '/w/app.aab',
            packageName: 'com.acme.app',
            jsonKeyPath: '/tmp/key.json',
            changesNotSentForReview: true,
          ),
        ),
      );
      expect(step.args, contains('changes_not_sent_for_review:true'));
    });
  });
}
