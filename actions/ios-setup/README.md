# `ios-setup` action

One step that makes an **iOS job build-ready**: installs Flutter + Java, runs your
codegen, sets up Bundler, and runs `pod install`. Put it after `checkout`, before
[`ios-build`](../ios-build).

## Requirements (read me first)

| What you need | Details |
|---|---|
| **Runner** | **macOS with Xcode** — required (CocoaPods + the iOS toolchain). GitHub's `macos-latest` or a self-hosted Mac. |
| **Run before this** | `actions/checkout`. |
| **Secrets** | None (signing secrets come later, in `ios-build`). |
| **In your repo** | A `Gemfile` (for Fastlane/CocoaPods via Bundler) and `ios/Podfile`. If `run-codegen: true` (default), also the OpenAPI codegen layout — see [`codegen`](../codegen). |

## Usage

```yaml
- uses: actions/checkout@v4
- uses: vymalo/flutter-tools/actions/ios-setup@v0
  with:
    flutter-version: '3.44.2'
    project-dir: mobile
```

## Inputs (most-used)

| Input | Required | Default | What it does |
|---|---|---|---|
| `flutter-version` | no | `3.44.2` | Flutter SDK version. |
| `pod-install` | no | `true` | Run `pod install` in `ios/`. |
| `run-codegen` | no | `true` | Run the layered codegen after setup. |
| `api-pubspec-template` | no | `mobile/tool/api-pubspec.template.yaml` | Restores the generated-API `pubspec.yaml` on runners where it's gitignored. |

See [`action.yml`](action.yml) for the full list.
