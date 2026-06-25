# Dependency Version Research — flutter-tools

**Date:** 2025-06-25 (mid-2026)
**Repo:** `vymalo/flutter-tools` at `/Users/selast/dev/vymalo/flutter-tools`

This document inventories every tool, SDK, GitHub Action, and Dart package
used by the repository, states the currently pinned version, researches the
latest stable version available as of mid-2026, notes breaking changes or
security advisories, and gives an upgrade recommendation for each.

---

## Summary Table

| Dependency | Pinned | Latest Stable | Gap | Upgrade? |
|---|---|---|---|---|
| Dart SDK (pubspec constraint) | `>=3.4.0 <4.0.0` | 3.12.2 | 8 minor versions | **Yes** — raise floor |
| Flutter SDK (action default) | `3.44.2` | 3.44.0 (latest major; 3.44.2 is a patch) | Current | No — already current |
| `args` (Dart package) | `^2.5.0` | 2.7.0 | 2 minor | **Yes** |
| `lints` (Dart package) | `^4.0.0` | 6.1.0 | 2 major | **Yes** |
| `test` (Dart package) | `^1.25.0` | 1.31.1 | 6 minor | **Yes** |
| `actions/checkout` | `@v6` | v7.0.0 | 1 major | **Yes** |
| `dart-lang/setup-dart` | `@v1` | v1.7.2 | 7 minor (same major) | **Yes** (minor) |
| `actions/upload-artifact` | `@v4` | v7.0.1 | 3 major | **Yes** |
| `subosito/flutter-action` | `@v2` | v2.23.0 | 23 minor (same major) | **Yes** (minor) |
| `actions/setup-java` | `@v4` | v5.3.0 | 1 major | **Yes** |
| `ruby/setup-ruby` | `@v1` | v1.314.0 | 314 minor (same major) | **Yes** (minor) |
| `actions/cache` | `@v4` | v6.0.0 | 2 major | **Yes** |
| `unfor19/install-aws-cli-action` | `@v1` | v1 (1.0.8) | Current | No |
| Ruby (action default) | `3.2` | 4.0.5 | 2 major | **Yes** (cautiously) |
| Java / Temurin (action default) | `21` | 21 (LTS) / 25 (latest LTS) | Current LTS | Optional — see notes |
| Fastlane | `gem install` (unpinned) | latest gem | n/a | Pin a version |
| AWS CLI | via action / brew | v2 latest | n/a | No action needed |

---

## 1. Dart SDK

| | |
|---|---|
| **Pinned** | `sdk: ">=3.4.0 <4.0.0"` (pubspec.yaml line 11) |
| **Latest stable** | **3.12.2** (dart.dev footer: "reflects Dart 3.12.2") |
| **Gap** | Floor is 8 minor versions behind |

### Breaking changes / advisories

- Dart 3.5+ introduced **digit separators** and **switch expressions** refinements.
- Dart 3.7 added **extension types** (formerly inline classes) — a new language feature.
- Dart 3.12 is the current stable; the `<4.0.0` upper bound is still correct.
- No security advisories specific to the SDK constraint itself.

### Recommendation

**Raise the floor to `>=3.8.0 <4.0.0`** (or `>=3.10.0`) to take advantage of
recent language features and match the `sdk-floor` default of `>=3.12.0` already
used in the codegen action inputs. The upper bound `<4.0.0` remains correct.

---

## 2. Flutter SDK

| | |
|---|---|
| **Pinned** | `3.44.2` (default in `android-setup`, `codegen`, `ios-setup` action inputs) |
| **Latest stable** | **3.44.0** (latest major listed on flutter.dev release notes) |
| **Gap** | None — 3.44.2 is a patch release of the 3.44 stable line |

### Notes

- The Flutter release notes page lists major stable releases (3.44.0, 3.41.0,
  3.38.0, …). Patch releases like 3.44.2 are not listed separately but exist
  in the SDK archive.
- The pinned `3.44.2` is current and appropriate.

### Recommendation

**No change needed.** The pinned version is current. Consider making the
default `'3.x'` or `'any'` to auto-track the latest stable, or keep the exact
pin for reproducibility.

---

## 3. Dart Package Dependencies

### 3.1 `args`

| | |
|---|---|
| **Pinned** | `^2.5.0` (pubspec.yaml line 14) |
| **Latest** | **2.7.0** (pub.dev) |
| **Gap** | 2 minor versions |

#### Breaking changes

- `args` 2.6 and 2.7 are minor releases; no breaking changes from 2.5.
- Added `CommandRunner` improvements and minor API additions.

#### Recommendation

**Upgrade to `^2.7.0`.** No breaking changes; picks up minor improvements.

