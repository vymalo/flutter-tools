# `android-build` action

Builds a **signed Android APK and/or AAB** in one step: decodes your keystore,
writes `android/key.properties`, runs `flutter build`, and exposes the file paths
as outputs. No Fastlane/Ruby needed. With no keystore it falls back to an
**unsigned debug APK** (handy for PR builds).

## Requirements (read me first)

| What you need | Details |
|---|---|
| **Runner** | Linux (or any) with **Flutter on PATH** — run [`android-setup`](../android-setup) first. |
| **Run before this** | `actions/checkout` → `android-setup` (or your own Flutter setup). |
| **Secrets (for a *signed* build)** | `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD` (secrets) + the key alias (a repo var is fine). Omit all of them → unsigned debug APK. |
| **In your repo** | `android/app/build.gradle.kts` (or `.gradle`) must read `key.properties` for signing — the standard Flutter signing setup. This action writes the file; your Gradle reads it. |

> **Make the keystore base64 once, locally:** `base64 -i upload-keystore.jks | pbcopy`
> then paste into a repo secret. Never commit the keystore itself.

## Usage

```yaml
- uses: actions/checkout@v4
- uses: vymalo/flutter-tools/actions/android-setup@v0
  with: { flutter-version: '3.44.2' }

- id: build
  uses: vymalo/flutter-tools/actions/android-build@v0
  with:
    artifacts: both                    # apk | aab | both
    build-number: ${{ github.run_number }}
    keystore-base64:   ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
    keystore-password: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
    key-alias:         ${{ vars.ANDROID_KEY_ALIAS }}
    key-password:      ${{ secrets.ANDROID_KEY_PASSWORD }}
    dart-defines: |
      API_URL=https://api.example.com
- run: echo "AAB at ${{ steps.build.outputs.aab-path }}"
```

## Inputs (most-used)

| Input | Required | Default | What it does |
|---|---|---|---|
| `artifacts` | no | `both` | `apk`, `aab`, or `both`. |
| `build-number` | no | _(pubspec)_ | Android `versionCode`. Usually `${{ github.run_number }}`. |
| `dart-defines` | no | — | One `KEY=VALUE` per line → a `--dart-define` each. |
| `keystore-base64` + `keystore-password` + `key-alias` + `key-password` | for signing | — | Signing material. Omit all → unsigned debug APK. |

## Outputs

| Output | What |
|---|---|
| `apk-path` / `aab-path` | Absolute path to the built file (AAB empty if unsigned/skipped). |
| `signed` | `true` when a release-signed build was produced. |

Feed `aab-path` into [`play-submit`](../play-submit) and either path into
[`artifact-upload`](../artifact-upload).
