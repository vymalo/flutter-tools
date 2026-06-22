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
- `fastlane-setup` — OS-aware Ruby/Bundler/CocoaPods setup (Linux `setup-ruby`
  vs. the Mac Mini's manual cache).
- `build-android` / `build-ios` — wrap the Fastlane build lanes.
- Optionally a `workflow_call` that composes them end-to-end.
