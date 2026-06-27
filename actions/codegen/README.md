# `codegen` action

Runs your Flutter project's **code generation** in one step: OpenAPI client →
generated `*.g.dart` → app `build_runner` (riverpod / drift / go_router).

## Requirements (read me first)

| What you need | Details |
|---|---|
| **Runner** | Any — Linux or macOS, GitHub-hosted or self-hosted. |
| **Run before this** | `actions/checkout` (so your code is on disk). That's it — this action sets up Flutter + Java for you (toggle off with `setup-flutter: false` / `setup-java: false` if an earlier step already did). |
| **Secrets** | None. |
| **In your repo** | A layered codegen layout: a Flutter app dir, a generated-client package dir, and a "tool" dir whose `build_runner` drives the OpenAPI Generator. Point the `*-dir` inputs at yours. If you don't use OpenAPI, you probably want the plain `dart run build_runner build` instead of this action. |

> **Defaults assume `mobile/`.** If your app lives at the repo root or elsewhere,
> set `project-dir`, `api-dir`, and `codegen-tool-dir` accordingly.

## Usage

```yaml
- uses: actions/checkout@v4
- uses: vymalo/flutter-tools/actions/codegen@v0
  with:
    project-dir: mobile
    api-dir: mobile/api
    codegen-tool-dir: mobile/tool/openapi_codegen
    flutter-version: '3.44.2'
```

## Inputs (most-used)

| Input | Required | Default | What it does |
|---|---|---|---|
| `project-dir` | no | `mobile` | Your Flutter app directory. |
| `api-dir` | no | `mobile/api` | The generated OpenAPI client package. |
| `codegen-tool-dir` | no | `mobile/tool/openapi_codegen` | Dir whose `build_runner` runs the OpenAPI Generator. |
| `clean` | no | `true` | `build_runner clean` + drop `pubspec.lock` first (avoids stale `*.g.dart`). |
| `setup-flutter` / `setup-java` | no | `true` | Let this action install the toolchain. Set `false` if a prior step did. |
| `flutter-version` / `java-version` | no | `3.44.2` / `21` | Versions used when the setups run. |

See [`action.yml`](action.yml) for the full list.
