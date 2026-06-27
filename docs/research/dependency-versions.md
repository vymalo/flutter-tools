# Dependency Version Research — flutter-tools

**Original research:** 2025-06-25 · **Reconciled against the repo:** 2026-06-27
**Repo:** `vymalo/flutter-tools`

This document inventories every tool, SDK, GitHub Action, and Dart package the
repository uses, states the **currently pinned** version (verified against the
actual `pubspec.yaml` / `action.yml` / `ci.yml`), the latest stable available, and
an upgrade recommendation. Most upgrades the first draft recommended have since
been applied — this revision corrects the pinned column to reality.

---

## Summary Table

| Dependency | Pinned | Latest Stable | Gap | Upgrade? |
|---|---|---|---|---|
| Dart SDK (pubspec constraint) | `>=3.12.0 <4.0.0` | 3.12.2 | Current | No |
| Flutter SDK (action default) | `3.44.2` | 3.44.4 | 2 patches | Optional |
| `args` (Dart package) | `^2.5.0` | 2.7.0 | caret already resolves 2.7.0 | No |
| `lints` (Dart package) | `^6.0.0` | 6.1.0 | caret already resolves 6.1.0 | No |
| `test` (Dart package) | `^1.25.0` | 1.31.2 | caret already resolves 1.31.2 | No |
| `actions/checkout` (ci.yml + examples) | `@v7` | v7.0.0 | Current | No (done) |
| `dart-lang/setup-dart` (ci.yml) | `@v1` | v1.7.2 | `@v1` tracks latest | No |
| `actions/upload-artifact` | `@v7` | v7.0.1 | Current | No |
| `subosito/flutter-action` | `@v2` | v2.23.0 | `@v2` tracks latest | No |
| `actions/setup-java` | `@v5` | v5.4.0 | Current | No |
| `ruby/setup-ruby` | `@v1` | v1.314.0 | `@v1` tracks latest | No |
| `actions/cache` | `@v6` | v6.1.0 | Current | No |
| `softprops/action-gh-release` (release-cut) | `@v3` | v3.0.1 | Current | No (done) |
| `unfor19/install-aws-cli-action` | `@v1` | v1 (1.0.8) | Current | No |
| Ruby (action default) | `3.4` | 4.0.5 | 2 major | Optional |
| Java / Temurin (action default) | `21` | 21 LTS / 25 LTS | Current LTS | No |
| Fastlane | `gem install` (unpinned) | latest gem | n/a | Pin a version |
| AWS CLI | via action / brew | v2 latest | n/a | No |

> **Caret note:** `^2.5.0` means `>=2.5.0 <3.0.0`, so the lockfile already resolves
> to the latest 2.x. The Dart packages below don't need a *pin* bump to get current
> minors — only raise the floor if you want to *require* a newer minimum.

---

## 1. Dart SDK

| | |
|---|---|
| **Pinned** | `sdk: ">=3.12.0 <4.0.0"` (pubspec.yaml line 11) |
| **Latest stable** | **3.12.2** |
| **Gap** | None — floor already at 3.12.0 |

**No change needed.** The floor already matches the `sdk-floor` default
(`>=3.12.0`) used by the codegen action, and `<4.0.0` remains correct.

---

## 2. Flutter SDK

| | |
|---|---|
| **Pinned** | `3.44.2` (default in `android-setup`, `codegen`, `ios-setup`) |
| **Latest stable** | **3.44.4** (same minor, 2 patches ahead) |

**Optional.** `3.44.2` is current-enough and consumers pin `flutter-version`
explicitly. Bump the default to `3.44.4` opportunistically, or use
`flutter-version-file` (read from pubspec) to centralize it.

---

## 3. Dart Package Dependencies

### 3.1 `args` — pinned `^2.5.0`, latest **2.7.0**
The caret already resolves 2.7.0 (no breaking changes 2.5→2.7). No change needed;
optionally raise the floor to `^2.7.0` if a 2.6+ API is required.

