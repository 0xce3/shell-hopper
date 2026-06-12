#!/usr/bin/env bash
set -euo pipefail

config_file="${SHELLHOPPER_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/shellhopper/projects.tsv}"
default_command="${SHELLHOPPER_COMMAND:-nvim}"
dry_run=0
list_only=0
entry_filter="${SHELLHOPPER_ENTRY:-}"
profile_mode="${SHELLHOPPER_PROFILE_MODE:-}"

usage() {
  cat <<'USAGE'
Usage: shellhopper [--config PATH] [--dry-run] [--list] [NAME]

Select a development environment and open a shell or Neovim inside it.

Project config format:
  name<TAB>kind<TAB>target<TAB>workspace<TAB>command

Kinds:
  container     Attach to an existing Docker container.
  devcontainer  Start a devcontainer from a local project path, then attach.
  wsl           Open a local WSL directory.

Examples:
  app<TAB>container<TAB>app-dev<TAB>/workspaces/app<TAB>nvim
  tools<TAB>wsl<TAB>-<TAB>/home/user/src/tools<TAB>nvim

USAGE
}

log() {
  printf '%s\n' "$*"
}

set_terminal_title() {
  local title="$1"
  printf '\033]0;%s\007' "$title"
}

run() {
  if [[ "$dry_run" -eq 1 ]]; then
    printf '  $'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi

  exec "$@"
}

