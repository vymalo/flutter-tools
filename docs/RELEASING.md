# Releasing flutter-tools

How to ship a new version. Everything is driven from the **Actions tab**
(`workflow_dispatch`) — no local `git tag` or push.

## The two artifacts

flutter-tools ships **two independently-versioned things**. Keep them straight:

| Artifact | What it is | Versioned by | Cut by |
|---|---|---|---|
| **CLI binary** | The compiled `flutter-tools` executable the actions download at runtime (per OS/arch). | [`cli-version.txt`](../cli-version.txt) → `cli-v<version>` GitHub Release | `release-cli` workflow |
| **Action version** | The `vX.Y.Z` tag (and moving `v0`) that consumers reference as `…/actions/<name>@v0`. | git tags | `release-actions` workflow |

**The link between them:** every action calls
[`scripts/install-cli.sh`](../scripts/install-cli.sh), which reads
`cli-version.txt` **from the checked-out action ref** and downloads the matching
`cli-v<version>` release. So an action tag and the binary it pulls are bound by
whatever `cli-version.txt` said at that commit. That binding is the reason
ordering matters (below).

## Decision: what do I need to run?

| What changed | Bump `cli-version.txt`? | Run `release-cli`? | Run `release-actions`? |
|---|---|---|---|
| Dart code (`lib/`, `bin/`) | **Yes** | **Yes** | Yes |
| Action YAML, scripts, docs, workflows only | No | No | Yes |
| Nothing shippable (tests, internal docs) | No | No | No |

> **Bumping `cli-version.txt` and running `release-cli` are a pair.** If you bump
> it without publishing the matching binary, every `@v0` consumer 404s on the
> download. If you change Dart code without bumping it, you'd have to *overwrite*
> an existing immutable `cli-v*` release — don't; bump instead.

## Flow A — you changed the Dart CLI (most common)

1. **Bump the binary version.** Edit [`cli-version.txt`](../cli-version.txt)
   (e.g. `0.1.0` → `0.2.0`). Open a PR with your code change, get it green, merge
   to `main`.
2. **Publish the binary.** Actions tab → **release-cli** → **Run workflow** (from
   `main`). It compiles for `linux-x64`, `linux-arm64`, `macos-arm64` and creates
   the `cli-v0.2.0` Release + `SHA256SUMS`. Wait for it to finish.
3. **Cut the action version.** Actions tab → **release-actions** → **Run
   workflow**: `version = 0.7.0`, `move_major = true`. It tags `v0.7.0` at `main`
   and advances `v0` → `main`.

The instant `v0` moves, `@v0` consumers resolve to the new actions, whose
`cli-version.txt` is `0.2.0`, whose binary (step 2) exists. ✅

**Order is load-bearing:** run `release-cli` **before** `release-actions`. If you
move `v0` first, `@v0` consumers briefly point at actions that want a binary that
isn't published yet.

## Flow B — you only changed action YAML / scripts / docs

No new binary needed (the current `cli-v*` release still matches). Just:

- Actions tab → **release-actions** → **Run workflow**: `version = <next>`,
  `move_major = true`.

## Versioning conventions

- **Action tags** are `v0.x` while the project is pre-1.0; `v0` is the moving
  major most consumers pin. Bump the **minor** for features, **patch** for fixes.
  `release-actions` refuses to overwrite an existing `vX.Y.Z`.
- **Binary** `cli-vX.Y.Z` just needs to be a fresh, unique version each time the
  Dart code changes so each release stays immutable. Simplest is to move it in
  lockstep with the action minor, but they need not match.
- The two numbers are **independent** — `cli-version.txt` is the only thing that
  must be internally consistent.

## Verify

After a release, confirm a real consumer picks it up. In a repo that pins `@v0`
(e.g. vymalo-shop), trigger a workflow and check the logs:

- A migrated action shows an **`install-cli.sh`** step that downloads + checksums
  the binary into a `…/_temp/vymalo-flutter-tools.XXXX/flutter-tools` path, then
  execs it — **no `dart pub get`**.
- The run is green on each runner OS/arch you target (the published assets must
  cover them: `linux-x64`/`linux-arm64`/`macos-arm64` today).

## Roll back

- **Bad action release:** re-run **release-actions** with `version` pointing at a
  known-good commit, or repoint `v0` to the previous tag. `@v0` consumers recover
  with no change on their side.
- **Bad binary:** bump `cli-version.txt` to a new version, fix, and re-run
  **release-cli** + **release-actions**. Don't overwrite a published `cli-v*`
  (consumers on older action refs may still pull it).

## Gotchas

- **Self-hosted runners need egress** to `objects.githubusercontent.com` for the
  binary download. (They already needed network for `dart pub get`, so this is
  usually a non-issue — but it's the first thing to check if a download fails.)
- **Moving `v0` affects every `@v0` consumer**, not just one repo. It's instantly
  reversible, but coordinate if several repos pin `@v0`.
- **New runner arch?** Add a matrix leg in
  [`.github/workflows/release-cli.yml`](../.github/workflows/release-cli.yml)
  (`dart compile exe` can't cross-compile) and re-release, or
  `install-cli.sh` will 404 for that OS/arch.