---

### 3.2 `lints` (dev dependency)

| | |
|---|---|
| **Pinned** | `^4.0.0` (pubspec.yaml line 17) |
| **Latest** | **6.1.0** (pub.dev) |
| **Gap** | 2 major versions |

#### Breaking changes

- `lints` 5.0.0 updated the core and recommended lint sets — some previously
  passing code may trigger new lints.
- `lints` 6.0.0 further updated lint rules; the `recommended` set was expanded.
- These are **analysis-only** changes; they don't affect runtime behavior.
- May require fixing newly-flagged lint issues in the codebase.

#### Recommendation

**Upgrade to `^6.1.0`.** Run `dart analyze` after upgrading and fix any new
lint warnings. This keeps the project aligned with current Dart best practices.

---

### 3.3 `test` (dev dependency)

| | |
|---|---|
| **Pinned** | `^1.25.0` (pubspec.yaml line 18) |
| **Latest** | **1.31.1** (pub.dev) |
| **Gap** | 6 minor versions |

#### Breaking changes

- No breaking changes within the 1.x line. Minor releases add features and
  fix bugs in the test runner.
- 1.31.x added `--coverage-path` for LCOV output and improved the GitHub
  Actions reporter.

#### Recommendation

**Upgrade to `^1.31.0`.** No breaking changes; picks up runner improvements.

---

## 4. GitHub Actions

### 4.1 `actions/checkout`

| | |
|---|---|
| **Pinned** | `@v6` (ci.yml line 22) |
| **Latest** | **v7.0.0** (released 2025-06-18) |
| **Gap** | 1 major version |

#### Breaking changes (v6 → v7)

- **ESM module upgrade**: the action was upgraded to ES modules. This is an
  internal change but requires a minimum Actions Runner version.
- **Fork PR security**: v7 blocks checking out fork PRs for
  `pull_request_target` and `workflow_run` events (security hardening).
- Bumped `js-yaml` from 4.1.0 to 4.2.0, removed `uuid` dependency.
- Requires minimum runner version v2.329.0.

#### Recommendation

**Upgrade to `@v7`.** The security hardening (blocking fork PR checkout for
sensitive events) is valuable. Ensure self-hosted runners are on v2.329.0+.

---

### 4.2 `dart-lang/setup-dart`

| | |
|---|---|
| **Pinned** | `@v1` (ci.yml line 23) |
| **Latest** | **v1.7.2** (released 2025-03-23) |
| **Gap** | 7 minor versions (same major) |

#### Breaking changes / advisories

- v1.7.2: Updated to Node.js 24, fixed Dependabot alerts by bumping `undici`
  to `>=6.24.0`.
- v1.7.1: Rolled `undici` to address **CVE-2025-22150**.
- v1.7.0: Added Flutter SDK install support in publish workflow.
- The `@v1` tag tracks the latest v1.x.x release, so pinning `@v1` already
  gets v1.7.2. No action needed unless you want to pin to an exact version.

#### Recommendation

**No change needed** — `@v1` already resolves to v1.7.2. Consider pinning to
`@v1.7.2` for reproducibility if desired.

---

### 4.3 `actions/upload-artifact`

| | |
|---|---|
| **Pinned** | `@v4` (artifact-upload/action.yml line 61) |
| **Latest** | **v7.0.1** (released 2025-04-10) |
| **Gap** | 3 major versions |

#### Breaking changes (v4 → v5 → v6 → v7)

- **v5.0.0**: Upgraded to Node.js 24 runtime. Requires runner v2.327.1+.
- **v6.0.0**: Node.js 24 by default (was preliminary in v5).
- **v7.0.0**: **ESM module upgrade**. Added **direct file uploads** (new
  `archive` parameter — set to `false` to skip zipping). The `name` parameter
  is ignored when `archive: false`.
- v7.0.1: Bug fixes for direct upload and dependency updates.

#### Recommendation

**Upgrade to `@v7`.** The direct upload feature is useful for large artifacts
(APK/AAB/IPA). Ensure runners are on v2.327.1+. The API is backward-compatible
for existing usage (the `archive` parameter defaults to `true`).

---

### 4.4 `subosito/flutter-action`

| | |
|---|---|
| **Pinned** | `@v2` (android-setup, codegen, ios-setup action.yml) |
| **Latest** | **v2.23.0** (released 2025-03-25) |
| **Gap** | 23 minor versions (same major) |

#### Breaking changes / new features

- v2.23.0: Added **FVM support**, separate `pub-cache` boolean flag, simplified
  zip extraction.
