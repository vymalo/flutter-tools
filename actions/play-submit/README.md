# `play-submit` action

Uploads an **AAB to a Google Play track** via Fastlane `supply` — configurable
track, release status, and staged rollout. Uploads the binary only (skips
metadata/images/changelogs). Use it after [`android-build`](../android-build).

## Requirements (read me first)

| What you need | Details |
|---|---|
| **Runner** | Any (no Docker). Ruby is needed — either already on the runner, or set `setup-ruby: true` to install it. Fastlane is auto-installed if missing. |
| **Run before this** | A signed `.aab` — typically [`android-build`](../android-build). |
| **Secrets / credentials** | A **Google Play service-account JSON** (base64 in `service-account-json-base64`, or plaintext in `service-account-json`). |
| **In your Google Play account (one-time, you do this)** | 1) Create the app in the Play Console. 2) Create a service account in Google Cloud, download its JSON key, and **grant it access** in Play Console → Users & permissions (at least "Release to testing tracks"). 3) The app's **very first** production release must be created by hand — the API can't seed a brand-new listing. |

## Usage

```yaml
- id: build
  uses: vymalo/flutter-tools/actions/android-build@v0
  with: { /* signing inputs */ }

- uses: vymalo/flutter-tools/actions/play-submit@v0
  with:
    aab: ${{ steps.build.outputs.aab-path }}
    package-name: com.example.app
    track: internal
    service-account-json-base64: ${{ secrets.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64 }}
```

## Inputs (most-used)

| Input | Required | Default | What it does |
|---|---|---|---|
| `aab` | **yes** | — | Path to the `.aab`. |
| `package-name` | **yes** | — | Application id, e.g. `com.example.app`. |
| `service-account-json-base64` | yes* | — | base64 of the service-account JSON (*or use `service-account-json`). |
| `track` | no | `internal` | `internal` / `alpha` / `beta` / `production` / custom. |
| `release-status` | no | `completed` | `completed` / `draft` / `halted` / `inProgress`. |
| `rollout` | no | — | Staged-rollout fraction (e.g. `0.1`) — for `inProgress`/`halted`. |
| `setup-ruby` | no | `false` | Install Ruby first (leave off if the runner has it). |

> **Production with staged rollout:** `track: production`, `release-status: inProgress`,
> `rollout: 0.1` (10%). Bump the fraction later, or `completed` for 100%.
