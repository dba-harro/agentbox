#!/usr/bin/env bash

log_info() {
  echo "$*"
}

log_warn() {
  echo "$*" >&2
}

log_error() {
  echo "$*" >&2
}

usage() {
  cat << EOF
Usage: $(basename "$0") [directory]

Launch tuicr in a new Herdr tab to review git changes.

Arguments:
  directory    Git repository directory to review (default: current directory)

Examples:
  $(basename "$0")                    # Review changes in current directory
  $(basename "$0") ~/project          # Review changes in ~/project
EOF
}

check_herdr() {
  if [[ "${HERDR_ENV:-}" != "1" ]]; then
    return 1
  fi
  return 0
}

check_tuicr() {
  if ! command -v tuicr &> /dev/null; then
    log_error "tuicr not found. Install it first."
    return 1
  fi
  return 0
}

check_git_repo() {
  local dir="$1"
  if ! git -C "$dir" rev-parse --git-dir &> /dev/null; then
    return 1
  fi
  return 0
}

launch_tuicr_tab() {
  local target_dir="$1"
  local output_file tab_id pane_id
  output_file=$(mktemp "${TMPDIR:-/tmp}/tuicr-output.XXXXXX")

  # Open a new tab (focusing it so the user sees tuicr) and run tuicr there,
  # exporting any approved instructions to stdout.
  local resp
  resp=$(herdr tab create --cwd "$target_dir" --label tuicr --focus)
  tab_id=$(printf '%s' "$resp" | jq -r '.result.tab.tab_id')
  pane_id=$(printf '%s' "$resp" | jq -r '.result.root_pane.pane_id')

  # Close the tab and clean up on any exit. Values are expanded now: the trap
  # runs after this function returns, when its locals are gone.
  # shellcheck disable=SC2064
  trap "herdr tab close $(printf '%q' "$tab_id") 2>/dev/null; rm -f $(printf '%q' "$output_file")" EXIT

  herdr pane run "$pane_id" "tuicr -w --stdout > $(printf '%q' "$output_file")"

  # Block until tuicr exits (foreground process returns to the shell)
  while herdr pane process-info --pane "$pane_id" 2>/dev/null | grep -qi tuicr; do
    sleep 1
  done

  if [[ -s "$output_file" ]]; then
    cat "$output_file"
  else
    log_info "Nothing to do. Everything's fine"
  fi
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  if ! check_tuicr; then
    exit 1
  fi

  local target_dir="${1:-.}"
  target_dir=$(cd "$target_dir" && pwd)  # Get absolute path

  if ! check_git_repo "$target_dir"; then
    log_error "$target_dir is not a git repository!"
    exit 1
  fi

  if ! check_herdr; then
    log_error "Not running inside Herdr!"
    exit 1
  fi

  launch_tuicr_tab "$target_dir"
}

main "$@"
