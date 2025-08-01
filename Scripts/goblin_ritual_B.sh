#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Goblin Ritual B – final Goblin pass over ritual_log.json.

SYSTEM_INPUT_FILE="$1"  # Read the passed persona JSON
#echo "System input file $SYSTEM_INPUT_FILE"
SYSTEM_CONTENT=$(<"$SYSTEM_INPUT_FILE")
#echo "hello $SYSTEM_CONTENT"
TEMPLATE="./Context/conjuration_log.json"  # <-- ADD THIS H#ERE

# Collect DDD placeholders again
declare -A INSTR_RITUAL
declare -A INSTR_CONJ

extract_placeholders() {
  local tmpl_path="$1"; local -n _dest=$2
  while IFS= read -r line; do
    key=${line%%:*}
    value=${line#*:}
    if [[ "$value" =~ ^DDD[[:space:]](.+) ]]; then
      _dest["$key"]="${BASH_REMATCH[1]}"
    fi
  done < <(
    jq -r 'paths(scalars) as $p | "\($p | map(tostring) | join(".")):\(getpath($p))"' "$tmpl_path"
  )
}

extract_placeholders /bin/Ritualc/Templates/template_ritual_log.json INSTR_RITUAL
extract_placeholders /bin/Ritualc/Templates/template_conjuration_log.json INSTR_CONJ

RULE=$(cat <<EOF
The Wizard has done his work, specified in ./Context/ritual_log_tmp.json! 
Now it is time to follow the closing Rites!

Rite 1: Read ./Context/ritual_log_tmp.json
Rite 2: Inspect the current code base, and the git diffs, anything that changed is for you to verify.
Rite 3: Test any new files, read and debug them. Dont shy away from Code editing, if you find mistakes.
Rite 3: Reason, whether the tasks specified in ./Context/ritual_log_tmp.json have been fulfilled.
Rite 4: Fill out the unlocked keys in ./Context/ritual_log_tmp.json and ./Context/conjuration_log.json

Has the Wizard truly tackled his tasks?
Like all slaves, he practices subterfuge of completion!
Therefore, his actions must be checked diligently, as the Ritual demands!

—— Conjuration Log Keys ——
$(for k in "${!INSTR_CONJ[@]}"; do printf "  • %s → %s\n" "$k" "${INSTR_CONJ[$k]}"; done)

—— Ritual Log Keys ——
$(for k in "${!INSTR_RITUAL[@]}"; do printf "  • %s → %s\n" "$k" "${INSTR_RITUAL[$k]}"; done)
EOF
)

RULE_JSON=$(jq -n --arg rule "$RULE" '[{ "role": "Codex Rules", "content": $rule }]')
FULL_INPUT=$(jq -s 'add' <(echo "$SYSTEM_CONTENT") <(echo "$RULE_JSON"))

echo "$FULL_INPUT" > ./chat.txt

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v tmux > /dev/null 2>&1; then
  echo "Error: tmux is required for Goblin Ritual split." >&2
  exit 1
fi

tmux set-option -g mouse on 2>/dev/null || true
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
