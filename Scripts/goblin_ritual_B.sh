#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Goblin Ritual B – final Goblin pass over ritual_log.json.

if [ ! -f ./Context/ritual_log.json ]; then
  cp /bin/Ritualc/Templates/template_ritual_log.json ./Context/ritual_log.json
fi

if [ $# -gt 0 ]; then
  SYSTEM_INPUT_FILE="$1"
  SYSTEM_CONTENT=$(<"$SYSTEM_INPUT_FILE")
else
  SYSTEM_CONTENT='[{"role":"system","content":"Ritual orchestration mode."}]'
fi

TEMPLATE="./Context/ritual_log.json"

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
Instructions for Goblin (Ritual Phase B – Review):

The wizard has applied changes. Review BOTH ./Context/ritual_log.json and ./Context/conjuration_log.json.
Ensure all DDD placeholders are replaced with meaningful summaries and semantic diffs.

Consult ./Context/.whispers.txt for additional context.

—— Conjuration Log Keys ——
$(for k in "${!INSTR_CONJ[@]}"; do printf "  • %s → %s\n" "$k" "${INSTR_CONJ[$k]}"; done)

—— Ritual Log Keys ——
$(for k in "${!INSTR_RITUAL[@]}"; do printf "  • %s → %s\n" "$k" "${INSTR_RITUAL[$k]}"; done)
EOF
)

RULE_JSON=$(jq -n --arg rule "$RULE" '[{ "role": "system", "content": $rule }]')
FULL_INPUT=$(jq -s 'add' <(echo "$SYSTEM_CONTENT") <(echo "$RULE_JSON"))

echo "$FULL_INPUT" > ./chat.txt

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v tmux > /dev/null 2>&1; then
  echo "Error: tmux is required for Goblin Ritual split." >&2
  exit 1
fi

tmux set-option -g mouse on 2>/dev/null || true
tmux set-window-option -g mouse on 2>/dev/null || true

SESSION_NAME="goblin_ritual_B"

if [ -n "${TMUX-}" ]; then
  CURRENT_SESSION=$(tmux display-message -p '#{session_name}')
  if tmux list-windows -t "$CURRENT_SESSION" -F "#{window_name}" | grep -q "^$SESSION_NAME$"; then
    tmux kill-window -t "${CURRENT_SESSION}:$SESSION_NAME"
  fi
  tmux new-window -n "$SESSION_NAME" -t "$CURRENT_SESSION" "bash -lc 'python3 \"$SCRIPT_DIR/jsonwatch_render.py\" \"$TEMPLATE\"; exec bash'"
  tmux split-window -h -d -t "${CURRENT_SESSION}:$SESSION_NAME" "bash -lc 'codex --full-auto \"read ./chat.txt and follow instructions.\" | tee -a ./Context/.whispers.txt; rm ./chat.txt; exec bash'"
  tmux select-layout -t "${CURRENT_SESSION}:$SESSION_NAME" even-horizontal
  tmux select-window -t "${CURRENT_SESSION}:$SESSION_NAME"
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
