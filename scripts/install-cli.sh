#!/usr/bin/env bash
# Download the prebuilt vymalo flutter-tools CLI for this runner's OS/arch from
# the matching GitHub release, verify its SHA-256, and expose it.
#
# This replaces the per-run `dart pub get` + `dart run` dance: the AOT binary is
# self-contained (no Dart SDK on the runner, no dependency resolution), so a step
# that uses it pays a single small download instead of a full pub resolve.
#
# It writes the binary path to stdout, to $GITHUB_OUTPUT (cli=<path>), and
# prepends its directory to $GITHUB_PATH so later steps can call `flutter-tools`
# directly.
#
# Usage: install-cli.sh [version]   # version defaults to repo-root cli-version.txt
set -euo pipefail

REPO="vymalo/flutter-tools"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

version="${1:-${CLI_VERSION:-}}"
if [ -z "$version" ]; then
  version="$(tr -d ' \t\n\r' < "$repo_root/cli-version.txt")"
fi

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

dest_dir="${RUNNER_TEMP:-/tmp}/vymalo-flutter-tools"
mkdir -p "$dest_dir"
bin="$dest_dir/flutter-tools"

curl --fail --silent --show-error --location --retry 3 -o "$bin" "$base/$asset"
curl --fail --silent --show-error --location --retry 3 -o "$dest_dir/SHA256SUMS" "$base/SHA256SUMS"

expected="$(awk -v f="$asset" '$2 == f {print $1}' "$dest_dir/SHA256SUMS")"
if [ -z "$expected" ]; then
  echo "::error::no checksum for $asset in $tag SHA256SUMS" >&2
  exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$bin" | awk '{print $1}')"
else
  actual="$(shasum -a 256 "$bin" | awk '{print $1}')"
fi
if [ "$expected" != "$actual" ]; then
  echo "::error::checksum mismatch for $asset (expected $expected, got $actual)" >&2
  exit 1
fi

chmod +x "$bin"
# Defensive: drop any Gatekeeper quarantine flag on macOS runners (curl usually
# doesn't set it, but this guarantees the unsigned binary is runnable).
[ "$os_slug" = macos ] && xattr -d com.apple.quarantine "$bin" 2>/dev/null || true

echo "$bin"
[ -n "${GITHUB_OUTPUT:-}" ] && echo "cli=$bin" >>"$GITHUB_OUTPUT"
[ -n "${GITHUB_PATH:-}" ] && echo "$dest_dir" >>"$GITHUB_PATH"
exit 0
