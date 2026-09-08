#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/flutter-tools-installer-test.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin" "$test_tmp/standalone/scripts" "$test_tmp/runner"
cp "$repo_root/scripts/install-cli.sh" "$test_tmp/standalone/scripts/install-cli.sh"

# Simulate a server whose first streamed response is partial. The old
# `curl --retry-all-errors | ...` implementation consumed both response bodies;
# the fixed installer must always pass -o and consume only the completed file.
cat > "$test_tmp/bin/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -euo pipefail

output=
url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o | --output)
      output="$2"
      shift 2
      ;;
    http://* | https://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ -z "$output" ]; then
  printf '0.2.0.2.1\n'
  exit 0
fi

case "$url" in
  */cli-version.txt)
    printf '0.2.1\n' > "$output"
    ;;
  */cli-v0.2.1/flutter-tools-linux-x64)
    printf '#!/usr/bin/env bash\nexit 0\n' > "$output"
    ;;
  */cli-v0.2.1/SHA256SUMS)
    if command -v sha256sum >/dev/null 2>&1; then
      hash="$(printf '#!/usr/bin/env bash\nexit 0\n' | sha256sum | awk '{print $1}')"
    else
      hash="$(printf '#!/usr/bin/env bash\nexit 0\n' | shasum -a 256 | awk '{print $1}')"
    fi
    printf '%s  flutter-tools-linux-x64\n' "$hash" > "$output"
    ;;
  *)
    echo "unexpected URL: $url" >&2
    exit 22
    ;;
esac
MOCK_CURL
chmod +x "$test_tmp/bin/curl"

github_output="$test_tmp/github-output"
github_path="$test_tmp/github-path"
PATH="$test_tmp/bin:$PATH" \
FT_REF=test-ref \
RUNNER_OS=Linux \
RUNNER_ARCH=X64 \
RUNNER_TEMP="$test_tmp/runner" \
GITHUB_OUTPUT="$github_output" \
GITHUB_PATH="$github_path" \
  bash "$test_tmp/standalone/scripts/install-cli.sh" > "$test_tmp/stdout"

installed="$(tail -n 1 "$test_tmp/stdout")"
test -x "$installed"
grep -Fx "cli=$installed" "$github_output" >/dev/null
grep -Fx "$(dirname "$installed")" "$github_path" >/dev/null

if grep -R -n -E 'curl .*\|[[:space:]]*bash|\|[[:space:]]*bash -s' "$repo_root/actions"; then
  echo "composite actions must download retried installers before executing them" >&2
  exit 1
fi

fallback_count="$(grep -R -l 'remote_installer="$(mktemp)"' "$repo_root/actions"/*/action.yml | wc -l | tr -d ' ')"
test "$fallback_count" = 13

echo "install-cli bootstrap tests passed"
