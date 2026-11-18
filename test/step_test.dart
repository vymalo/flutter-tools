import 'package:test/test.dart';
import 'package:vymalo_flutter_tools/vymalo_flutter_tools.dart';

void main() {
  group('resolveIn', () {
    test('normalizes empty, ".", "./", and "./." to root', () {
      expect(resolveIn('/w', ''), '/w');
      expect(resolveIn('/w', '.'), '/w');
      expect(resolveIn('/w', './'), '/w');
      expect(resolveIn('/w', './.'), '/w');
      expect(resolveIn('/w', r'.\'), '/w');
    });

    test('strips leading "./" when joining relative paths', () {
      expect(resolveIn('/w', './a'), '/w/a');
      expect(resolveIn('/w', '././a/b'), '/w/a/b');
      expect(resolveIn('/w', 'apps/mobile'), '/w/apps/mobile');
    });

    test('returns absolute paths unchanged', () {
      expect(resolveIn('/w', '/abs/path'), '/abs/path');
    });

    test('rejects path traversal ("..") even after "./" normalization', () {
      expect(() => resolveIn('/w', '..'), throwsArgumentError);
      expect(() => resolveIn('/w', './..'), throwsArgumentError);
      expect(() => resolveIn('/w', 'a/../b'), throwsArgumentError);
    });
  });
}
