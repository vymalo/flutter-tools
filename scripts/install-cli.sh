#!/usr/bin/env bash
# Download the prebuilt vymalo flutter-tools CLI for this runner's OS/arch from
# the matching GitHub release, verify its SHA-256, and expose it.
#
# This replaces the per-run `dart pub get` + `dart run` dance: the AOT binary is
# self-contained (no Dart SDK on the runner, no dependency resolution). The first
# action in a job downloads it; later actions reuse it from a job-scoped cache, so
# a multi-action job pays for the download once.
#
# It writes the binary path to stdout, to $GITHUB_OUTPUT (cli=<path>), and
# prepends its directory to $GITHUB_PATH so later steps can call `flutter-tools`
# directly.
#
# Usage: install-cli.sh [version]   # version defaults to repo-root cli-version.txt
set -euo pipefail

REPO="vymalo/flutter-tools"

# When piped from stdin (curl | bash) there is no on-disk checkout, so BASH_SOURCE
# is unreliable — fall back to "." and guard every repo-relative read below.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo .)"
repo_root="$(cd "$script_dir/.." 2>/dev/null && pwd || echo .)"

# Last-resort version when neither an arg, CLI_VERSION, an on-disk cli-version.txt,
# nor FT_REF is available. Keep in sync with cli-version.txt.
DEFAULT_CLI_VERSION="0.3.0"

# Version precedence: explicit arg / CLI_VERSION → on-disk cli-version.txt (normal
# checkout) → cli-version.txt fetched from the action ref (FT_REF set by the
# calling action = github.action_ref) → baked default.
version="${1:-${CLI_VERSION:-}}"
version_source="the script argument"
[ -n "${1:-}" ] || version_source="the CLI_VERSION environment variable"
if [ -z "$version" ]; then
  if [ -f "$repo_root/cli-version.txt" ]; then
    version="$(tr -d ' \t\n\r' < "$repo_root/cli-version.txt")"
    version_source="cli-version.txt in the checkout at $repo_root"
  elif [ -n "${FT_REF:-}" ]; then
    version_file="$(mktemp "${TMPDIR:-/tmp}/vymalo-flutter-tools-version.XXXXXX")"
    trap 'rm -f "${version_file:-}"' EXIT
    curl --fail --silent --show-error --location --retry 3 --retry-all-errors \
      -o "$version_file" \
      "https://raw.githubusercontent.com/${REPO}/${FT_REF}/cli-version.txt"
    version="$(tr -d ' \t\n\r' < "$version_file")"
    rm -f "$version_file"
    version_file=
    version_source="cli-version.txt at actions ref ${FT_REF}"
  else
    version="$DEFAULT_CLI_VERSION"
    version_source="this script's built-in default"
  fi
fi
# Tolerate a leading `cli-v` / `v` so `v0.1.0` or `cli-v0.1.0` also resolve.
version="${version#cli-v}"
version="${version#v}"

os="${RUNNER_OS:-$(uname -s)}"
arch="${RUNNER_ARCH:-$(uname -m)}"
case "$os" in
  Linux) os_slug=linux ;;
  macOS | Darwin) os_slug=macos ;;
  *)
    echo "::error::unsupported OS '$os' for the prebuilt flutter-tools CLI" >&2
    exit 1
    ;;
esac
case "$arch" in
  X64 | x86_64 | amd64) arch_slug=x64 ;;
  ARM64 | arm64 | aarch64) arch_slug=arm64 ;;
  *)
    echo "::error::unsupported arch '$arch' for the prebuilt flutter-tools CLI" >&2
    exit 1
    ;;
esac

asset="flutter-tools-${os_slug}-${arch_slug}"
tag="cli-v${version}"
base="https://github.com/${REPO}/releases/download/${tag}"

