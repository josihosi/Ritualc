#!/usr/bin/env bash
set -euo pipefail

SESSION="codexwatch"
# LOGFILE="/tmp/codex_out.log"  # not used

# 1. Resolve all the paths, no more magic relative CWD guesses
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Project root is two levels up from scripts dir
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONJ_JSON="$PROJECT_ROOT/Context/conjuration_log.json"
CHAT_FILE="$PROJECT_ROOT/chat.txt"

# 2. Clean up any stale session & logfile
tmux kill-session -t "$SESSION" 2>/dev/null || true

# 3. Create the session, starting at your project root, but leave you at a shell.
tmux new-session -d -s "$SESSION" -c "$PROJECT_ROOT"

# 4. Pane 0 (left): fire up the JSON‐watcher
tmux send-keys -t "$SESSION":0.0 \
  "bash -lc 'python3 \"$SCRIPT_DIR/jsonwatch_render.py\" \"$CONJ_JSON\" \"$LOGFILE\"'" C-m

# 5. Split vertically, pane 1 (right): Goblin Chat + tee
tmux split-window -h -t "$SESSION":0 -c "$PROJECT_ROOT"
tmux send-keys -t "$SESSION":0.1 \
  "bash -lc '\"$SCRIPT_DIR/goblin_chat.sh\" \"$SYSTEM_INPUT\" | tee \"$LOGFILE\"'" C-m

# 6. Finally, attach you into the session
tmux attach -t "$SESSION"
