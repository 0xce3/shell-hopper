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
[[ -f "$repo_root/bootstrap.ps1" ]] || fail "bootstrap.ps1 exists"
bash -n "$loader"

grep -q 'LASTEXITCODE' "$repo_root/install.ps1" || fail "install.ps1 checks WSL exit codes"
grep -q 'test -x ~/.local/bin/shellhopper' "$repo_root/install.ps1" || fail "Windows Terminal profile bootstraps missing shellhopper"
grep -q 'Optional package installation failed' "$repo_root/install.ps1" || fail "apt package installation is best effort"
grep -q 'JetBrainsMono Nerd Font' "$repo_root/install.ps1" || fail "install.ps1 configures JetBrainsMono Nerd Font"
grep -q 'ryanoasis/nerd-fonts' "$repo_root/install.ps1" || fail "install.ps1 downloads Nerd Fonts from the official release repo"
grep -q 'ProfileIcon' "$repo_root/install.ps1" || fail "install.ps1 exposes a Windows Terminal profile icon"
grep -q 'tmux' "$repo_root/install.ps1" || fail "install.ps1 installs tmux"
grep -q 'Install-Step' "$repo_root/install.ps1" || fail "install.ps1 uses readable installation steps"
grep -q 'SilentlyContinue' "$repo_root/install.ps1" || fail "install.ps1 suppresses noisy download progress"
grep -q 'Installing WSL packages' "$repo_root/install.ps1" || fail "install.ps1 explains WSL package installation"
grep -q 'Test-NerdFontInstalled' "$repo_root/install.ps1" || fail "install.ps1 detects already installed Nerd Fonts"
grep -q "\$bootstrap = @'" "$repo_root/install.ps1" || fail "install.ps1 protects Bash bootstrap from PowerShell interpolation"
grep -q 'api.github.com/repos' "$repo_root/bootstrap.ps1" || fail "bootstrap.ps1 uses GitHub API installer download"
grep -q 'contents/install.ps1' "$repo_root/bootstrap.ps1" || fail "bootstrap.ps1 downloads install.ps1"
grep -q 'Start-Transcript' "$repo_root/bootstrap.ps1" || fail "bootstrap.ps1 writes a log"
grep -q 'Wait-OnFailure' "$repo_root/bootstrap.ps1" || fail "bootstrap.ps1 waits on failure"
grep -Fq 'irm https://raw.githubusercontent.com/0xce3/shell-hopper/main/bootstrap.ps1 | iex' "$repo_root/README.md" || fail "README keeps one-command install"
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

docker_bin="$tmp_dir/bin"
mkdir -p "$docker_bin"
cat >"$docker_bin/docker" <<'DOCKER'
#!/usr/bin/env bash
case "$1 $2" in
  "ps -a")
    printf 'random_container\tUp 2 hours\n'
    ;;
  "inspect -f")
    template="$3"
    case "$template" in
      *'devcontainer.local_folder'*)
        printf '/home/user/src/cool-app\n'
        ;;
      *'com.docker.compose.project'*|*'com.docker.compose.service'*)
        printf '\n'
        ;;
      *'.State.Status'*)
        printf 'running\n'
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

help_output="$("$loader" --help)"
assert_contains "$help_output" "Project config format"

printf 'shellhopper_test.sh: ok\n'