# Job-scoped cache. RUNNER_TEMP is unique per job and is NOT shared by concurrent
# jobs on a runner, so a binary an earlier step already fetched can be reused
# safely within the same job — turning N downloads (one per action) into one.
# Keyed by asset+version so a stale binary is never reused. Outside Actions
# (no RUNNER_TEMP) fall back to a fresh mktemp dir: no cross-step reuse, but
# collision-safe (a static /tmp path could be hijacked on a shared host).
key="${asset}-${version}"
if [ -n "${RUNNER_TEMP:-}" ]; then
  bin_dir="$RUNNER_TEMP/vymalo-flutter-tools/$key"
else
  bin_dir="$(mktemp -d "${TMPDIR:-/tmp}/vymalo-flutter-tools.XXXXXX")/$key"
fi
mkdir -p "$bin_dir"
chmod 700 "$bin_dir"  # owner-only, matching the mktemp fallback's 0700
bin="$bin_dir/flutter-tools"

if [ -x "$bin" ]; then
  # Already fetched + verified by an earlier step in this job — skip the network.
  echo "Reusing flutter-tools $tag from this job's cache ($bin)" >&2
else
  tmp="$(mktemp "$bin_dir/.download.XXXXXX")"
  sums="$(mktemp "$bin_dir/.sha256sums.XXXXXX")"
  # Every actions tag pins the CLI release named in its cli-version.txt, so a tag only
  # works while that exact cli-v* release stays published. When it does not, say which
  # release, which ref pinned it, and what to do - a bare `curl: (22) 404` cost a
  # downstream repo most of a night on 2026-09-09 (v0.11.0 -> cli-v0.2.0, gone).
  fetch_release_file() {
    local url="$1" dest="$2" code
    code="$(curl --silent --show-error --location --retry 3 --retry-all-errors -o "$dest" -w '%{http_code}' "$url")" || code="000"
    if [ "$code" != "200" ]; then
      rm -f "$dest"
      echo "::error::flutter-tools CLI release ${tag} has no downloadable $(basename "$url") (HTTP ${code} from ${url})." >&2
      echo "CLI version ${version} came from ${version_source}. Published CLI releases: https://github.com/${REPO}/releases. Either set CLI_VERSION to a published cli-v* version, or use an actions tag whose cli-version.txt names one - and never retire a cli-v* release that a tagged action still pins." >&2
      exit 1
    fi
  }
  fetch_release_file "$base/$asset" "$tmp"
  fetch_release_file "$base/SHA256SUMS" "$sums"

  expected="$(awk -v f="$asset" '{sub(/\r$/, "", $2); sub(/^\*/, "", $2); if ($2 == f) print $1}' "$sums")"
  if [ -z "$expected" ]; then
    echo "::error::no checksum for $asset in $tag SHA256SUMS" >&2
    exit 1
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$tmp" | awk '{print $1}')"
  else
    actual="$(shasum -a 256 "$tmp" | awk '{print $1}')"
  fi
  if [ "$expected" != "$actual" ]; then
    echo "::error::checksum mismatch for $asset (expected $expected, got $actual)" >&2
    exit 1
  fi

  chmod +x "$tmp"
  # Defensive: drop any Gatekeeper quarantine flag on macOS runners (curl usually
  # doesn't set it, but this guarantees the unsigned binary is runnable).
  [ "$os_slug" = macos ] && xattr -d com.apple.quarantine "$tmp" 2>/dev/null || true

  # Publish atomically: $bin only appears once fully downloaded + verified, so a
  # failed/partial download is never mistaken for a cache hit by a later step.
  mv -f "$tmp" "$bin"
  rm -f "$sums"
  echo "Downloaded flutter-tools $tag ($asset) -> $bin" >&2
fi

echo "$bin"
[ -n "${GITHUB_OUTPUT:-}" ] && echo "cli=$bin" >>"$GITHUB_OUTPUT"
[ -n "${GITHUB_PATH:-}" ] && echo "$bin_dir" >>"$GITHUB_PATH"
exit 0