- v2.22.0: Upgraded internal `actions/cache` to v5.
- v2.21.0: Added cache-hit outputs, dynamic `PUB-CACHE-PATH` values.
- v2.15.0: Added `flutter-version-file` option (read Flutter version from
  pubspec.yaml).
- v2.16.0: Added `dry-run` option.
- The `@v2` tag tracks the latest v2.x.x release, so pinning `@v2` already
  gets v2.23.0.

#### Recommendation

**No change needed** — `@v2` already resolves to v2.23.0. Consider pinning to
`@v2.23.0` for reproducibility. The `flutter-version-file` option is worth
adopting to centralize Flutter version management.

---

### 4.5 `actions/setup-java`

| | |
|---|---|
| **Pinned** | `@v4` (android-setup, codegen, ios-setup action.yml) |
| **Latest** | **v5.3.0** (released 2025-06-16) |
| **Gap** | 1 major version |

#### Breaking changes (v4 → v5)

- **v5.0.0**: Upgraded to **Node.js 24** runtime. Requires runner v2.327.1+.
- v5.1.0: Added `.sdkmanrc` file support, Microsoft OpenJDK 25, GraalVM GitHub
  Token support, improved error logging with retry.
- v5.2.0: Upgraded `@actions/cache` to v5, retry on HTTP 522.
- v5.3.0: Added **Alpine Linux** support for Temurin, npm audit vulnerability
  fixes, pagination improvements for Adoptium API.

#### Recommendation

**Upgrade to `@v5`.** Node.js 24 alignment matches the other actions. Ensure
runners are on v2.327.1+. No API changes to inputs/outputs.

---

### 4.6 `ruby/setup-ruby`

| | |
|---|---|
| **Pinned** | `@v1` (android-setup, play-submit action.yml) |
| **Latest** | **v1.314.0** (released 2025-06-20) |
| **Gap** | 314 minor versions (same major) |

#### Breaking changes / advisories

- The `@v1` tag tracks the latest v1.x.x release. No breaking changes within
  v1.x.x — each release adds new Ruby versions or minor fixes.
- v1.314.0: Added `ubuntu-26.04` and `ubuntu-26.04-arm` support.
- v1.310.0: Added Ruby 4.0.5.
- v1.312.0: Use `BUNDLE_LOCKFILE` when detecting lockfile.

#### Recommendation

**No change needed** — `@v1` already resolves to v1.314.0. Consider pinning to
`@v1.314.0` for reproducibility.

---

### 4.7 `actions/cache`

| | |
|---|---|
| **Pinned** | `@v4` (ios-setup/action.yml lines 64, 113) |
| **Latest** | **v6.0.0** (released 2025-06-23) |
| **Gap** | 2 major versions |

#### Breaking changes (v4 → v5 → v6)

- **v5.0.0**: Upgraded to **Node.js 24** runtime. Requires runner v2.327.1+.
- v5.0.3: Bumped `@actions/cache` to v5.0.5 (security fix).
- v5.0.4: Security vulnerability patches.
- **v6.0.0**: **ESM module migration**, updated packages.

#### Recommendation

**Upgrade to `@v6`.** Security patches and Node.js 24 alignment. Ensure
runners are on v2.327.1+.

---

### 4.8 `unfor19/install-aws-cli-action`

| | |
|---|---|
| **Pinned** | `@v1` (artifact-upload/action.yml line 85) |
| **Latest** | **v1** (tag tracks 1.0.8, released 2025-07-18) |
| **Gap** | Current |

#### Notes

- This is a Docker-based action (uses `entrypoint.sh`). It is used only as a
  fallback when `aws` is not already on PATH.
