# `testflight-submit` action

Uploads an **IPA to TestFlight** via Fastlane `pilot`, authenticated with an App
Store Connect **API key** (no Apple-ID password). Use it after
[`ios-build`](../ios-build).

## Requirements (read me first)

| What you need | Details |
|---|---|
| **Runner** | macOS (the IPA is built on a Mac; keep the upload on the same job). |
| **Run before this** | A built IPA — typically [`ios-build`](../ios-build). No Dart/Flutter setup required — the action downloads a prebuilt CLI binary. (Dart on `PATH` is a harmless nice-to-have, not needed.) |
| **Secrets / credentials** | An App Store Connect **API key**: `asc-key-id`, `asc-issuer-id`, and `asc-api-key-base64` (base64 of the `.p8` you downloaded from ASC → Users and Access → Integrations → App Store Connect API). |
| **In your Apple account** | The app must already exist in App Store Connect, and the API key needs at least the **App Manager** role. |

> Fastlane is auto-installed if missing — no separate setup step required.

## Usage

```yaml
- id: build
  uses: vymalo/flutter-tools/actions/ios-build@v0
  with: { /* signing inputs */ }

- uses: vymalo/flutter-tools/actions/testflight-submit@v0
  with:
    ipa: ${{ steps.build.outputs.ipa-path }}
    asc-key-id:         ${{ secrets.ASC_KEY_ID }}
    asc-issuer-id:      ${{ secrets.ASC_ISSUER_ID }}
    asc-api-key-base64: ${{ secrets.ASC_API_KEY_BASE64 }}
```

## Inputs

| Input | Required | Default | What it does |
|---|---|---|---|
| `ipa` | no | first under `build/ios/ipa` | Path to the IPA to upload. |
| `asc-key-id` | yes | — | API key id. |
| `asc-issuer-id` | yes | — | API issuer id. |
| `asc-api-key-base64` | yes | — | base64 of the `.p8` key. |
| `skip-waiting` | no | `true` | Don't block the job waiting for Apple to finish processing the build. |
