# flutter-tools

**Reusable, heavily-configurable GitHub Actions for Flutter CI/CD.** Stop
copy-pasting the same codegen / build / sign / upload YAML into every workflow
(and every repo) — reference these instead.

```yaml
- uses: vymalo/flutter-tools/actions/android-build@v0
  with:
    build-number: ${{ github.run_number }}
    keystore-base64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
    # …
```

Built for [Vymalo](https://github.com/vymalo), but **designed to be generic** —
the inputs are wired so you can point them at any Flutter project layout. MIT
licensed; use it for yours.

## What you get

| Action | Does |
|--------|------|
| [`codegen`](actions/codegen) | Layered codegen: OpenAPI client → generated `*.g.dart` → app `build_runner` (riverpod/drift/go_router) |
| [`version-stamp`](actions/version-stamp) | Stamp a build number into pubspec (`version: x.y.z+<build>`) — unique/increasing CFBundleVersion / versionCode per build |
| [`android-setup`](actions/android-setup) | Flutter + Java (+ optional Ruby) + codegen — get an Android job build-ready |
| [`android-build`](actions/android-build) | Signed APK/AAB (`keystore → key.properties → flutter build`). **No Fastlane needed** |
| [`play-submit`](actions/play-submit) | Upload an AAB to a Google Play track (configurable track / status / rollout) |
| [`ios-setup`](actions/ios-setup) | Flutter + Java + codegen + Bundler + `pod install` — get an iOS job build-ready (Mac runner) |
| [`ios-build`](actions/ios-build) | Signed App Store IPA (CI keychain → `flutter build ipa --no-codesign` → `xcodebuild -exportArchive`; the flutter#176636 workaround) |
| [`testflight-submit`](actions/testflight-submit) | Upload an IPA to TestFlight (Fastlane pilot, ASC API key) |
| [`app-store-submit`](actions/app-store-submit) | Upload IPA and/or screenshots to App Store Connect, optionally submit for review (Fastlane deliver) |
| [`artifact-upload`](actions/artifact-upload) | Upload to GitHub Artifacts **and/or** S3/MinIO (+ presigned URL) |
| [`release-cut`](actions/release-cut) | Cut a release with **no PR permission / no PAT**: conventional-commits semver → tag → GitHub Release (auto-notes) |
| [`screenshots`](actions/screenshots) | Capture store screenshots across an Android + iOS device matrix (cold boot, drive-retry, per-device rescue, fail-loud) |

**New here?** Click any action above — each folder has its own README with a
plain-language **Requirements** checklist (which runner, what to run before it,
which secrets/permissions) and a copy-paste example. Start with the
[Quick start](#quick-start) below.

## Why it's built this way

- **Logic in Dart, glue in bash.** Each action is a thin composite wrapper around
  a small, unit-tested Dart CLI. The orchestration is a pure, inspectable
  `List<Step>` (run a command, write/copy/delete a file…) that's *planned* then
  *executed* — so behaviour is testable without spawning a process. Run any
  command with `--dry-run` to print its plan.
- **Prebuilt CLI, not resolved at runtime.** Most actions download a
  self-contained, **checksum-verified** binary of the CLI for the runner's
  OS/arch (Linux x64/arm64, macOS arm64) — no Dart SDK, no `dart pub get` on
  every run. Only `codegen` / `android-setup` / `ios-setup` still use `dart run`,
  since they set up Flutter anyway. See [Releasing the CLI](#releasing-the-cli).
- **Quiet by default.** Command output is captured and shown **only on failure**
  (chronic-style) — a green run is one tick per step. Turn on GitHub step-debug
  (`RUNNER_DEBUG=1`) or pass `--verbose` to stream everything. No `moreutils`
  dependency; it's built into the Dart runner.
- **No Docker.** Every action is composite/JS — nothing needs a Docker daemon, so
  they work on self-hosted runners that don't have one. Where a good community
  action exists it's reused ([`upload-artifact`](https://github.com/actions/upload-artifact),
  [`install-aws-cli-action`](https://github.com/unfor19/install-aws-cli-action),
  [`flutter-action`](https://github.com/subosito/flutter-action)).
- **Free + self-hosted friendly.** No paid services. Runs the same on
  GitHub-hosted or self-hosted runners. The build/codegen actions read your
  Flutter toolchain from PATH (with opt-in setup steps); the rest just run the
  prebuilt CLI binary and need nothing on PATH.

## Quick start

A minimal Android build-and-publish job:

```yaml
jobs:
  android:
    runs-on: ubuntu-latest   # or your self-hosted label
    steps:
      - uses: actions/checkout@v4

      - uses: vymalo/flutter-tools/actions/android-setup@v0
        with:
          flutter-version: '3.x'

      - id: build
        uses: vymalo/flutter-tools/actions/android-build@v0
        with:
          build-number: ${{ github.run_number }}
          keystore-base64:   ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
          keystore-password: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          key-alias:         ${{ vars.ANDROID_KEY_ALIAS }}
          key-password:      ${{ secrets.ANDROID_KEY_PASSWORD }}
          dart-defines: |
            API_URL=https://api.example.com

      - uses: vymalo/flutter-tools/actions/artifact-upload@v0
        with:
          file: ${{ steps.build.outputs.aab-path }}
          to-gh-artifacts: 'true'

      - uses: vymalo/flutter-tools/actions/play-submit@v0
        if: github.ref == 'refs/heads/main'
        with:
          aab: ${{ steps.build.outputs.aab-path }}
          package-name: com.example.app
          track: internal
          service-account-json-base64: ${{ secrets.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64 }}
```

> Your `android/app/build.gradle.kts` must read `key.properties` for signing
> (the standard Flutter setup) — that part stays in your repo.

Each action's `action.yml` documents every input; the most useful knobs:

- **`android-build`** — `artifacts: apk|aab|both`, `dart-defines` (one `KEY=VALUE`
  per line), all signing inputs (omit them → unsigned debug APK). Outputs:
  `apk-path`, `aab-path`, `signed`.
- **`play-submit`** — `track`, `release-status` (`completed|draft|halted|inProgress`),
  `rollout` (staged %), `changes-not-sent-for-review`.
- **`artifact-upload`** — `to-gh-artifacts`, `to-s3` + `s3-bucket`/`s3-key`/
  `s3-endpoint` (MinIO). Outputs: `s3-url` (presigned), `s3-key`.
- **`codegen`** — `project-dir`, `api-dir`, `codegen-tool-dir`, `sdk-floor`,
  `clean`, `api-pubspec-template`. Tuned for an OpenAPI-generated client + a
  layered `build_runner`; point the dirs at your layout.
- **`screenshots`** — `platform`, `driver`/`target`, `locale`, `dart-defines`,
  and the **device matrix**: `android-devices` (`"avd:profile:class,…"`) and
  `ios-devices` (`"sim|label,…"`). The *simulator/AVD* picks the resolution;
  `fastlane deliver` routes each PNG to the matching App Store Connect display
  slot **by its pixel size** (the label is just the filename prefix, for grouping
  + order). To hit a specific slot, choose the simulator that yields it:

  | ASC slot | Resolution (portrait) | Simulator |
  |---|---|---|
  | iPhone 6.9″ | 1320×2868 | `iPhone 16 Pro Max` |
  | iPhone 6.5″ | 1242×2688 / 1284×2778 | `iPhone 11 Pro Max` / `iPhone 14 Plus` |
  | iPhone 6.7″ | 1290×2796 | `iPhone 15 Plus` |
  | iPad 13″ | 2064×2752 | `iPad Pro 13-inch (M4)` |
  | iPad 12.9″ | 2048×2732 | `iPad Pro (12.9-inch) (6th generation)` |

  > ⚠️ Plain `iPhone 16 Pro` is **6.3″ (1206×2622)** — *not* an ASC slot. Use the
  > **Max**. A device type missing from the runner's Xcode is skipped (per-device
  > rescue), so the run won't fail — but you'll silently miss that slot; check the
  > artifact. Apple Watch needs a watchOS sim + a watch app target — not covered.

## The CLI (run it locally)

```sh
dart pub get
dart run bin/flutter_tools.dart android-build --dry-run   # print the plan
dart run bin/flutter_tools.dart play-submit  --help
dart test
```

## Compatibility

- **Runners:** GitHub-hosted or self-hosted Linux for the Android/Dart actions;
  a **macOS runner with Xcode** for `ios-build` / `ios-setup` (the keychain +
  `xcodebuild -exportArchive`).
- **Private consumers:** if you fork this private, enable **Settings → Actions →
  Access → "Accessible from repositories owned by the organization"**. Public
  needs nothing.
- **Pin a version:** `@v0` (moving major) or a release tag like `@v0.4.0`.

## Roadmap

An optional `workflow_call` that composes setup → version-stamp → build →
release-cut → submit → publish end-to-end, so a consumer calls one thing.

## Releasing the CLI

The actions download a prebuilt CLI binary from a GitHub Release; the version is
pinned per action ref by [`cli-version.txt`](cli-version.txt) (consumers don't
manage it). To cut a release:

1. Bump the version in [`cli-version.txt`](cli-version.txt) and merge it to `main`.
2. **Actions** tab → **release-cli** → **Run workflow**.

The workflow compiles the binary on each runner (Linux x64/arm64, macOS arm64),
then creates the `cli-v<version>` tag + GitHub Release with the binaries and a
`SHA256SUMS`. No local `git tag` needed; re-running for the same version updates
the existing release.

## Contributing

It's a normal Dart package — `dart pub get`, `dart test`, `dart analyze`. Logic
goes in `lib/src/` as a pure planner (`plan…()` → `List<Step>`) with a unit test;
the action is a thin `action.yml` wrapper that runs the CLI. PRs welcome.

## License

MIT — see [LICENSE](LICENSE).