ensure_config() {
  if [[ -f "$config_file" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$config_file")"
  cat >"$config_file" <<'CONFIG'
# name	kind	target	workspace	command
# example	wsl	-	/home/user/src/example	nvim
CONFIG
}

container_status() {
  local container="$1"

  if ! command -v docker >/dev/null 2>&1; then
    printf 'docker unavailable'
    return 0
  fi

  docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || printf 'missing'
}

docker_label() {
  local container="$1"
  local label="$2"

  docker inspect -f "{{ index .Config.Labels \"$label\" }}" "$container" 2>/dev/null | sed 's/^<no value>$//'
}

path_basename() {
  local path="${1//\\//}"
  path="${path%/}"
  printf '%s\n' "${path##*/}"
}

docker_project_name() {
  local container="$1"
  local local_folder compose_project compose_service inferred

  local_folder="$(docker_label "$container" "devcontainer.local_folder")"
  if [[ -n "$local_folder" ]]; then
    inferred="$(path_basename "$local_folder")"
    if [[ -n "$inferred" ]]; then
      printf '%s\n' "$inferred"
      return 0
    fi
  fi

  compose_project="$(docker_label "$container" "com.docker.compose.project")"
  if [[ -n "$compose_project" ]]; then
    printf '%s\n' "$compose_project"
    return 0
  fi

  compose_service="$(docker_label "$container" "com.docker.compose.service")"
  if [[ -n "$compose_service" ]]; then
    printf '%s\n' "$compose_service"
    return 0
  fi

  printf '%s\n' "$container"
}

docker_workspace() {
  local container="$1"
  local destination

  while IFS= read -r destination; do
    case "$destination" in
      /workspaces/*|/workspace)
        printf '%s\n' "$destination"
        return 0
        ;;
    esac
  done < <(docker inspect -f '{{range .Mounts}}{{println .Destination}}{{end}}' "$container" 2>/dev/null)

  printf '%s\n' "-"
}

workspace_command() {
  local workspace="$1"
  local command="$2"
  local quoted_workspace

  quoted_workspace="$(printf '%q' "$workspace")"

  if [[ "$workspace" == "-" ]]; then
    printf '%s\n' "$command"
  else
    printf 'cd %s && %s\n' "$quoted_workspace" "$command"
  fi
}

windows_terminal_tabs() {
  local name="$1"
  local ide_command="$2"
  local shell_command="$3"
  local distro="${WSL_DISTRO_NAME:-Ubuntu-22.04}"

  run wt.exe \
    new-tab --title "$name:nvim" -- wsl.exe -d "$distro" -- bash -lc "$ide_command" \
    ';' \
    new-tab --title "$name:shell" -- wsl.exe -d "$distro" -- bash -lc "$shell_command"
}

windows_terminal_profile_name() {
  local name="$1"
  local mode="${2:-}"

  if [[ -n "$mode" ]]; then
    printf '%s [%s]\n' "$name" "$mode"
  else
    printf '%s\n' "$name"
  fi
}

current_script_path() {
  local source="${BASH_SOURCE[0]}"

  if command -v readlink >/dev/null 2>&1; then
    readlink -f "$source"
  else
    cd "$(dirname "$source")" && printf '%s/%s\n' "$PWD" "$(basename "$source")"
  fi
}

windows_terminal_commandline() {
  local entry="$1"
  local mode="${2:-}"
  local distro shellhopper_path quoted_entry quoted_mode quoted_shellhopper_path bootstrap

  distro="${WSL_DISTRO_NAME:-Ubuntu-22.04}"
  shellhopper_path="${SHELLHOPPER_BIN:-$(current_script_path)}"
  quoted_entry="$(printf '%q' "$entry")"
  quoted_mode="$(printf '%q' "$mode")"
  quoted_shellhopper_path="$(printf '%q' "$shellhopper_path")"
  if [[ -n "$mode" ]]; then
    bootstrap="SHELLHOPPER_ENTRY=$quoted_entry SHELLHOPPER_PROFILE_MODE=$quoted_mode exec $quoted_shellhopper_path"
  else
    bootstrap="SHELLHOPPER_ENTRY=$quoted_entry exec $quoted_shellhopper_path"
  fi
  printf 'wsl.exe -d %s -- bash -lc "%s"\n' "$distro" "$bootstrap"
}

register_windows_terminal_profile() {
  local name="$1"
  local entry="$2"
  local mode="${3:-}"
  local profile_name commandline escaped_profile escaped_command powershell_command

  [[ "${SHELLHOPPER_REGISTER_PROFILES:-1}" == "1" ]] || return 0

  profile_name="$(windows_terminal_profile_name "$name" "$mode")"
  commandline="$(windows_terminal_commandline "$entry" "$mode")"

  if [[ "$dry_run" -eq 1 ]]; then
    printf '  # register Windows Terminal profile: %s\n' "$profile_name"
    printf '  # commandline: %s\n' "$commandline"
    printf '  # scrollbarState: hidden\n'
    return 0
  fi

  if ! command -v powershell.exe >/dev/null 2>&1; then
    return 0
  fi

  escaped_profile="${profile_name//\'/\'\'}"
  escaped_command="${commandline//\'/\'\'}"
  powershell_command="
\$ErrorActionPreference = 'Stop'
\$settingsPaths = @(
  \"\$env:LOCALAPPDATA\\Packages\\Microsoft.WindowsTerminal_8wekyb3d8bbwe\\LocalState\\settings.json\",
  \"\$env:LOCALAPPDATA\\Packages\\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\\LocalState\\settings.json\"
)
\$settingsPath = \$settingsPaths | Where-Object { Test-Path \$_ } | Select-Object -First 1
if (-not \$settingsPath) { exit 0 }
\$settings = Get-Content \$settingsPath -Raw | ConvertFrom-Json
if (-not \$settings.profiles) { \$settings | Add-Member -MemberType NoteProperty -Name profiles -Value ([pscustomobject]@{ list = @() }) }
if (-not \$settings.profiles.list) { \$settings.profiles | Add-Member -MemberType NoteProperty -Name list -Value @() }
\$profileName = '$escaped_profile'
\$commandLine = '$escaped_command'
\$existing = \$settings.profiles.list | Where-Object { \$_.name -eq \$profileName } | Select-Object -First 1
if (\$existing) {
  \$existing.commandline = \$commandLine
  \$existing.startingDirectory = '%USERPROFILE%'
  if (-not \$existing.PSObject.Properties['scrollbarState']) { \$existing | Add-Member -MemberType NoteProperty -Name scrollbarState -Value 'hidden' }
  \$existing.scrollbarState = 'hidden'
  if (\$existing.PSObject.Properties['icon']) { \$existing.PSObject.Properties.Remove('icon') }
} else {
  \$settings.profiles.list += [pscustomobject]@{
    guid = \"{\$([guid]::NewGuid().ToString())}\"
    name = \$profileName
    commandline = \$commandLine
    startingDirectory = '%USERPROFILE%'
    scrollbarState = 'hidden'
  }
}
\$settings | ConvertTo-Json -Depth 100 | Set-Content -Encoding utf8 \$settingsPath
"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$powershell_command" >/dev/null 2>&1 || true
}

register_windows_terminal_profiles() {
  local name="$1"
  local entry="$2"

  register_windows_terminal_profile "$name" "$entry" "nvim"
  register_windows_terminal_profile "$name" "$entry" "shell"
}

read_config_entries() {
  ensure_config

  while IFS=$'\t' read -r name kind target workspace command _rest; do
    [[ -z "${name:-}" || "${name:0:1}" == "#" ]] && continue
    [[ -z "${kind:-}" || -z "${target:-}" || -z "${workspace:-}" ]] && continue
    command="${command:-$default_command}"

    case "$kind" in
      container)
        printf 'config\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$kind" "$target" "$workspace" "$command" "$(container_status "$target")"
        ;;
      devcontainer)
        printf 'config\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$kind" "$target" "$workspace" "$command" "project"
        ;;
      wsl)
        printf 'config\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$kind" "$target" "$workspace" "$command" "local"
        ;;
      *)
        printf 'config\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$kind" "$target" "$workspace" "$command" "unknown kind"
        ;;
    esac
  done <"$config_file"
}

read_docker_entries() {
  if ! command -v docker >/dev/null 2>&1; then
    return 0
  fi

  docker ps -a --format '{{.Names}}\t{{.Status}}' 2>/dev/null |
    while IFS=$'\t' read -r name status; do
      [[ -z "${name:-}" ]] && continue
      local project workspace command detail
      project="$(docker_project_name "$name")"
      workspace="$(docker_workspace "$name")"
      if [[ "$workspace" == "-" ]]; then
        command="bash"
      else
        command="$default_command"
      fi
      detail="$status"
      if [[ "$project" != "$name" ]]; then
        detail="$status ($name)"
      fi
      printf 'docker\t%s\tcontainer\t%s\t%s\t%s\t%s\n' "$project" "$name" "$workspace" "$command" "$detail"
    done
}

entries() {
  {
    read_config_entries
    read_docker_entries
  } | awk -F '\t' '!seen[$2 "|" $3 "|" $4]++'
}

display_entries() {
  entries | awk -F '\t' '{
    printf "%-12s %-28s %-13s %-28s %s\n", $1, $2, $3, $6, $7
  }'
}

fzf_entries() {
  entries | awk -F '\t' '
    function color(code, text) { return sprintf("\033[%sm%s\033[0m", code, text) }
    {
      command = $6
      status_icon = color("33", "◐")
      status_text = $7
      if ($7 ~ /^Up/) {
        status_icon = color("32", "●")
      } else if ($7 ~ /^Exited/) {
        status_icon = color("90", "○")
      }

      source = color("36", $1)
      name = color("1;37", $2)
      kind = color("35", $3)
      target = color("90", $4)
      command_col = color("33", command)

      display = sprintf("%s  %-30s %-11s %-24s %s", status_icon, name, kind, command_col, status_text)
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", display, $1, $2, $3, $4, $5, $6, $7, command
    }'
}

find_entry() {
  local filter="$1"
  entries | awk -F '\t' -v filter="$filter" '$2 == filter || $4 == filter { print; exit }'
}

choose_entry() {
  local selected

  if [[ "$list_only" -eq 1 ]]; then
    display_entries
    return 0
  fi

  if [[ -n "$entry_filter" ]]; then
    selected="$(find_entry "$entry_filter")"
    if [[ -z "$selected" ]]; then
      log "No environment found for: $entry_filter"
      exit 1
    fi
    launch_entry "$selected"
    return 0
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    display_entries
    return 0
  fi

  if command -v fzf >/dev/null 2>&1; then
    # shellcheck disable=SC2016
    selected="$(
      fzf_entries |
        fzf --ansi \
          --delimiter=$'\t' \
          --with-nth=1 \
          --nth=1 \
          --layout=reverse \
          --height=80% \
          --border=rounded \
          --prompt='ShellHopper > ' \
          --header=$'Select development environment\n↑/↓ move  Enter open  type to filter  Esc cancel' \
          --preview='printf "%s\n" {} | awk -F "\t" "{ printf \"Name:      %s\nSource:    %s\nKind:      %s\nTarget:    %s\nWorkspace: %s\nCommand:   %s\nStatus:    %s\n\", \$3, \$2, \$4, \$5, \$6, \$9, \$8 }"' \
          --preview-window='right,50%,border-left'
    )"
    if [[ -n "${selected:-}" ]]; then
      selected="$(printf '%s\n' "$selected" | cut -f2-7)"
    fi
  else
    mapfile -t rows < <(entries)
    if [[ "${#rows[@]}" -eq 0 ]]; then
      log "No environments found. Add entries to $config_file."
      exit 1
    fi

    local i
    for i in "${!rows[@]}"; do
      IFS=$'\t' read -r source name kind _target _workspace _command status <<<"${rows[$i]}"
      printf '%2d) %-12s %-28s %-13s %s\n' "$((i + 1))" "$source" "$name" "$kind" "$status"
    done

    local choice
    read -r -p "Select environment: " choice
    selected="${rows[$((choice - 1))]:-}"
  fi

  [[ -n "${selected:-}" ]] || exit 0
  launch_entry "$selected"
}

launch_entry() {
  local row="$1"
  local source name kind target workspace command status
  local inner_command shell_inner_command
  IFS=$'\t' read -r source name kind target workspace command status <<<"$row"
  set_terminal_title "$name"
  register_windows_terminal_profiles "$name" "$name"

  case "$kind" in
    container)
      if [[ "$(container_status "$target")" != "running" ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
          printf '  $ docker start %q\n' "$target"
        else
          docker start "$target" >/dev/null
        fi
      fi

      inner_command="$(workspace_command "$workspace" "$command")"
      shell_inner_command="$(workspace_command "$workspace" "bash")"
      case "$profile_mode" in
        nvim)
          run docker exec -e TERM=xterm-256color -e COLORTERM=truecolor -it "$target" bash -lc "$inner_command"
          ;;
        shell)
          run docker exec -e TERM=xterm-256color -e COLORTERM=truecolor -it "$target" bash -lc "$shell_inner_command"
          ;;
        "")
          windows_terminal_tabs "$name" \
            "docker exec -e TERM=xterm-256color -e COLORTERM=truecolor -it $(printf '%q' "$target") bash -lc $(printf '%q' "$inner_command")" \
            "docker exec -e TERM=xterm-256color -e COLORTERM=truecolor -it $(printf '%q' "$target") bash -lc $(printf '%q' "$shell_inner_command")"
          ;;
        *)
          log "Unsupported ShellHopper profile mode: $profile_mode"
          exit 2
          ;;
      esac
      ;;
    devcontainer)
      if ! command -v devcontainer >/dev/null 2>&1; then
        log "devcontainer CLI not found. Install it with: npm install -g @devcontainers/cli"
        exit 1
      fi

      devcontainer up --workspace-folder "$target"
      inner_command="$(workspace_command "$workspace" "$command")"
      shell_inner_command="$(workspace_command "$workspace" "bash")"
      case "$profile_mode" in
        nvim)
          run devcontainer exec --workspace-folder "$target" bash -lc "$inner_command"
          ;;
        shell)
          run devcontainer exec --workspace-folder "$target" bash -lc "$shell_inner_command"
          ;;
        "")
          windows_terminal_tabs "$name" \
            "devcontainer exec --workspace-folder $(printf '%q' "$target") bash -lc $(printf '%q' "$inner_command")" \
            "devcontainer exec --workspace-folder $(printf '%q' "$target") bash -lc $(printf '%q' "$shell_inner_command")"
          ;;
        *)
          log "Unsupported ShellHopper profile mode: $profile_mode"
          exit 2
          ;;
      esac
      ;;
    wsl)
      inner_command="$(workspace_command "$workspace" "$command")"
      shell_inner_command="$(workspace_command "$workspace" "bash")"
      case "$profile_mode" in
        nvim)
          run bash -lc "$inner_command"
          ;;
        shell)
          run bash -lc "$shell_inner_command"
          ;;
        "")
          windows_terminal_tabs "$name" "$inner_command" "$shell_inner_command"
          ;;
        *)
          log "Unsupported ShellHopper profile mode: $profile_mode"
          exit 2
          ;;
      esac
      ;;
    *)
      log "Unsupported environment kind: $kind"
      exit 1
      ;;
  esac
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        config_file="$2"
        shift
        ;;
      --dry-run)
        dry_run=1
        ;;
      --list)
        list_only=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        if [[ -z "$entry_filter" ]]; then
          entry_filter="$1"
        else
          usage >&2
          exit 2
        fi
        ;;
    esac
    shift
  done

  choose_entry
}

main "$@"
