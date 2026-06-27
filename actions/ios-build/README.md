# `ios-build` action

Builds a **signed App Store IPA**: decodes your distribution certificate +
provisioning profile into a throwaway CI keychain, forces manual signing, then
`flutter build ipa --no-codesign` + `xcodebuild -exportArchive`. (That two-step is
the workaround for [flutter/flutter#176636](https://github.com/flutter/flutter/issues/176636),
where `flutter build ipa` wrongly rejects an "Apple Distribution" cert.)

## Requirements (read me first)

| What you need | Details |
|---|---|
| **Runner** | **macOS with Xcode** — required. |
| **Run before this** | `actions/checkout` → [`ios-setup`](../ios-setup) (or your own Flutter + `pod install`). |
| **Secrets / credentials** | `IOS_CERTIFICATE_BASE64` (base64 of your distribution `.p12`) + its password, `IOS_PROVISION_PROFILE_BASE64` (base64 of the App Store `.mobileprovision`), and your 10-char `team-id`. |
| **In your repo / Apple account** | A registered App ID (bundle identifier), a **Distribution** certificate, and an **App Store** provisioning profile that matches both — all created in the Apple Developer portal (one-time, you do this). |

> **Make the base64 blobs locally:** `base64 -i dist.p12 | pbcopy` and
> `base64 -i AppStore.mobileprovision | pbcopy`, then paste into repo secrets.

## Usage

```yaml
- uses: actions/checkout@v7
- uses: vymalo/flutter-tools/actions/ios-setup@v0
- id: build
  uses: vymalo/flutter-tools/actions/ios-build@v0
  with:
    app-id: com.example.app
    team-id: ${{ vars.APPLE_TEAM_ID }}
    profile-name: 'Example App Store'
    certificate-base64:       ${{ secrets.IOS_CERTIFICATE_BASE64 }}
    certificate-password:     ${{ secrets.IOS_CERTIFICATE_PASSWORD }}
    provision-profile-base64: ${{ secrets.IOS_PROVISION_PROFILE_BASE64 }}
- run: echo "IPA at ${{ steps.build.outputs.ipa-path }}"
```

## Inputs (most-used)

| Input | Required | Default | What it does |
|---|---|---|---|
| `app-id` | yes | `com.vymalo.vymalo` | Your bundle identifier. |
| `team-id` | yes | — | 10-char Apple Developer team id. |
| `profile-name` | yes | `Vymalo App Store` | Display name of the App Store provisioning profile. |
| `certificate-base64` + `certificate-password` | yes | — | Your distribution `.p12`. |
| `provision-profile-base64` | yes | — | Your App Store `.mobileprovision`. |
| `dart-defines` | no | — | One `KEY=VALUE` per line → a `--dart-define` each. |

## Outputs

| Output | What |
|---|---|
| `ipa-path` | Absolute path to the exported `.ipa` — feed it to [`testflight-submit`](../testflight-submit) or [`app-store-submit`](../app-store-submit). |
