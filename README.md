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
| [`android-setup`](actions/android-setup) | Flutter + Java (+ optional Ruby) + codegen — get a job build-ready |
| [`android-build`](actions/android-build) | Signed APK/AAB (`keystore → key.properties → flutter build`). **No Fastlane needed** |
| [`play-submit`](actions/play-submit) | Upload an AAB to a Google Play track (configurable track / status / rollout) |
| [`artifact-upload`](actions/artifact-upload) | Upload to GitHub Artifacts **and/or** S3/MinIO (+ presigned URL) |

## Why it's built this way

- **Logic in Dart, glue in bash.** Each action is a thin composite wrapper around
  a small, unit-tested Dart CLI. The orchestration is a pure, inspectable
  `List<Step>` (run a command, write/copy/delete a file…) that's *planned* then
  *executed* — so behaviour is testable without spawning a process. Run any
  command with `--dry-run` to print its plan.
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
  GitHub-hosted or self-hosted runners (the actions read your toolchain from
  PATH, with opt-in setup steps).

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

## The CLI (run it locally)

```sh
dart pub get
dart run bin/flutter_tools.dart android-build --dry-run   # print the plan
dart run bin/flutter_tools.dart play-submit  --help
dart test
```

## Compatibility

- **Runners:** GitHub-hosted or self-hosted Linux. macOS works for the
  Dart/Flutter actions; the keychain-heavy iOS build isn't packaged yet (roadmap).
- **Private consumers:** if you fork this private, enable **Settings → Actions →
  Access → "Accessible from repositories owned by the organization"**. Public
  needs nothing.
- **Pin a version:** `@v0` (moving major) or a release tag like `@v0.3.0`.

## Roadmap

`ios-setup` / `ios-build` (the keychain + `xcodebuild` export), and an optional
`workflow_call` that composes setup → build → upload end-to-end.

## Contributing

It's a normal Dart package — `dart pub get`, `dart test`, `dart analyze`. Logic
goes in `lib/src/` as a pure planner (`plan…()` → `List<Step>`) with a unit test;
the action is a thin `action.yml` wrapper that runs the CLI. PRs welcome.

## License

MIT — see [LICENSE](LICENSE).
