#!/usr/bin/env bash
set -euo pipefail

config_file="${SHELLHOPPER_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/shellhopper/projects.tsv}"
default_command="${SHELLHOPPER_COMMAND:-nvim}"
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
      printf 'docker\t%s\tcontainer\t%s\t-\tbash\t%s\n' "$name" "$name" "$status"
    done
}

entries() {
  {
    read_config_entries
    read_docker_entries
  } | awk -F '\t' '!seen[$2 "|" $3 "|" $4]++'
}

display_entries() {
  entries | awk -F '\t' '{ printf "%-12s %-28s %-13s %-28s %s\n", $1, $2, $3, $6, $7 }'
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
  IFS=$'\t' read -r source name kind target workspace command status <<<"$row"

  case "$kind" in
    container)
      if [[ "$(container_status "$target")" != "running" ]]; then
        docker start "$target" >/dev/null
      fi

      if [[ "$workspace" == "-" ]]; then
        run docker exec -it "$target" bash -lc "$command"
      else
        run docker exec -it "$target" bash -lc "cd $(printf '%q' "$workspace") && $command"
      fi
      ;;
    devcontainer)
      if ! command -v devcontainer >/dev/null 2>&1; then
        log "devcontainer CLI not found. Install it with: npm install -g @devcontainers/cli"
        exit 1
      fi

      devcontainer up --workspace-folder "$target"
      run devcontainer exec --workspace-folder "$target" bash -lc "cd $(printf '%q' "$workspace") && $command"
      ;;
    wsl)
      run bash -lc "cd $(printf '%q' "$workspace") && $command"
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
