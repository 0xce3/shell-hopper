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
grep -q 'Remove-Member -Name icon' "$repo_root/install.ps1" || fail "install.ps1 must remove ShellHopper profile icons"
grep -q 'tmux' "$repo_root/install.ps1" || fail "install.ps1 installs tmux"
# shellcheck disable=SC2016
grep -Fq 'name="${name//[^[:alnum:]_-]/_}"' "$loader" || fail "tmux session names must not allow dots"
grep -q 'set_terminal_title' "$loader" || fail "shellhopper sets terminal tab title"
grep -q 'set-titles-string' "$loader" || fail "tmux sets a short terminal title"
grep -q 'default-terminal tmux-256color' "$loader" || fail "tmux must use tmux-256color"
grep -q 'terminal-overrides.*RGB' "$loader" || fail "tmux must enable RGB truecolor"
grep -q '.config/tmux/tmux.conf' "$loader" || fail "shellhopper must write standard tmux config"
grep -q 'tmux source-file ~/.config/tmux/tmux.conf' "$loader" || fail "shellhopper must source tmux config"
grep -q '.config/tmux/tmux.conf' "$repo_root/install.ps1" || fail "install.ps1 must install tmux config"
grep -q 'status-style.*#32302f' "$loader" || fail "tmux status line must use gruvbox colors"
grep -q 'COLORTERM=truecolor' "$loader" || fail "container launches must pass truecolor"
grep -q 'TERM=tmux-256color' "$loader" || fail "tmux container launches must pass tmux TERM"
grep -q 'tmux -2 attach' "$loader" || fail "tmux attach must force 256-color mode"
grep -q 'tmux_enabled="${SHELLHOPPER_TMUX:-1}"' "$loader" || fail "tmux must be enabled by default"
grep -q 'register_windows_terminal_profile' "$loader" || fail "selected containers must be registered as Windows Terminal profiles"
grep -q 'scrollbarState' "$loader" || fail "generated Windows Terminal profiles must hide scrollbars"
grep -q -- '--sessions' "$loader" || fail "shellhopper must list tmux sessions"
grep -q -- '--kill NAME' "$loader" || fail "shellhopper must document session cleanup"
grep -q 'kill-session' "$loader" || fail "shellhopper must support killing stale tmux sessions"
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
assert_contains "$output" "tmux"

tmux_launch_output="$("$loader" --config "$config" --dry-run local-tools)"
assert_contains "$tmux_launch_output" "-n shell"
assert_contains "$tmux_launch_output" "-n serial"
if [[ "$tmux_launch_output" == *"-n logs"* ]]; then
  fail "direct tmux launch must not create a logs window"
fi

direct_output="$(SHELLHOPPER_TMUX=0 "$loader" --config "$config" --dry-run local-tools)"
assert_contains "$direct_output" "local-tools"
assert_contains "$direct_output" "nvim"

kill_output="$("$loader" --dry-run --kill local-tools)"
assert_contains "$kill_output" "tmux"
assert_contains "$kill_output" "kill-session"
assert_contains "$kill_output" "sh-local-tools"

mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
printf 'TMUX argc=%s:' "$#" >> "$TMUX_CAPTURE"
printf ' [%s]' "$@" >> "$TMUX_CAPTURE"
printf '\n' >> "$TMUX_CAPTURE"
case "$1" in
  has-session) exit 1 ;;
  attach) exit 0 ;;
esac
exit 0
TMUX
chmod +x "$tmp_dir/bin/tmux"

tmux_capture="$tmp_dir/tmux.log"
TMUX_CAPTURE="$tmux_capture" PATH="$tmp_dir/bin:/usr/bin:/bin" "$loader" --config "$config" local-tools >/dev/null
tmux_output="$(cat "$tmux_capture")"
assert_contains "$tmux_output" "[new-window] [-t] [sh-local-tools] [-n] [shell]"
assert_contains "$tmux_output" "[new-window] [-t] [sh-local-tools] [-n] [serial]"
if [[ "$tmux_output" == *"[-n] [logs]"* ]]; then
  fail "tmux launch must not create a logs window"
fi

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
assert_contains "$docker_output" "tmux"
if [[ "$docker_output" == *"wsl.localhost"* ]]; then
  fail "docker project names must be shortened from UNC paths"
fi

docker_launch_output="$(SHELLHOPPER_REGISTER_PROFILES=1 PATH="$docker_bin:/usr/bin:/bin" "$loader" --config "$empty_config" --dry-run cool-app)"
assert_contains "$docker_launch_output" "docker start random_container"
assert_contains "$docker_launch_output" "register Windows Terminal profile: cool-app"
assert_contains "$docker_launch_output" "scrollbarState"

help_output="$("$loader" --help)"
assert_contains "$help_output" "Project config format"

printf 'shellhopper_test.sh: ok\n'
