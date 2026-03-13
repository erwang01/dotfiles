#!/usr/bin/env bash
# tmux session switcher with fzf
# enter=switch, ctrl-r=rename, ctrl-a=new
# Shows HEAD commit message and Claude status under each session name

STATUS_DIR="/tmp/claude-tmux-status"

# Remove status files whose pane no longer exists in any session
sweep_orphan_status_files() {
  [ -d "$STATUS_DIR" ] || return
  local active_panes
  active_panes=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | sed 's/^%//')
  for f in "$STATUS_DIR"/*; do
    [ -f "$f" ] || continue
    local pane_id="${f##*/}"
    if ! echo "$active_panes" | grep -qx "$pane_id"; then
      rm -f "$f"
    fi
  done
}

# Returns the highest-priority Claude status across all panes in a session
# Priority: permission > working > idle > done
get_session_claude_status() {
  local session="$1"
  [ -d "$STATUS_DIR" ] || return

  local best=""
  local pane_info
  pane_info=$(tmux list-panes -s -t "$session" -F '#{pane_id} #{pane_current_command}' 2>/dev/null)

  while read -r pane_id cmd; do
    [ -z "$pane_id" ] && continue
    local id="${pane_id#%}"
    local file="$STATUS_DIR/$id"
    [ -f "$file" ] || continue

    # Staleness: if the pane isn't running claude, clean up
    if [ "$cmd" != "claude" ]; then
      rm -f "$file"
      continue
    fi

    local status
    status=$(head -1 "$file")
    case "$status" in
      permission) best="permission" ;;
      working)    [ "$best" != "permission" ] && best="working" ;;
      done|idle)  [ "$best" != "permission" ] && [ "$best" != "working" ] && best="done" ;;
    esac
  done <<< "$pane_info"

  [ -n "$best" ] && echo "$best"
}

format_claude_status() {
  case "$1" in
    working)    printf ' \033[36m⟳ claude: working...\033[0m' ;;
    done)       printf ' \033[32m✓ claude: responded\033[0m' ;;
    permission) printf ' \033[31m⚠ claude: action required\033[0m' ;;
  esac
}

generate_entries() {
  sweep_orphan_status_files

  for session in $(tmux list-sessions -F '#{session_activity} #{session_name}' | sort -rn | cut -d' ' -f2-); do
    path=$(tmux display-message -t "$session" -p '#{pane_current_path}' 2>/dev/null)
    branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "")
    commit=$(git -C "$path" log --oneline -1 2>/dev/null || echo "(no git repo)")
    claude_status=$(get_session_claude_status "$session")
    claude_indicator=$(format_claude_status "$claude_status")
    if [ -n "$claude_status" ]; then
      printf "%s\n  \033[33m%s\033[0m \033[90m%s\033[0m\n  %b\0" "$session" "$branch" "$commit" "$claude_indicator"
    else
      printf "%s\n  \033[33m%s\033[0m \033[90m%s\033[0m\0" "$session" "$branch" "$commit"
    fi
  done
}

while true; do
  output=$(generate_entries | fzf --read0 --ansi --reverse \
    --header 'enter=switch / ctrl-r=rename / ctrl-a=new / ctrl-x=close' \
    --expect=ctrl-r,ctrl-a,ctrl-x)

  # fzf exited with no output (Esc/Ctrl-C)
  [ -z "$output" ] && exit 0

  key=$(echo "$output" | head -1)
  session=$(echo "$output" | sed -n '2p')

  if [ "$key" = "ctrl-a" ]; then
    printf "Session name (empty to cancel): "
    read -r new_session
    if [ -n "$new_session" ]; then
      tmux new-session -d -s "$new_session"
      tmux switch-client -t "$new_session"
      exit 0
    fi
  elif [ "$key" = "ctrl-x" ]; then
    [ -n "$session" ] && tmux kill-session -t "$session"
  elif [ "$key" = "ctrl-r" ]; then
    printf "Rename '%s' to: " "$session"
    read -r new_name
    [ -n "$new_name" ] && tmux rename-session -t "$session" "$new_name"
  elif [ -n "$session" ]; then
    tmux switch-client -t "$session"
    exit 0
  fi
done
