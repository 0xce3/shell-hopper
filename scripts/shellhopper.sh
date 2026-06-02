#!/usr/bin/env bash
set -euo pipefail

config_file="${SHELLHOPPER_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/shellhopper/projects.tsv}"
default_command="${SHELLHOPPER_COMMAND:-nvim}"
tmux_enabled="${SHELLHOPPER_TMUX:-1}"
dry_run=0
list_only=0

usage() {
  cat <<'USAGE'
Usage: shellhopper [--config PATH] [--dry-run] [--list]

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
  local path="${1%/}"
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
  local session quoted_session

  if [[ "$tmux_enabled" != "1" ]]; then
    printf '%s\n' "$ide_command"
    return 0
  fi

  session="$(session_name "$name")"
  quoted_session="$(printf '%q' "$session")"

  cat <<COMMAND
if command -v tmux >/dev/null 2>&1; then
  tmux has-session -t $quoted_session 2>/dev/null || {
    tmux new-session -d -s $quoted_session -n ide "$ide_command";
    tmux new-window -t $quoted_session -n shell "$shell_command";
    tmux new-window -t $quoted_session -n tasks "$shell_command";
    tmux new-window -t $quoted_session -n logs "$shell_command";
    tmux select-window -t $quoted_session:ide;
  }
  tmux attach -t $quoted_session;
else
  $ide_command;
fi
COMMAND
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

choose_entry() {
  local selected

  if [[ "$list_only" -eq 1 || "$dry_run" -eq 1 ]]; then
    display_entries
    return 0
  fi

  if command -v fzf >/dev/null 2>&1; then
    selected="$(entries | fzf --delimiter=$'\t' --with-nth=1,2,3,6,7 --header='Select development environment')"
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

  case "$kind" in
    container)
      if [[ "$(container_status "$target")" != "running" ]]; then
        docker start "$target" >/dev/null
      fi

      if [[ "$tmux_enabled" == "1" ]]; then
        inner_command="$(workspace_command "$workspace" "$command")"
        shell_inner_command="$(workspace_command "$workspace" "bash")"
        run bash -lc "$(tmux_command "$name" "docker exec -it $(printf '%q' "$target") bash -lc $(printf '%q' "$inner_command")" "docker exec -it $(printf '%q' "$target") bash -lc $(printf '%q' "$shell_inner_command")")"
      else
        run docker exec -it "$target" bash -lc "$(workspace_command "$workspace" "$command")"
      fi
      ;;
    devcontainer)
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
        run devcontainer exec --workspace-folder "$target" bash -lc "$(workspace_command "$workspace" "$command")"
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
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
    shift
  done

  choose_entry
}

main "$@"
