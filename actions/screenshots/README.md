# `screenshots` action

Captures **store screenshots** across a device matrix — Android phone + tablets
(emulators, auto-created) and iOS (simulators, auto-created) — by running your
Flutter **integration test** on each device. Hardened for CI: clean cold boot, one
drive retry, per-device rescue (one bad device doesn't sink the rest), and
**fail-loud if zero** are captured.

## Requirements (read me first)

| What you need | Details |
|---|---|
| **Runner** | For **both** platforms: **macOS with Xcode *and* the Android SDK** (emulator + `avdmanager` + `adb`). Android-only can run on Linux **with `/dev/kvm`** (GitHub-hosted `ubuntu-latest` has it) — pass an `x86_64` `sysimg`. iOS can only run on macOS. |
| **Run before this** | `actions/checkout` + a Flutter setup ([`ios-setup`](../ios-setup) covers Mac). |
| **Secrets** | None to capture. (Uploading the result to a store is a separate step — see [`app-store-submit`](../app-store-submit) / [`play-submit`](../play-submit).) |
| **In your repo — the part beginners miss** | A working `flutter drive` screenshot setup (see below). Without it you get a **green run with zero screenshots**. |

### The integration-test setup your app must have

1. **A driver** at `test_driver/integration_test.dart` that passes an
   **`onScreenshot`** callback — this is the #1 gotcha. `integrationDriver`
   *silently drops every screenshot* when `onScreenshot` is null:

   ```dart
   import 'dart:io';
   import 'package:integration_test/integration_test_driver_extended.dart';
   Future<void> main() => integrationDriver(
     onScreenshot: (name, bytes, [args]) async {
       final file = File('screenshots/$name.png')..createSync(recursive: true);
       file.writeAsBytesSync(bytes);
       return true;
     },
   );
   ```

2. **A test** at `integration_test/screenshots_test.dart` that drives your app and
   calls `binding.takeScreenshot('01_home')` at each screen. On **Android** you
   must `await binding.convertFlutterSurfaceToImage()` first (Android-only; guard
   with `if (Platform.isAndroid)`), and only *after* the first frame has settled.

The driver writes PNGs to `<project-dir>/screenshots/`; the action collects them
into the Play (`fastlane/metadata/android/...`) and App Store
(`fastlane/screenshots/...`) layouts.

> ⚠️ **A green run proves nothing.** Always check the `count` output (or the
> uploaded artifact) — and per device class, not just the total.

## Choosing devices to hit App Store / Play slots

The **simulator/AVD you pick decides the pixel size**, and stores route each image
to a display slot by that size. To target a specific App Store slot:

| ASC slot | Resolution (portrait) | Simulator |
|---|---|---|
| iPhone 6.9″ | 1320×2868 | `iPhone 16 Pro Max` |
| iPhone 6.5″ | 1242×2688 / 1284×2778 | `iPhone 11 Pro Max` / `iPhone 14 Plus` |
| iPhone 6.7″ | 1290×2796 | `iPhone 15 Plus` |
| iPad 13″ | 2064×2752 | `iPad Pro 13-inch (M4)` |
| iPad 12.9″ | 2048×2732 | `iPad Pro (12.9-inch) (6th generation)` |

> Plain `iPhone 16 Pro` is **6.3″ (1206×2622)** — *not* a valid slot. Use the **Max**.

Override the matrix with `ios-devices` (`"sim|label,…"`) and `android-devices`
(`"avd:profile:class,…"`). Empty = sensible defaults (phone + 7″ + 10″ Android;
6.9″ + 6.7″ + iPad 13″ iOS).

## Usage

```yaml
- uses: actions/checkout@v4
- uses: vymalo/flutter-tools/actions/ios-setup@v0
- id: shots
  uses: vymalo/flutter-tools/actions/screenshots@v0
  with:
    platform: both                       # android | ios | both
    # Apple Silicon Mac → arm64 (default). Intel/Linux → x86_64:
    sysimg: 'system-images;android-36;google_apis;arm64-v8a'
    dart-defines: |
      API_URL=https://api.example.com
- run: echo "Captured ${{ steps.shots.outputs.count }} screenshots"
```

## Inputs (most-used)

| Input | Required | Default | What it does |
|---|---|---|---|
| `platform` | no | `both` | `android` / `ios` / `both`. |
| `driver` / `target` | no | the two paths above | Your integration-test driver + test. |
| `sysimg` | no | `…arm64-v8a` | Android system image. **Use `…x86_64` on Intel/Linux.** |
| `android-home` | no | `$ANDROID_HOME` / Homebrew | Android SDK root. |
| `android-devices` / `ios-devices` | no | sensible defaults | Override the matrix. |
| `dart-defines` | no | — | One `KEY=VALUE` per line → a `--dart-define` each. |

## Outputs

| Output | What |
|---|---|
| `count` / `android-count` / `ios-count` | PNGs captured (total / per platform). |
| `android-dir` / `ios-dir` | Where the collected screenshots landed (feed to the upload actions). |