- v1.0.8 added support for new `runner.arch` values and AWS CLI v1.
- The `@v1` tag tracks the latest 1.x.x release.
- **Note**: This action is a Docker action, which means it requires a Docker
  daemon. The README says "No Docker" but this one action is an exception
  (it's only used as a Linux/Windows fallback).

#### Recommendation

**No change needed.** `@v1` is current. Consider whether the Docker
requirement is acceptable for self-hosted runners without Docker (the
artifact-upload action already has a brew fallback for macOS and checks for
`aws` on PATH first).

---

## 5. Runtime Tool Versions (Action Input Defaults)

### 5.1 Ruby

| | |
|---|---|
| **Pinned** | `3.2` (default in android-setup, play-submit) |
| **Latest stable** | **4.0.5** (from ruby/setup-ruby v1.310.0) |
| **Gap** | 2 major versions |

#### Notes

- Ruby 3.2 is still supported but nearing EOL.
- Ruby 4.0 is the latest stable line (4.0.5 available via setup-ruby).
- Fastlane and its dependencies generally support Ruby 3.2+; Ruby 4.0
  compatibility may require updating Fastlane.
- The `ios-setup` action intentionally uses system/Homebrew Ruby and does NOT
  use `ruby/setup-ruby` (documented in its description).

#### Recommendation

**Upgrade the default to `3.4`** (a safe middle ground). Ruby 4.0 may have
compatibility issues with older Fastlane versions. Test before jumping to 4.0.

---

### 5.2 Java / Temurin JDK

| | |
|---|---|
| **Pinned** | `21` (default in android-setup, codegen, ios-setup) |
| **Latest LTS** | Java 21 (current LTS) and Java 25 (newest LTS, Sep 2025) |
| **Gap** | Java 21 is still the current widely-adopted LTS |

#### Notes

- Java 21 is the current LTS and is the standard for Android/Flutter builds.
- Java 25 was released as LTS in September 2025 but adoption is still ramping up.
- `actions/setup-java@v5` added support for Microsoft OpenJDK 25 and Alpine
  Linux Temurin.
- Flutter 3.44.x requires Java 17+; Java 21 is recommended.

#### Recommendation

**Keep Java 21.** It's the current standard for Flutter/Android builds. Consider
Java 25 only when Flutter officially requires it or when the Android Gradle
Plugin supports it.

---

### 5.3 Fastlane

| | |
|---|---|
| **Pinned** | Unpinned (`gem install fastlane --no-document`) |
| **Latest** | Latest gem release (changes frequently) |

#### Notes

- Fastlane is installed via `gem install fastlane --no-document` in
  `play-submit`, `testflight-submit`, `app-store-submit`, and `ios-setup`.
- No version is pinned, so the latest compatible version is always installed.
- This is fragile: a Fastlane release could break CI without warning.

#### Recommendation

**Pin Fastlane to a known-good version**, e.g.:
```bash
gem install fastlane --version '~> 2.225' --no-document
```
Or better, use a `Gemfile` + `bundle install` consistently (the `ios-setup`
action already does this, but the submit actions don't).

---

## 6. CI Workflow (`.github/workflows/ci.yml`)

The CI workflow for the flutter-tools CLI itself uses:

| Action | Pinned | Latest | Upgrade? |
|---|---|---|---|
| `actions/checkout` | `@v6` | `@v7` | **Yes** |
| `dart-lang/setup-dart` | `@v1` | `@v1.7.2` | No (already latest via `@v1`) |

### Recommendation

Update `actions/checkout` from `@v6` to `@v7` in ci.yml. The `dart-lang/setup-dart@v1` reference is already current.

---

## 7. Prioritized Upgrade Plan

### Immediate (security + major gaps)

1. **`actions/checkout` @v6 → @v7** — security hardening for fork PRs
2. **`actions/upload-artifact` @v4 → @v7** — 3 major versions behind, security patches
3. **`actions/setup-java` @v4 → @v5** — Node.js 24, security fixes
4. **`actions/cache` @v4 → @v6** — security patches, ESM migration
5. **`lints` ^4.0.0 → ^6.1.0** — 2 major versions behind, updated lint rules

### Short-term (feature improvements)

6. **`args` ^2.5.0 → ^2.7.0** — minor improvements
7. **`test` ^1.25.0 → ^1.31.0** — runner improvements
8. **Dart SDK floor** `>=3.4.0` → `>=3.10.0` (or `>=3.12.0`) — align with codegen defaults
9. **Ruby default** `3.2` → `3.4` — stay ahead of EOL

### Optional / monitoring

10. **Pin Fastlane version** — prevent surprise breakages
11. **Java 21 → 25** — wait for Flutter/AGP to require it
12. **Pin `subosito/flutter-action` to exact version** — for reproducibility
13. **Pin `dart-lang/setup-dart` to `@v1.7.2`** — for reproducibility

---

## 8. Self-Hosted Runner Compatibility

Several of the upgraded actions require **Actions Runner v2.327.1+**
(Node.js 24 runtime). If the project uses self-hosted runners (the README
mentions this), ensure runners are updated before deploying the upgraded
actions. The `actions/checkout@v7` requires runner v2.329.0+.

| Action | Min Runner Version |
|---|---|
| `actions/checkout@v7` | v2.329.0 |
| `actions/upload-artifact@v7` | v2.327.1 |
| `actions/setup-java@v5` | v2.327.1 |
| `actions/cache@v6` | v2.327.1 |
| `dart-lang/setup-dart@v1.7.2` | v2.327.1 (Node 24) |

---

*Research conducted 2025-06-25 using GitHub release pages, pub.dev, dart.dev,
and docs.flutter.dev.*