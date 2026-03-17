#!/usr/bin/env bash
# Claude Code hook script — writes per-pane status files for tmux session switcher
# and marks the tmux window as "unread" when Claude finishes.
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

# --- Unread window indicator ---
# Get the window and session that own this pane
pane_window=$(tmux display-message -t "$TMUX_PANE" -p '#{window_id}' 2>/dev/null) || exit 0
pane_session=$(tmux display-message -t "$TMUX_PANE" -p '#{session_name}' 2>/dev/null) || exit 0
window_name=$(tmux display-message -t "$TMUX_PANE" -p '#{window_name}' 2>/dev/null) || exit 0

ICON="●"

case "$status" in
  done|permission)
    # Only mark if this window is NOT the active one in the client's current session
    active_window=$(tmux display-message -t "$pane_session" -p '#{window_id}' 2>/dev/null)
    if [ "$pane_window" != "$active_window" ]; then
      # Prepend icon if not already there
      case "$window_name" in
        "$ICON "*)  ;;  # already marked
        *)  tmux rename-window -t "$pane_window" "$ICON $window_name" ;;
      esac
    fi
    ;;
  working)
    # User started a new prompt — clear the unread icon
    case "$window_name" in
      "$ICON "*)  tmux rename-window -t "$pane_window" "${window_name#$ICON }" ;;
    esac
    ;;
esac
