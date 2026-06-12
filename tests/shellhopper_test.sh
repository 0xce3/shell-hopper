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
grep -q 'shellhopper.tmp' "$repo_root/install.ps1" || fail "Windows Terminal profile must refresh shellhopper launcher"
grep -q 'Optional package installation failed' "$repo_root/install.ps1" || fail "apt package installation is best effort"
grep -q 'scrollbarState' "$repo_root/install.ps1" || fail "Windows Terminal profiles must hide scrollbars"
grep -q 'PSObject.Properties.Remove("icon")' "$repo_root/install.ps1" || fail "install.ps1 must remove ShellHopper profile icons"
if grep -q 'tmux' "$repo_root/install.ps1"; then
  fail "install.ps1 must not install or configure tmux"
fi
if grep -q 'Remove-Member' "$repo_root/install.ps1"; then
  fail "install.ps1 must not call unavailable Remove-Member cmdlet"
fi
grep -q 'set_terminal_title' "$loader" || fail "shellhopper sets terminal tab title"
grep -q 'COLORTERM=truecolor' "$loader" || fail "container launches must pass truecolor"
grep -q 'wt.exe' "$loader" || fail "shellhopper must open Windows Terminal tabs"
grep -q 'new-tab' "$loader" || fail "shellhopper must create Windows Terminal tabs"
grep -q 'nvim' "$loader" || fail "shellhopper must name the editor tab"
grep -q 'shell' "$loader" || fail "shellhopper must name the shell tab"
grep -q 'register_windows_terminal_profile' "$loader" || fail "selected containers must be registered as Windows Terminal profiles"
grep -q 'SHELLHOPPER_PROFILE_MODE' "$loader" || fail "direct Windows Terminal profiles must launch one tab mode"
grep -q 'scrollbarState' "$loader" || fail "generated Windows Terminal profiles must hide scrollbars"
if grep -q 'tmux' "$loader"; then
  fail "shellhopper.sh must not reference tmux"
fi
if grep -q -- '--sessions' "$loader" || grep -q -- '--kill NAME' "$loader" || grep -q 'kill-session' "$loader"; then
  fail "shellhopper must not expose tmux session management"
fi
grep -q "ShellHopper > " "$loader" || fail "fzf menu must use a clear ShellHopper prompt"
grep -q -- "--preview-window" "$loader" || fail "fzf menu must show entry details"
grep -q 'SHELLHOPPER_ENTRY' "$loader" || fail "shellhopper supports direct entry launch"
if grep -q -- '-n logs' "$loader"; then
  fail "shellhopper must not create an empty logs window"
fi
if grep -qi 'Nerd Font\\|JetBrainsMono\\|ryanoasis\\|SkipFont\\|FontFace' "$repo_root/install.ps1"; then
  fail "install.ps1 must not install or configure fonts"
fi
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
if [[ "$output" == *"tmux"* ]]; then
  fail "environment list must not mention tmux"
fi

wt_launch_output="$("$loader" --config "$config" --dry-run local-tools)"
assert_contains "$wt_launch_output" "wt.exe"
assert_contains "$wt_launch_output" "new-tab"
assert_contains "$wt_launch_output" "local-tools:nvim"
assert_contains "$wt_launch_output" "local-tools:shell"
assert_contains "$wt_launch_output" "cd\\ /home/user/src/tools\\ \\&\\&\\ nvim"
assert_contains "$wt_launch_output" "cd\\ /home/user/src/tools\\ \\&\\&\\ bash"
if [[ "$(grep -o 'new-tab' <<<"$wt_launch_output" | wc -l)" -ne 2 ]]; then
  fail "launch must create exactly two Windows Terminal tabs"
fi

mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/wt.exe" <<'WT'
#!/usr/bin/env bash
printf 'WT argc=%s:' "$#" >> "$WT_CAPTURE"
printf ' [%s]' "$@" >> "$WT_CAPTURE"
printf '\n' >> "$WT_CAPTURE"
WT
chmod +x "$tmp_dir/bin/wt.exe"

wt_capture="$tmp_dir/wt.log"
WT_CAPTURE="$wt_capture" PATH="$tmp_dir/bin:/usr/bin:/bin" "$loader" --config "$config" local-tools >/dev/null
wt_output="$(cat "$wt_capture")"
assert_contains "$wt_output" "[new-tab]"
assert_contains "$wt_output" "[local-tools:nvim]"
assert_contains "$wt_output" "[local-tools:shell]"
if [[ "$(grep -Fo '[new-tab]' <<<"$wt_output" | wc -l)" -ne 2 ]]; then
  fail "wt launch must create exactly two tabs"
fi

wsl_profile_output="$(SHELLHOPPER_REGISTER_PROFILES=1 "$loader" --config "$config" --dry-run local-tools)"
assert_contains "$wsl_profile_output" "register Windows Terminal profile: local-tools [nvim]"
assert_contains "$wsl_profile_output" "register Windows Terminal profile: local-tools [shell]"
assert_contains "$wsl_profile_output" "SHELLHOPPER_PROFILE_MODE=nvim"
assert_contains "$wsl_profile_output" "SHELLHOPPER_PROFILE_MODE=shell"

docker_bin="$tmp_dir/bin"
mkdir -p "$docker_bin"
cat >"$docker_bin/docker" <<'DOCKER'
#!/usr/bin/env bash
case "$1 $2" in
  "ps -a")
    printf 'random_container\tExited (0) 2 hours ago\n'
    ;;
  "inspect -f")
    template="$3"
    case "$template" in
      *'devcontainer.local_folder'*)
        printf '\\\\wsl.localhost\\Ubuntu-22.04\\home\\user\\src\\cool-app\n'
        ;;
      *'com.docker.compose.project'*|*'com.docker.compose.service'*)
        printf '\n'
        ;;
      *'.State.Status'*)
        printf 'exited\n'
        ;;
      *'.Mounts'*)
        printf '/workspaces/cool-app\n'
        ;;
      *)
        printf '\n'
        ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
DOCKER
chmod +x "$docker_bin/docker"

empty_config="$tmp_dir/empty-projects.tsv"
printf '# name\tkind\ttarget\tworkspace\tcommand\n' >"$empty_config"
docker_output="$(PATH="$docker_bin:/usr/bin:/bin" "$loader" --config "$empty_config" --dry-run)"
assert_contains "$docker_output" "cool-app"
assert_contains "$docker_output" "random_container"
if [[ "$docker_output" == *"tmux"* ]]; then
  fail "docker list must not mention tmux"
fi
if [[ "$docker_output" == *"wsl.localhost"* ]]; then
  fail "docker project names must be shortened from UNC paths"
fi

docker_launch_output="$(SHELLHOPPER_REGISTER_PROFILES=1 PATH="$docker_bin:/usr/bin:/bin" "$loader" --config "$empty_config" --dry-run cool-app)"
assert_contains "$docker_launch_output" "docker start random_container"
assert_contains "$docker_launch_output" "register Windows Terminal profile: cool-app [nvim]"
assert_contains "$docker_launch_output" "register Windows Terminal profile: cool-app [shell]"
assert_contains "$docker_launch_output" "scrollbarState"

help_output="$("$loader" --help)"
assert_contains "$help_output" "Project config format"

printf 'shellhopper_test.sh: ok\n'
