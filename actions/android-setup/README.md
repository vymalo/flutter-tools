# `android-setup` action

One step that makes an **Android job build-ready**: installs Flutter + Java (and
optionally Ruby for Fastlane), then runs your codegen. Put it right after
`checkout`, before [`android-build`](../android-build).

## Requirements (read me first)

| What you need | Details |
|---|---|
| **Runner** | Linux (GitHub-hosted `ubuntu-latest` or self-hosted). macOS works too. |
| **Run before this** | `actions/checkout`. |
| **Secrets** | None. |
| **In your repo** | Only if `run-codegen: true` (the default): the OpenAPI codegen layout — see [`codegen`](../codegen). No codegen? set `run-codegen: false`. |

## Usage

```yaml
- uses: actions/checkout@v4
- uses: vymalo/flutter-tools/actions/android-setup@v0
  with:
    flutter-version: '3.44.2'
    run-codegen: true        # set false if you have no OpenAPI codegen
    setup-ruby: false        # set true only if a later step needs Fastlane
```

## Inputs (most-used)

| Input | Required | Default | What it does |
|---|---|---|---|
| `flutter-version` | no | `3.44.2` | Flutter SDK version. |
| `java-version` | no | `21` | Temurin JDK (for the OpenAPI Generator). |
| `run-codegen` | no | `true` | Run the layered codegen after setup. |
| `setup-ruby` | no | `false` | Also install Ruby + Bundler (needed only for Fastlane steps like `play-submit` with `setup-ruby`). |
| `project-dir` | no | `mobile` | Your Flutter app directory. |

See [`action.yml`](action.yml) for the full list (codegen dirs, channels, versions).
