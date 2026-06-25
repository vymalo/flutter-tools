import 'package:test/test.dart';
import 'package:vymalo_flutter_tools/vymalo_flutter_tools.dart';

void main() {
  group('default device matrices', () {
    test('android = phone + 7" + 10"', () {
      expect(defaultAndroidDevices.map((d) => d.imagesClass), [
        'phoneScreenshots',
        'sevenInchScreenshots',
        'tenInchScreenshots',
      ]);
      expect(defaultAndroidDevices.first.avd, 'vymalo_screenshots');
    });

    test('ios = 6.9" + 6.5" + iPad', () {
      expect(defaultIosDevices.map((d) => d.label), [
        'iPhone69',
        'iPhone67',
        'iPadPro13',
      ]);
      // The 6.9" default must be the Max (1320×2868), not the 6.3" iPhone 16 Pro.
      expect(defaultIosDevices.first.sim, 'iPhone 16 Pro Max');
    });
  });

  group('store path mapping', () {
    test('android images dir = Play supply layout', () {
      expect(
        androidImagesDir('/w/mobile', 'phoneScreenshots'),
        '/w/mobile/fastlane/metadata/android/en-US/images/phoneScreenshots',
      );
      expect(
        androidImagesDir('/w/mobile', 'tenInchScreenshots', locale: 'de-DE'),
        '/w/mobile/fastlane/metadata/android/de-DE/images/tenInchScreenshots',
      );
    });

    test('ios screenshots dir + label-prefixed dest name', () {
      expect(
        iosScreenshotsDir('/w/mobile'),
        '/w/mobile/fastlane/screenshots/en-US',
      );
      expect(iosDestName('iPhone69', '01_shop.png'), 'iPhone69-01_shop.png');
    });
  });

  group('device overrides', () {
    test('empty → defaults', () {
      expect(parseAndroidDevices(''), same(defaultAndroidDevices));
      expect(parseIosDevices('   '), same(defaultIosDevices));
    });

    test('android override "avd:profile:class"', () {
      final d = parseAndroidDevices('foo:pixel_7:phoneScreenshots');
      expect(d, hasLength(1));
      expect(d.single.avd, 'foo');
      expect(d.single.profile, 'pixel_7');
      expect(d.single.imagesClass, 'phoneScreenshots');
    });

    test('ios override "sim|label", multiple', () {
      final d = parseIosDevices(
        'iPhone 16 Pro|p69, iPad Pro 13-inch (M4)|ipad',
      );
      expect(d.map((x) => x.label), ['p69', 'ipad']);
      expect(d.first.sim, 'iPhone 16 Pro');
    });

    test('malformed rows throw', () {
      expect(() => parseAndroidDevices('only:two'), throwsFormatException);
      expect(() => parseIosDevices('no-pipe'), throwsFormatException);
    });
  });
}
