# `version-stamp` action

Writes a **build number** (and optionally a marketing version) into your
`pubspec.yaml` so every CI build gets a unique, increasing
`version: x.y.z+<build>` — which becomes the Android `versionCode` and iOS
`CFBundleVersion`. Stores reject re-used build numbers, so you generally want this
before any build.

## Requirements (read me first)

| What you need | Details |
|---|---|
| **Runner** | Any — Linux or macOS. |
| **Run before this** | `actions/checkout`. (No Flutter setup needed — it just edits the file.) |
| **Secrets** | None. |
| **In your repo** | A `pubspec.yaml` under `project-dir` (default `mobile/`). |

> By default the build number is the **CI run number** (`github.run_number`),
> which always increases. Override with `build-number` if you track it elsewhere.

## Usage

```yaml
- uses: actions/checkout@v4
- id: ver
  uses: vymalo/flutter-tools/actions/version-stamp@v0
  with:
    project-dir: mobile
    # build-number defaults to the CI run number
    # version: 1.4.0    # optional — pin the marketing version (e.g. from a git tag)
- run: echo "Built ${{ steps.ver.outputs.full-version }}"
```

## Inputs

| Input | Required | Default | What it does |
|---|---|---|---|
| `project-dir` | no | `mobile` | Folder holding `pubspec.yaml`. |
| `build-number` | no | CI run number | The `+build` value to stamp. |
| `version` | no | _(keep existing)_ | Marketing `x.y.z` to set. Blank = keep pubspec's, only re-stamp `+build`. |

## Outputs

| Output | Example | What |
|---|---|---|
| `version` | `1.4.0` | The marketing version. |
| `build-number` | `271` | The stamped build. |
| `full-version` | `1.4.0+271` | Combined — handy for logs/release names. |
