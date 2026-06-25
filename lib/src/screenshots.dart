/// Device-matrix screenshot capture — the pure, testable parts (device tables +
/// store-path mapping). The imperative orchestration (boot emulators/simulators,
/// `flutter drive`, collect, per-device rescue) lives in the `screenshots` CLI
/// command, since it is heavy I/O with retry/rescue that does not fit a planner.
library;

/// An Android emulator entry: the AVD name, the device profile to create it from
/// if missing, and the Play Store image class it feeds.
class AndroidScreenshotDevice {
  const AndroidScreenshotDevice({
    required this.avd,
    required this.profile,
    required this.imagesClass,
  });

  final String avd;
  final String profile;

  /// Play image class dir: phoneScreenshots / sevenInchScreenshots / tenInchScreenshots.
  final String imagesClass;
}

/// An iOS simulator entry: the device TYPE to create a sim from, and the label
/// prefixed onto the captured filenames (so App Store Connect groups them).
class IosScreenshotDevice {
  const IosScreenshotDevice({required this.sim, required this.label});

  final String sim;
  final String label;
}

/// The default Play matrix: phone + 7" + 10" (AVDs auto-created if missing).
const List<AndroidScreenshotDevice> defaultAndroidDevices = [
  AndroidScreenshotDevice(
    avd: 'vymalo_screenshots',
    profile: 'pixel_6',
    imagesClass: 'phoneScreenshots',
  ),
  AndroidScreenshotDevice(
    avd: 'vymalo_screenshots_7in',
    profile: 'Nexus 7',
    imagesClass: 'sevenInchScreenshots',
  ),
  AndroidScreenshotDevice(
    avd: 'vymalo_screenshots_10in',
    profile: 'Nexus 10',
    imagesClass: 'tenInchScreenshots',
  ),
];

/// The default App Store matrix: 6.9", 6.5" iPhones + a 12.9" iPad.
const List<IosScreenshotDevice> defaultIosDevices = [
  IosScreenshotDevice(sim: 'iPhone 16 Pro', label: 'iPhone69'),
  IosScreenshotDevice(sim: 'iPhone 15 Plus', label: 'iPhone65'),
  IosScreenshotDevice(sim: 'iPad Pro 13-inch (M4)', label: 'iPadPro129'),
];

/// `fastlane supply` Play images dir for a device class.
String androidImagesDir(
  String appRoot,
  String imagesClass, {
  String locale = 'en-US',
}) => '$appRoot/fastlane/metadata/android/$locale/images/$imagesClass';

/// `fastlane deliver` App Store screenshots dir.
String iosScreenshotsDir(String appRoot, {String locale = 'en-US'}) =>
    '$appRoot/fastlane/screenshots/$locale';

/// App Store dest filename: `<label>-<srcBasename>` (so deliver groups by device).
String iosDestName(String label, String srcBasename) => '$label-$srcBasename';

/// Parse a device override string `"avd:profile:imagesClass,…"` (empty → default).
List<AndroidScreenshotDevice> parseAndroidDevices(String spec) {
  if (spec.trim().isEmpty) return defaultAndroidDevices;
  return [
    for (final row in spec.split(',').where((r) => r.trim().isNotEmpty))
      () {
        final p = row.split(':');
        if (p.length != 3) {
          throw FormatException(
            'android device must be avd:profile:class — got "$row"',
          );
        }
        return AndroidScreenshotDevice(
          avd: p[0].trim(),
          profile: p[1].trim(),
          imagesClass: p[2].trim(),
        );
      }(),
  ];
}

/// Parse an iOS device override string `"sim|label,…"` (empty → default).
List<IosScreenshotDevice> parseIosDevices(String spec) {
  if (spec.trim().isEmpty) return defaultIosDevices;
  return [
    for (final row in spec.split(',').where((r) => r.trim().isNotEmpty))
      () {
        final p = row.split('|');
        if (p.length != 2) {
          throw FormatException('ios device must be sim|label — got "$row"');
        }
        return IosScreenshotDevice(sim: p[0].trim(), label: p[1].trim());
      }(),
  ];
}
