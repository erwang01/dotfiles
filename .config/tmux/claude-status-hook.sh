#!/usr/bin/env bash
# Claude Code hook script — writes per-pane status files for tmux session switcher
# Called by Claude hooks with status as $1: working, done, idle, permission, ended

cat > /dev/null  # consume stdin (hooks protocol requirement)

status="$1"
[ -z "$TMUX_PANE" ] && exit 0

status_dir="/tmp/claude-tmux-status"
pane_id="${TMUX_PANE#%}"
status_file="$status_dir/$pane_id"

if [ "$status" = "ended" ]; then
  rm -f "$status_file"
else
  mkdir -p "$status_dir"
  printf '%s\n%s\n' "$status" "$(date +%s)" > "$status_file"
fi