### 3.2 `lints` (dev) — pinned `^6.0.0`, latest **6.1.0**
Already on the current major (the first draft's `^4.0.0` is stale). `^6.0.0`
resolves 6.1.0. No change needed.

### 3.3 `test` (dev) — pinned `^1.25.0`, latest **1.31.2**
The caret already resolves 1.31.2 (no breaking changes in 1.x). No change needed;
optionally raise the floor to pick up `--coverage-path` etc. as a hard minimum.

---

## 4. GitHub Actions

### 4.1 `actions/checkout`
| | |
|---|---|
| **Pinned** | `@v7` (ci.yml + the README examples) |
| **Latest** | **v7.0.0** |

v7 adds fork-PR checkout hardening for `pull_request_target` / `workflow_run` and
requires runner ≥ v2.329.0. **Bumped** — flutter-tools' own CI is GitHub-hosted, so v7 is safe there.

### 4.2 `dart-lang/setup-dart` — pinned `@v1` (ci.yml), latest **v1.7.2**
`@v1` already tracks the latest v1.x (v1.7.2 moved to Node 24 + patched
CVE-2025-22150). No change; pin `@v1.7.2` if you want reproducibility.

### 4.3 `actions/upload-artifact` — pinned `@v7`, latest **v7.0.1**
Already current (the first draft's `@v4` is stale). v7 added direct (`archive:
false`) uploads; defaults stay backward-compatible. No change.

### 4.4 `subosito/flutter-action` — pinned `@v2`, latest **v2.23.0**
`@v2` tracks the latest v2.x. No change; `flutter-version-file` is worth adopting.

### 4.5 `actions/setup-java` — pinned `@v5`, latest **v5.4.0**
Already on the current major (the first draft's `@v4` is stale). v5 runs on Node 24
(runner ≥ v2.327.1). No input changes. No change.

### 4.6 `ruby/setup-ruby` — pinned `@v1`, latest **v1.314.0**
`@v1` tracks the latest v1.x. No change.

### 4.7 `actions/cache` — pinned `@v6`, latest **v6.1.0**
Already on the current major (the first draft's `@v4` is stale). v6 is the ESM /
Node 24 line (runner ≥ v2.327.1). No change.

### 4.8 `softprops/action-gh-release` (used by `release-cut`)
| | |
|---|---|
| **Pinned** | `@v3` (release-cut/action.yml) |
| **Latest** | **v3.0.1** |

**Bumped to `@v3`.** v3.0.0 only moves the runtime from Node 20 to **Node 24** — no
input/behavior changes. Since `release-cut` runs on the **self-hosted arc runner**,
this assumes that fleet provides the Node 24 Actions runtime (≈ runner ≥ v2.327.1) —
the next manual release cut validates it. If it fails with a Node-24 error, revert
release-cut to `@v2` (still maintained as `v2.6.2`) or update the runner image.

### 4.9 `unfor19/install-aws-cli-action` — pinned `@v1`, latest **v1 (1.0.8)**
Current. Used only as a Linux/Windows fallback when `aws` isn't on PATH
(artifact-upload prefers an existing `aws`, then Homebrew on macOS). No change.

---

## 5. Runtime Tool Versions (action defaults)

### 5.1 Ruby — default `3.4`, latest **4.0.5**
The default is `3.4` (the first draft's `3.2` is stale), comfortably pre-EOL and
Fastlane-compatible. Ruby 4.0 may need a Fastlane bump — stay on 3.4 unless tested.
(`ios-setup` deliberately uses system/Homebrew Ruby, not `setup-ruby`.)

### 5.2 Java / Temurin — default `21`, latest LTS **21 / 25**
**Keep 21** — the standard for Flutter/Android (Flutter 3.44 needs Java 17+).
Move to 25 only when Flutter / AGP require it.

### 5.3 Fastlane — **unpinned** (`gem install fastlane --no-document`)
Used by `play-submit`, `testflight-submit`, `app-store-submit`. **Recommendation:
pin** (e.g. `--version '~> 2.230'`, which `play-submit` already does) or move all
submit actions to a `Gemfile` + `bundle install` (as `ios-setup` does) so a
Fastlane release can't break CI unannounced.

---

## 6. Remaining upgrade plan

Most of the first draft's "immediate" upgrades (upload-artifact, setup-java, cache,
lints, the Dart SDK floor) are **already applied**. `checkout@v7` in `ci.yml` (§4.1)
and `action-gh-release@v3` in release-cut (§4.8) are **now done** too. What's left:

1. **Pin Fastlane** in the submit actions (§5.3).
2. *Optional:* bump the Flutter default `3.44.2 → 3.44.4` (§2).
3. *Validate:* the next manual release cut exercises `action-gh-release@v3` on the
   self-hosted arc runner — confirm it's Node-24-capable (§4.8).

---

## 7. Self-hosted runner compatibility

The Node-24 actions (`setup-java@v5`, `cache@v6`, `upload-artifact@v7`,
`setup-dart@v1.7.2`) need **Actions Runner ≥ v2.327.1**; `checkout@v7` needs
**≥ v2.329.0**. The Android/Dart jobs already run these on the self-hosted Linux
runner, so it meets v2.327.1; confirm v2.329.0 before moving `ci.yml` checkout to
v7 there (flutter-tools CI itself is GitHub-hosted, so it's fine). This is also the
gate for `action-gh-release@v3` on the arc runner that runs `release-cut`.

---

*Reconciled 2026-06-27 against the live `pubspec.yaml`, `action.yml`, and `ci.yml`;
latest versions from the GitHub releases API + pub.dev.*
