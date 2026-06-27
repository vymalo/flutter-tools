# `app-store-submit` action

Uploads to **App Store Connect** via Fastlane `deliver` (`upload_to_app_store`).
Two modes, usable together:

- **Binary** — upload an IPA.
- **Screenshots** — upload a folder of store screenshots (set `skip-binary-upload: true`).

Optionally submits the version for review.

## Requirements (read me first)

| What you need | Details |
|---|---|
| **Runner** | macOS. |
| **Run before this** | A built IPA ([`ios-build`](../ios-build)) and/or a screenshots folder ([`screenshots`](../screenshots)). |
| **Secrets / credentials** | App Store Connect **API key**: `asc-key-id`, `asc-issuer-id`, `asc-api-key-base64` (base64 of the `.p8`). |
| **In your Apple account** | For **screenshots**, the app must have an **editable "Prepare for Submission" version** in App Store Connect — `deliver` attaches images to that draft, it doesn't create it. If it's missing you'll see *"Could not find a version to update"* (an ASC setup step, not a CI bug). Uploaded screenshots are routed to the right device slot **by their pixel size** — see [`screenshots`](../screenshots) for the resolution → slot table. |

> **Already handled for you:** this action disables `deliver`'s `precheck`
> (`run_precheck_before_submit:false`). Precheck can't validate in-app purchases
> with an API key and would otherwise red the run *after* a successful upload.

## Usage (screenshots only)

```yaml
- uses: vymalo/flutter-tools/actions/app-store-submit@v0
  with:
    screenshots-path: mobile/fastlane/screenshots
    skip-binary-upload: true
    overwrite-screenshots: true
    asc-key-id:         ${{ secrets.ASC_KEY_ID }}
    asc-issuer-id:      ${{ secrets.ASC_ISSUER_ID }}
    asc-api-key-base64: ${{ secrets.ASC_API_KEY_BASE64 }}
```

## Inputs (most-used)

| Input | Required | Default | What it does |
|---|---|---|---|
| `asc-key-id` + `asc-issuer-id` + `asc-api-key-base64` | yes | — | ASC API key. |
| `ipa` | no | first under `build/ios/ipa` | IPA to upload (binary mode). |
| `app-version` | no | _(pubspec)_ | Marketing `x.y.z` of the version to update. |
| `screenshots-path` | for screenshots | — | Folder of screenshots to deliver. |
| `skip-binary-upload` | no | `false` | `true` = screenshots only (no IPA). |
| `overwrite-screenshots` | no | `false` | Replace the version's existing screenshots. |
| `submit-for-review` | no | `false` | Submit the version for App Review after upload. |

See [`action.yml`](action.yml) for the full list.
