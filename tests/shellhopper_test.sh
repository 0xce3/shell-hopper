#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
loader="$repo_root/scripts/shellhopper.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

[[ -f "$loader" ]] || fail "shellhopper.sh exists"
bash -n "$loader"

grep -q 'LASTEXITCODE' "$repo_root/install.ps1" || fail "install.ps1 checks WSL exit codes"
if grep -q 'docker.io' "$repo_root/install.ps1"; then
  fail "install.ps1 must not install docker.io"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

config="$tmp_dir/projects.tsv"
cat >"$config" <<'CONFIG'
# name	kind	target	workspace	command
local-tools	wsl	-	/home/user/src/tools	nvim
container-tools	container	tools-dev	/workspaces/tools	nvim
CONFIG

output="$("$loader" --config "$config" --dry-run)"
assert_contains "$output" "local-tools"
assert_contains "$output" "container-tools"
assert_contains "$output" "docker unavailable"

help_output="$("$loader" --help)"
assert_contains "$help_output" "Project config format"

printf 'shellhopper_test.sh: ok\n'
