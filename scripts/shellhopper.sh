#!/usr/bin/env bash
set -euo pipefail

config_file="${SHELLHOPPER_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/shellhopper/projects.tsv}"
default_command="${SHELLHOPPER_COMMAND:-nvim}"
tmux_enabled="${SHELLHOPPER_TMUX:-1}"
dry_run=0
list_only=0
sessions_only=0
kill_target=""
entry_filter="${SHELLHOPPER_ENTRY:-}"

usage() {
  cat <<'USAGE'
Usage: shellhopper [--config PATH] [--dry-run] [--list] [--sessions] [--kill NAME] [NAME]

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

Session management:
  --sessions   List ShellHopper tmux sessions.
  --kill NAME  Kill the ShellHopper tmux session for NAME.
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

session_name() {
  local name="$1"
  name="${name//[^[:alnum:]_-]/_}"
  printf 'sh-%s\n' "${name:-dev}"
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

tmux_command() {
  local name="$1"
  local ide_command="$2"
  local shell_command="$3"
  local serial_command="${4:-$shell_command}"
  local session quoted_session quoted_title quoted_ide_command quoted_shell_command quoted_serial_command

  if [[ "$tmux_enabled" != "1" ]]; then
    printf '%s\n' "$ide_command"
    return 0
  fi

  session="$(session_name "$name")"
  quoted_session="$(printf '%q' "$session")"
  quoted_title="$(printf '%q' "$name")"
  quoted_ide_command="$(printf '%q' "$ide_command")"
  quoted_shell_command="$(printf '%q' "$shell_command")"
  quoted_serial_command="$(printf '%q' "$serial_command")"

  cat <<COMMAND
if command -v tmux >/dev/null 2>&1; then
  mkdir -p ~/.config/tmux ~/.config/shellhopper;
  cat > ~/.config/tmux/tmux.conf <<'SHELLHOPPER_TMUX'
set -g default-terminal "tmux-256color"
set -g terminal-overrides ",*:RGB"
set -g terminal-features "*:RGB"

# Status bar
set -g status on
set -g status-position bottom
set -g status-interval 0
set -g status-style "bg=#32302f,fg=#a89984"

# Left: project name (strip sh- prefix)
set -g status-left-length 40
set -g status-left "#[bg=#504945,fg=#fabd2f,bold]  #{E:SHELLHOPPER_NAME}  #[default] "

# Right: empty
set -g status-right ""
set -g status-right-length 0

# Window tabs — index: name
set -g window-status-format         "#[bg=#32302f,fg=#a89984]  #I: #W  "
set -g window-status-current-format "#[bg=#504945,fg=#fabd2f,bold]  #I: #W  "
set -g window-status-separator      ""
SHELLHOPPER_TMUX
  cp ~/.config/tmux/tmux.conf ~/.config/shellhopper/tmux.conf;
  tmux source-file ~/.config/tmux/tmux.conf >/dev/null 2>&1 || true;
  tmux set-option -g default-terminal tmux-256color >/dev/null;
  tmux set-option -g terminal-overrides ',*:RGB' >/dev/null;
  tmux set-option -g terminal-features '*:RGB' >/dev/null 2>&1 || true;
  tmux has-session -t $quoted_session 2>/dev/null || {
    tmux new-session -d -s $quoted_session -n ide $quoted_ide_command;
    tmux set-environment -t $quoted_session SHELLHOPPER_NAME $quoted_title >/dev/null;
    tmux set-option -t $quoted_session set-titles on >/dev/null;
    tmux set-option -t $quoted_session set-titles-string $quoted_title >/dev/null;
    tmux new-window -t $quoted_session -n shell $quoted_shell_command;
    tmux new-window -t $quoted_session -n serial $quoted_serial_command;
    tmux select-window -t $quoted_session:ide;
  }
  tmux -2 attach -t $quoted_session;
else
  eval $quoted_ide_command;
fi
COMMAND
}

windows_terminal_profile_name() {
  printf '%s\n' "$1"
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
  local distro shellhopper_path quoted_entry quoted_shellhopper_path bootstrap

  distro="${WSL_DISTRO_NAME:-Ubuntu-22.04}"
  shellhopper_path="${SHELLHOPPER_BIN:-$(current_script_path)}"
  quoted_entry="$(printf '%q' "$entry")"
  quoted_shellhopper_path="$(printf '%q' "$shellhopper_path")"
  bootstrap="SHELLHOPPER_ENTRY=$quoted_entry exec $quoted_shellhopper_path"
  printf 'wsl.exe -d %s -- bash -lc "%s"\n' "$distro" "$bootstrap"
}

register_windows_terminal_profile() {
  local name="$1"
  local entry="$2"
  local profile_name commandline escaped_profile escaped_command powershell_command

  [[ "${SHELLHOPPER_REGISTER_PROFILES:-1}" == "1" ]] || return 0

  profile_name="$(windows_terminal_profile_name "$name")"
  commandline="$(windows_terminal_commandline "$entry")"

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

list_sessions() {
  if ! command -v tmux >/dev/null 2>&1; then
    log "tmux unavailable"
    return 0
  fi

  tmux list-sessions -F '#{session_name} windows=#{session_windows} attached=#{session_attached}' 2>/dev/null |
    awk '$1 ~ /^sh-/ { print }'
}

kill_session() {
  local target="$1"
  local session

  session="$(session_name "$target")"
  if [[ "$dry_run" -eq 1 ]]; then
    printf '  $ tmux kill-session -t %q\n' "$session"
    return 0
  fi

  tmux kill-session -t "$session"
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
  entries | awk -F '\t' -v tmux="$tmux_enabled" '{
    command = $6
    if (tmux == "1") {
      command = "tmux:" command
    }
    printf "%-12s %-28s %-13s %-28s %s\n", $1, $2, $3, command, $7
  }'
}

fzf_entries() {
  entries | awk -F '\t' -v tmux="$tmux_enabled" '
    function color(code, text) { return sprintf("\033[%sm%s\033[0m", code, text) }
    {
      command = $6
      if (tmux == "1") {
        command = "tmux:" command
      }

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

  case "$kind" in
    container)
      if [[ "$source" == "docker" ]]; then
        register_windows_terminal_profile "$name" "$name"
      fi
      if [[ "$(container_status "$target")" != "running" ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
          printf '  $ docker start %q\n' "$target"
        else
          docker start "$target" >/dev/null
        fi
      fi

      if [[ "$tmux_enabled" == "1" ]]; then
        inner_command="$(workspace_command "$workspace" "$command")"
        shell_inner_command="$(workspace_command "$workspace" "bash")"
        run bash -lc "$(tmux_command "$name" "docker exec -e TERM=tmux-256color -e COLORTERM=truecolor -it $(printf '%q' "$target") bash -lc $(printf '%q' "$inner_command")" "docker exec -e TERM=tmux-256color -e COLORTERM=truecolor -it $(printf '%q' "$target") bash -lc $(printf '%q' "$shell_inner_command")")"
      else
        run docker exec -e TERM=xterm-256color -e COLORTERM=truecolor -it "$target" bash -lc "$(workspace_command "$workspace" "$command")"
      fi
      ;;
    devcontainer)
      register_windows_terminal_profile "$name" "$name"
      if ! command -v devcontainer >/dev/null 2>&1; then
        log "devcontainer CLI not found. Install it with: npm install -g @devcontainers/cli"
        exit 1
      fi

      devcontainer up --workspace-folder "$target"
      if [[ "$tmux_enabled" == "1" ]]; then
        inner_command="$(workspace_command "$workspace" "$command")"
        shell_inner_command="$(workspace_command "$workspace" "bash")"
        run bash -lc "$(tmux_command "$name" "devcontainer exec --workspace-folder $(printf '%q' "$target") bash -lc $(printf '%q' "$inner_command")" "devcontainer exec --workspace-folder $(printf '%q' "$target") bash -lc $(printf '%q' "$shell_inner_command")")"
      else
        local sim_trigger bridge_pid
        sim_trigger="${target}/.shellhopper-sim-trigger"
        rm -f "$sim_trigger"
        bridge_pid=""

        if command -v shellhopper-sim-bridge >/dev/null 2>&1; then
          shellhopper-sim-bridge "$sim_trigger" "$target" &
          bridge_pid=$!
        fi

        devcontainer exec --workspace-folder "$target" bash -lc "$(workspace_command "$workspace" "$command")" || true

        if [[ -n "$bridge_pid" ]]; then
          kill "$bridge_pid" 2>/dev/null || true
          wait "$bridge_pid" 2>/dev/null || true
        fi
        rm -f "$sim_trigger"
      fi
      ;;
    wsl)
      if [[ "$tmux_enabled" == "1" ]]; then
        run bash -lc "$(tmux_command "$name" "$(workspace_command "$workspace" "$command")" "$(workspace_command "$workspace" "bash")")"
      else
        run bash -lc "$(workspace_command "$workspace" "$command")"
      fi
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
      --sessions)
        sessions_only=1
        ;;
      --kill)
        if [[ $# -lt 2 ]]; then
          usage >&2
          exit 2
        fi
        kill_target="$2"
        shift
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

  if [[ "$sessions_only" -eq 1 ]]; then
    list_sessions
    return 0
  fi

  if [[ -n "$kill_target" ]]; then
    kill_session "$kill_target"
    return 0
  fi

  choose_entry
}

main "$@"
