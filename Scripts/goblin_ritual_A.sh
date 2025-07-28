#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Goblin Ritual A – largely identical to goblin_chat.sh but operates on the ritual log.

# Ensure ritual log exists
# Ensure both ritual and conjuration logs exist
if [ ! -f ./Context/ritual_log.json ]; then
  cp /bin/Ritualc/Templates/template_ritual_log.json ./Context/ritual_log.json
fi
if [ ! -f ./Context/conjuration_log.json ]; then
  cp /bin/Ritualc/Templates/template_conjuration_log.json ./Context/conjuration_log.json
fi

# Expect path to system input JSON from caller (ritualc.sh provides this)
# Allow optional system-input JSON. If not supplied, create a fallback prompt.
if [ $# -gt 0 ]; then
  SYSTEM_INPUT_FILE="$1"
  SYSTEM_CONTENT=$(<"$SYSTEM_INPUT_FILE")
else
  SYSTEM_CONTENT='[{"role":"system","content":"Ritual orchestration mode."}]'
fi

TEMPLATE="./Context/ritual_log.json"

# ---------------------------------------------------------------------------
# Collect placeholder instructions (DDD) from BOTH template JSON files
# ---------------------------------------------------------------------------

declare -A INSTR_RITUAL  # placeholders from template_ritual_log.json
declare -A INSTR_CONJ    # placeholders from template_conjuration_log.json

extract_placeholders() {
  local tmpl_path="$1"
  local -n _dest=$2

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

# Build RULE string shown to Goblin
RULE=$(cat <<EOF
Instructions for Goblin (Ritual Phase A):

You’re supposed to update BOTH ./Context/ritual_log.json and ./Context/conjuration_log.json.
Consult ./Context/.whispers.txt for background if needed.

You are not permitted to edit any other file outside a ritual.

Read the unlocked keys and replace any placeholder beginning with DDD.

—— Conjuration Log Keys ——
$(for k in "${!INSTR_CONJ[@]}"; do printf "  • %s → %s\n" "$k" "${INSTR_CONJ[$k]}"; done)

—— Ritual Log Keys ——
$(for k in "${!INSTR_RITUAL[@]}"; do printf "  • %s → %s\n" "$k" "${INSTR_RITUAL[$k]}"; done)
EOF
)

# Wrap RULE into JSON and merge with SYSTEM_CONTENT
RULE_JSON=$(jq -n --arg rule "$RULE" '[{ "role": "system", "content": $rule }]')
FULL_INPUT=$(jq -s 'add' <(echo "$SYSTEM_CONTENT") <(echo "$RULE_JSON"))

# Write combined prompt for Codex / LLM
echo "$FULL_INPUT" > ./chat.txt

# Launch interactive tmux split: left – live JSON view; right – Codex agent
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v tmux > /dev/null 2>&1; then
  echo "Error: tmux is required for Goblin Ritual split. Please install tmux." >&2
  exit 1
fi

tmux set-option -g mouse on 2>/dev/null || true
tmux set-window-option -g mouse on 2>/dev/null || true

SESSION_NAME="goblin_ritual_A"

# Kill existing session/window if present
if [ -n "${TMUX-}" ]; then
  CURRENT_SESSION=$(tmux display-message -p '#{session_name}')
  if tmux list-windows -t "$CURRENT_SESSION" -F "#{window_name}" | grep -q "^$SESSION_NAME$"; then
    tmux kill-window -t "${CURRENT_SESSION}:$SESSION_NAME"
  fi
  tmux new-window -n "$SESSION_NAME" -t "$CURRENT_SESSION" "bash -lc 'python3 \"$SCRIPT_DIR/jsonwatch_render.py\" \"$TEMPLATE\"; exec bash'"
  tmux split-window -h -d -t "${CURRENT_SESSION}:$SESSION_NAME" "bash -lc 'codex --full-auto \"read ./chat.txt and follow instructions.\" | tee -a ./Context/.whispers.txt; rm ./chat.txt; exec bash'"
  tmux select-layout -t "${CURRENT_SESSION}:$SESSION_NAME" even-horizontal
  tmux select-window -t "${CURRENT_SESSION}:$SESSION_NAME"
  # Wait for user to quit via 'q'
  while tmux list-windows -t "$CURRENT_SESSION" -F "#{window_name}" | grep -q "^$SESSION_NAME$"; do
    sleep 0.5
  done
else
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux kill-session -t "$SESSION_NAME"
  fi
  tmux new-session -d -s "$SESSION_NAME" "bash -lc 'python3 \"$SCRIPT_DIR/jsonwatch_render.py\" \"$TEMPLATE\"; exec bash'"
  tmux split-window -h -d -t "$SESSION_NAME" "bash -lc 'codex --full-auto \"read ./chat.txt and follow instructions.\" | tee -a ./Context/.whispers.txt; rm ./chat.txt; exec bash'"
  tmux select-layout -t "$SESSION_NAME" even-horizontal
  tmux attach -t "$SESSION_NAME"
fi
