#!/bin/bash
set -euo pipefail   # stop on any error or missing variable
IFS=$'\n\t'         # safe word-splitting

#echo "Goblin invoked"

SYSTEM_INPUT_FILE="$1"  # Read the passed persona JSON
#echo "System input file $SYSTEM_INPUT_FILE"
SYSTEM_CONTENT=$(<"$SYSTEM_INPUT_FILE")
#echo "hello $SYSTEM_CONTENT"
TEMPLATE="./Context/conjuration_log.json"  # <-- ADD THIS H#ERE
#echo "$TEMPLATE"
# Show results
#echo "🔒 LOCKED KEYS:"
#printf '%s\n' "${LOCKED_KEYS[@]}"

#echo ""
#echo "🔓 UNLOCKED KEYS:"
#printf '%s\n' "${UNLOCKED_KEYS[@]}"

# Rebuild INSTR so that for each key with a CCC placeholder we store the stripped instruction
declare -A INSTR
while IFS= read -r line; do
  key=${line%%:*}
  value=${line#*:}
  if [[ "$value" =~ ^CCC[[:space:]](.+) ]]; then
    INSTR["$key"]="${BASH_REMATCH[1]}"
  fi
done < <(
  jq -r '
    paths(scalars) as $p
    | "\($p | map(tostring) | join(".")):\(getpath($p))"
  ' /bin/Ritualc/Templates/template_conjuration_log.json
)
#echo '39'
# Now build the RULE string
RULE=$(cat <<EOF
Instructions for Goblin:

You’re supposed to edit ./Context/conjuration_log.json.
Update ALL unlocked keys, according to the Dark Lords wishes.

You are not permitted to edit any other file, which is only permitted in a ritual.

Read the unlocked keys, and update them. If they contain three capital letters in a row (eg. CCC),
you may rewrite contents completely..

$(for k in "${!INSTR[@]}"; do
    printf "  • %s → %s\n" "$k" "${INSTR[$k]}"
  done)
EOF
)

 # 👇 Build the rule message as JSON
 #RULE_JSON=$(jq -n --arg rule "$RULE" '{ "role": "system", "content": $rule }')
 RULE_JSON=$(jq -n --arg rule "$RULE" '[{ "role": "Codex Rules", "content": $rule }]')

 # 👇 Merge the input JSON array and the rule message
 FULL_INPUT=$(jq -s 'add' \
   <(echo "$SYSTEM_CONTENT") \
   <(echo "$RULE_JSON"))

#echo "86"

echo "$FULL_INPUT" > ./chat.txt
#echo "./chat.txt"
#output=$(codex e "Read ./chat.txt and apply.")
# Save Codex reply to whispers
#echo "$output" > ./Context/.whispers.txt

## Launch split-screen using tmux: JSON renderer and Codex
# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

 # Ensure tmux is available
 if ! command -v tmux > /dev/null 2>&1; then
  echo "Error: tmux is required for Goblin Chat. Please install tmux." >&2
  exit 1
fi
 
# Enable mouse support to allow clicking on panes to focus them
tmux set-option -g mouse on 2>/dev/null || true
# For older tmux versions: enable mouse at the window level as well
tmux set-window-option -g mouse on 2>/dev/null || true

# If inside an existing tmux session, create a new window; otherwise, create a new session
if [ -n "${TMUX-}" ]; then
  # Running inside tmux: open a new window in the current session
  CURRENT_SESSION=$(tmux display-message -p '#{session_name}')
  # Kill existing goblin_chat window if present
  if tmux list-windows -t "$CURRENT_SESSION" -F "#{window_name}" 2>/dev/null | grep -q '^goblin_chat$'; then
    tmux kill-window -t "${CURRENT_SESSION}:goblin_chat"
  fi
  # Create window and split
  tmux new-window -n goblin_chat -t "$CURRENT_SESSION" "bash -lc 'exec \"$SCRIPT_DIR/jsonwatch_render_rust\" \"$TEMPLATE\"; exec bash'"
  tmux split-window -h -d -t "${CURRENT_SESSION}:goblin_chat" "bash -lc 'codex --full-auto \"read ./chat.txt and follow instructions.\" | tee ./Context/.whispers.txt; rm ./chat.txt; exec bash'"
  # Ensure mouse support in goblin_chat window
  tmux set-option -t "${CURRENT_SESSION}" -g mouse on 2>/dev/null || true
  tmux set-window-option -t "${CURRENT_SESSION}" -g mouse on 2>/dev/null || true
  # Bind 'q' to kill the goblin_chat window without prefix
  tmux bind-key -n 7 kill-window -t "${CURRENT_SESSION}:goblin_chat"
  # Bind SPACE to toggle focus between left (pane 0) and right (pane 1)
  tmux bind-key -n 3 if-shell -F '#{==:#{pane_index},0}' 'select-pane -t 1' 'select-pane -t 0'
  tmux select-layout -t "${CURRENT_SESSION}:goblin_chat" even-horizontal
  tmux select-window -t "${CURRENT_SESSION}:goblin_chat"
  # Wait until goblin_chat window is closed (exit on 'q')
  while tmux list-windows -t "${CURRENT_SESSION}" -F "#{window_name}" | grep -q '^goblin_chat$'; do
    sleep 0.5
  done
  exit 0
else
  # Not inside tmux: start a detached session
  # Kill existing session if present
  if tmux has-session -t goblin_chat 2>/dev/null; then
    tmux kill-session -t goblin_chat
  fi
  tmux new-session -d -s goblin_chat "bash -lc 'exec \"$SCRIPT_DIR/jsonwatch_render_rust\" \"$TEMPLATE\"; exec bash'"
  tmux split-window -h -d -t goblin_chat "bash -lc 'codex --full-auto \"read ./chat.txt and follow instructions.\" | tee ./Context/.whispers.txt; rm ./chat.txt; exec bash'"
  # Ensure mouse support in goblin_chat session
  tmux set-option -t goblin_chat -g mouse on 2>/dev/null || true
  tmux set-window-option -t goblin_chat -g mouse on 2>/dev/null || true
  # Bind 'q' to kill the goblin_chat session without prefix
  tmux bind-key -n 7 kill-session -t goblin_chat
  # Bind SPACE to toggle focus between left (pane 0) and right (pane 1)
  tmux bind-key -n 3 if-shell -F '#{==:#{pane_index},0}' 'select-pane -t 1' 'select-pane -t 0'
  tmux select-layout -t goblin_chat even-horizontal
  tmux attach -t goblin_chat
  exit 0
fi
