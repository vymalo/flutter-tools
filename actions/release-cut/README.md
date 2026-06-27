# `release-cut` action

Cuts a release with **no PR-create permission and no Personal Access Token**. It
reads your conventional-commit history, computes the next semver, **tags** it, and
creates a **GitHub Release** with auto-generated notes. Needs only the default
`contents: write` permission.

## Requirements (read me first)

| What you need | Details |
|---|---|
| **Runner** | Any with **Dart on PATH** — run a Flutter/Dart setup first (this repo's [`android-setup`](../android-setup) / [`ios-setup`](../ios-setup), or `subosito/flutter-action`). |
| **Run before this** | **`actions/checkout` with `fetch-depth: 0`** — the version is computed from tags + full history. A shallow clone is rejected loudly (it would silently mis-baseline). |
| **Workflow permissions** | `permissions: { contents: write }`. No PAT, no PR-create permission. |
| **Secrets** | None beyond the built-in `GITHUB_TOKEN`. |

> **Heads-up about chained builds:** a tag created with `GITHUB_TOKEN` does **not**
> trigger other `push:`/`tag:` workflows. If you want to build the freshly-cut tag,
> call your build job from the **same** workflow run (see vymalo-shop's
> `mobile-release-cut.yml`).

## How the version is chosen

Baseline = the latest `<tag-prefix>*` tag (or your `pubspec.yaml` for the first
release). Then `bump`:

- `auto` (default) — scan commit subjects since that tag: `feat:` → **minor**,
  `fix:` → **patch**, `!`/`BREAKING CHANGE` → **major** (nothing matching → patch).
- or force `patch` / `minor` / `major`.

## Usage

```yaml
permissions:
  contents: write
jobs:
  cut:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }      # required
      - uses: vymalo/flutter-tools/actions/android-setup@v0   # puts Dart on PATH
      - id: cut
        uses: vymalo/flutter-tools/actions/release-cut@v0
        with:
          tag-prefix: app-v
          bump: auto
          title-prefix: MyApp
      - run: echo "Cut ${{ steps.cut.outputs.tag }}"
```

## Inputs

| Input | Required | Default | What it does |
|---|---|---|---|
| `tag-prefix` | no | `mobile-v` | Tag namespace → `<prefix>1.2.3`. |
| `bump` | no | `auto` | `auto` / `patch` / `minor` / `major`. |
| `title-prefix` | no | `Mobile` | Release title → `<prefix> x.y.z`. |
| `project-dir` | no | `mobile` | Scopes the commit scan + pubspec fallback. |
| `target` | no | `github.sha` | Commitish to tag. |

## Outputs

| Output | Example | What |
|---|---|---|
| `version` | `1.4.0` | The cut marketing version. |
| `tag` | `app-v1.4.0` | The created tag. |
| `bump` | `minor` | The level applied. |
