#!/usr/bin/env bash
set -euo pipefail

SESSION="codexwatch"
CONJ_JSON=./Context/conjuration_log.json
TMPLOG=$(mktemp)
trap 'rm -f "$TMPLOG"; tmux kill-session -t "$SESSION" 2>/dev/null || true' EXIT

# 1. Start a new detached tmux session
tmux new-session -d -s "$SESSION"

# 2. In the *left* pane (pane 0), run your JSON watcher
tmux send-keys -t "$SESSION":0.0 \
  "python3 /bin/Ritualc/Scripts/jsonwatch_render.py $CONJ_JSON $TMPLOG" C-m

# 3. Split vertically, giving you a *right* pane (pane 0.1)
tmux split-window -h -t "$SESSION":0

# 4. In the right pane, run Goblin Chat *interactively* while tee’ing its output
tmux send-keys -t "$SESSION":0.1 \
  "/bin/Ritualc/Scripts/goblin_chat.sh /tmp/system_input.json | tee $TMPLOG" C-m

# 5. Attach so you land in your two-pane setup
tmux attach -t "$SESSION"
