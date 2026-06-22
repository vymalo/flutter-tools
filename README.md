# flutter-tools

Reusable, **heavily-configurable** GitHub Actions for Vymalo's Flutter CI/CD —
so the build/codegen/release steps live in **one** place and other repos just
reference them, instead of copy-pasting workflow YAML.

## Why

`vymalo-shop`'s three mobile workflows (`mobile-ci`, `mobile-release`,
`mobile-screenshots`) each carried the same ~30-line codegen block (with a
literal *"keep this block in sync"* comment) plus duplicated S3-upload and
Fastlane-setup shells. This repo packages those as composite actions so a change
is made **once** and every workflow — in this project or the next one — picks it
up via `uses:`.

## Design

- **Logic in Dart, glue in bash.** The orchestration is a small, unit-tested
  Dart CLI (`bin/flutter_tools.dart`); each action is a thin composite wrapper
  that sets up the toolchain and runs the CLI. Bash is only used where it's
  genuinely trivial.
- **Plan / execute split.** The CLI builds an inspectable `List<Step>` (run a
  command, write/copy/delete a file, …) and then executes it. That makes the
  behaviour testable without spawning a process — see `test/`. Use `--dry-run`
  to print any plan.
- **Free + self-hosted only.** Nothing here needs a paid service; it runs on
  your own runners.

## Actions

### `codegen` — layered Flutter codegen

OpenAPI Generator client → generated-API `*.g.dart` → app `build_runner`
(riverpod / drift / go_router), as one step.

```yaml
- uses: vymalo/flutter-tools/actions/codegen@v0
  with:
    flutter-version: '3.44.2'
    # everything below is optional — these are the defaults
    project-dir: mobile
    api-dir: mobile/api
    codegen-tool-dir: mobile/tool/openapi_codegen
    sdk-floor: '>=3.12.0 <4.0.0'
    clean: 'true'              # drop pubspec.lock + build_runner clean (persistent runners)
    # api-pubspec-template: mobile/openapi/api-pubspec.yaml  # restores a gitignored api/pubspec.yaml
```

| Input | Default | Notes |
|-------|---------|-------|
| `project-dir` | `mobile` | Flutter app dir |
| `api-dir` | `mobile/api` | generated OpenAPI client package |
| `codegen-tool-dir` | `mobile/tool/openapi_codegen` | drives the OpenAPI Generator CLI |
| `api-pubspec-template` | — | tracked pubspec copied into `api-dir` (restores it when gitignored); wins over `sdk-floor` |
| `sdk-floor` | `>=3.12.0 <4.0.0` | forced into the generated API pubspec |
| `clean` | `true` | drop `pubspec.lock` + `build_runner clean` before the API build |
| `upgrade-dart-style` | `false` | `dart pub upgrade dart_style` instead of `clean` |
| `setup-flutter` / `setup-java` | `true` | skip if the caller already set them up |
| `flutter-version` / `flutter-channel` / `java-version` | `3.44.2` / `stable` / `21` | |

### `android-setup` — get an Android job build-ready

Flutter + Java (+ optional Ruby for Fastlane) then the layered codegen, in one
step.

```yaml
- uses: vymalo/flutter-tools/actions/android-setup@v0
  with:
    setup-flutter: 'false'   # arc runner already has it
    setup-java: 'false'
    clean: 'false'
    upgrade-dart-style: 'true'
```

### `android-build` — signed APK / AAB (no Fastlane)

Decodes the keystore, writes `android/key.properties`, runs `flutter build`,
cleans up, and exposes the artifact paths. No keystore ⇒ unsigned debug APK.

```yaml
- id: build
  uses: vymalo/flutter-tools/actions/android-build@v0
  with:
    build-number: ${{ github.run_number }}
    artifacts: both                       # apk | aab | both
    keystore-base64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
    keystore-password: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
    key-alias: ${{ vars.ANDROID_KEY_ALIAS }}
    key-password: ${{ secrets.ANDROID_KEY_PASSWORD }}
    dart-defines: |
      MEDUSA_BASE_URL=https://api.vymalo.com
      AUTH_BASE_URL=https://auth.vymalo.com
      PUBLISHABLE_KEY=${{ secrets.MEDUSA_PUBLISHABLE_KEY }}
# outputs: steps.build.outputs.{signed, apk-path, aab-path}
```

> The consumer's `android/app/build.gradle.kts` must read `key.properties` for
> signing (the standard Flutter setup) — that part stays in your repo.

## Quiet logs by default

Every action runs **quiet** (chronic-style): a command's output is captured and
printed **only if it fails** — a green run shows one tick per step. Turn on
**Settings → … → step debug logging** (or set `RUNNER_DEBUG=1`, or pass
`--verbose` to the CLI) to stream everything live. Implemented natively in the
Dart `StepRunner`, so there's no `moreutils`/`chronic` dependency.

## The CLI (local use)

```sh
dart pub get
dart run bin/flutter_tools.dart codegen --workspace . --dry-run   # print the plan
dart run bin/flutter_tools.dart codegen --workspace .             # run it
dart test                                                         # unit tests
```

## Using a private copy of this repo

If `vymalo/flutter-tools` is private, enable **Settings → Actions → General →
Access → "Accessible from repositories owned by the organization"** so other
org repos can `uses:` it. (Public needs nothing.)

## Versioning

Reference a moving major tag (`@v0`) or pin a release (`@v0.1.0`). Tag releases
as the action surface stabilises.

## Roadmap (extract from vymalo-shop next)

- `s3-presign` — upload an artifact to S3/MinIO + emit a presigned URL (replaces
  the ~40-line shell pasted 3×).
- `ios-setup` / `ios-build` — the Mac Mini side (CocoaPods + the keychain/cert
  dance + `xcodebuild` export). Bigger; iOS is signed-cert territory.
- `play-submit` — upload an AAB to a Play track (today via Fastlane `supply`).
- Optionally a `workflow_call` that composes setup → build → upload end-to-end.
