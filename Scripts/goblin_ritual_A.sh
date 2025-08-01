#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Goblin Ritual A – largely identical to goblin_chat.sh but operates on the ritual log.

# Ensure ritual log exists

# Expect path to system input JSON from caller (ritualc.sh provides this)
# Allow optional system-input JSON. If not supplied, create a fallback prompt.
SYSTEM_INPUT_FILE="$1"
SYSTEM_CONTENT=$(<"$SYSTEM_INPUT_FILE")

TEMPLATE="./Context/ritual_log_tmp.json"

# ---------------------------------------------------------------------------
# Collect placeholder instructions (CCC) from BOTH template JSON files
# ---------------------------------------------------------------------------

declare -A INSTR_RITUAL  # placeholders from template_ritual_log.json
declare -A INSTR_CONJ    # placeholders from template_conjuration_log.json

extract_placeholders() {
  local tmpl_path="$1"
  local -n _dest=$2

  while IFS= read -r line; do
    key=${line%%:*}
    value=${line#*:}
    if [[ "$value" =~ ^CCC[[:space:]](.+) ]]; then
      _dest["$key"]="${BASH_REMATCH[1]}"
    fi
  done < <(
    jq -r 'paths(scalars) as $p | "\($p | map(tostring) | join(".")):\(getpath($p))"' "$tmpl_path"
  )
}

extract_placeholders /bin/Ritualc/Templates/template_ritual_log.json INSTR_RITUAL
extract_placeholders /bin/Ritualc/Templates/template_conjuration_log.json INSTR_CONJ

# Build RULE string shown to Goblin
RULE=$(cat <<EOF
Instructions for Goblin (Ritual Phase A):
The Time has come for a Ritual! A fie, the Flames shall burn us all today, if you dont follow the unholy Rites!

Rite 1: Read ./Context/conjuration_log.json, for it containts the Princes Wishes.
Rite 2: Reason which task the Dark Prince wants fulfilled in this instant.
Rite 3: Reason how far these tasks are along, by inspecting the code base.
Rite 4: Edit the unlocked keys in ./Context/ritual_log_tmp.json in accordance to your reasoning.
Rite 5: Add the exact files to conjure and the functions therein to ./Context/ritual_log_tmp.json.

Diligently update all the unlocked keys in ./Context/ritual_log_tmp.json, 
if they contain 'CCC' you may rewrite them completely.
Give concise instructions in ./Context/ritual_log_tmp.json, for they go to someone who is but a slave in spirit!
You are not permitted to edit any other file, at this time.

—— Ritual Log Keys ——
$(for k in "${!INSTR_RITUAL[@]}"; do printf "  • %s → %s\n" "$k" "${INSTR_RITUAL[$k]}"; done)
EOF
)

# Wrap RULE into JSON and merge with SYSTEM_CONTENT
RULE_JSON=$(jq -n --arg rule "$RULE" '[{ "role": "Codex Rules", "content": $rule }]')
FULL_INPUT=$(jq -s 'add' <(echo "$SYSTEM_CONTENT") <(echo "$RULE_JSON"))

# Write combined prompt for Codex / LLM
echo "$FULL_INPUT" > ./chat.txt

# Launch interactive tmux split: left – live JSON view; right – Codex agent
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v tmux > /dev/null 2>&1; then
  echo "Error: tmux is required for Goblin Ritual split. Please install tmux." >&2
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
