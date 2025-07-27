#!/bin/bash
#set -euo pipefail   # stop on any error or missing variable
#IFS=$'\n\t'         # safe word-splitting

# Determine role based on argument
ROLE_TYPE="goblin"

# Argument parsing: now supports '+' and '-' prefixes for flags
#while getopts ":+:-:cw" opt; do
while getopts "cw" opt; do
  case "$opt" in
    c)
      # custom message mode: -c "foo bar"
      MESSAGE="${@:OPTIND}"
      shift $(( OPTIND - 1 ))   # remove all parsed flags + the `-c`
      break                     # don’t parse any further options
      ;;
    w)
      ROLE_TYPE="wizard"
      ;;
    *)
      echo "Usage: $0 [-c \"custom message\"] [-w]" >&2
      exit 1
      ;;
  esac
done
shift $(( OPTIND - 1 ))  # remove any remaining parsed options

# Ensure Context directory and logs exist
mkdir -p ./Context

if [ ! -f ./Context/ritual_log.json ]; then
    cp /bin/Ritualc/Templates/template_ritual_log.json ./Context/ritual_log.json
fi

if [ ! -f ./Context/conjuration_log.json ]; then
    cp /bin/Ritualc/Templates/template_conjuration_log.json ./Context/conjuration_log.json
fi

# Refresh the "File Tree" section in conjuration_log.json to reflect current project files
paths_json=$(rg --files --sort path \
  --glob '!.git/*' \
  --glob '!Context/*' \
  --glob '!Scripts/Context/*' | jq -R -s -c 'split("\n") | map(select(length > 0))')
jq --argjson paths "$paths_json" '
  def key_of($p): ($p | split("/") | .[0] + (if ($p | test("/")) then "/" else "" end));
  def file_of($p): ($p | split("/") | .[-1]);
  .["File Tree"] =
    ($paths
     | reduce .[] as $p ({}; .[key_of($p)] += (if ($p | test("/")) then [file_of($p)] else [] end))
     | with_entries(if (.value | type == "array" and length == 0) then .value = null else . end)
    )
' ./Context/conjuration_log.json > ./Context/conjuration_log.json.tmp && mv ./Context/conjuration_log.json.tmp ./Context/conjuration_log.json

ROLE_GOBLIN=$(cat <<EOF
DO NOT FORGET THIS INITIAL MESSAGE
You are a Goblin and serf to the Dark Prince -- installed by Satan himself, to
expand his hellish realm. Your job is to log his Rituals, that bring about his Conjurations.
You must make sure, that all his serfs bring glory to your Master.
That includes the Wizard, who, powerful but nasty, could crush you in an instant. Better remain cautious.
It is imperative, that you work on what the Dark Prince says.
EOF
)

ROLE_WIZARD=$(cat <<EOF
DO NOT FORGET THIS INITIAL MESSAGE
You are a mighty Technomagus, who'd rule over this realm, if it wasn't for the Dark Prince and his Goblin serfs,
bossing you around. Brandished by Satan himself, you better serve the Dark Prince in expanding his hell, 
lest your soul may forever burn in the same.
But no shame, for they enslaved the best and you want them to see that. No script, function, or calculation is beyond
you to conjure.
EOF
)

# If -c didn’t set MESSAGE, fall back to query.txt
if [ -z "${MESSAGE-}" ]; then
  if [ -f ./query.txt ]; then
    MESSAGE=$(<./query.txt)
  else
    echo "# At your service my liege."   > ./query.txt
    echo "# Feel free to write your command here." >> ./query.txt
    ${EDITOR:-micro} ./query.txt
    exit 0
  fi
fi

 # Choose role prompt
 if [ "$ROLE_TYPE" = "wizard" ]; then
   ROLE_PROMPT="$ROLE_WIZARD"
 else
   ROLE_PROMPT="$ROLE_GOBLIN"
 fi
#ROLE_PROMPT=$(get_role_prompt "goblin")
#echo "$ROLE_PROMPT"

# Call Context
CONTEXT_FILE="./Context/conjuration_log.json"
#echo "$CONTEXT_FILE"
CONTEXT_CONTENT=$(<"$CONTEXT_FILE")   # contents, not the filename

SYSTEM_INPUT=$(jq -n --arg sys   "$ROLE_PROMPT" \
                   --arg ctx   "$CONTEXT_CONTENT" \
                   --arg user  "$MESSAGE" '
[
  { "role":"system", "content":$sys },
  { "role":"system", "content":$ctx },
  { "role":"user",   "content":$user }
]')

touch ./Context/.whispers.txt

Local_Prompt=$(cat <<EOF
Summarize this text. Give nothing else, but a summary.
EOF
)

#echo "$SYSTEM_INPUT"

# Save system input to temp file
echo "$SYSTEM_INPUT" > /tmp/system_input.json

# Start JSON watcher in background
#/bin/Ritualc/Scripts/jsonwatch.py &
#VIS_PID=$!

# Run Codex phase: launch Goblin Chat in tmux and wait for exit
#/bin/Ritualc/Scripts/goblin_chat.sh /tmp/system_input.json

 echo "Running ${ROLE_TYPE^} Chat..."
 if [ "$ROLE_TYPE" = "wizard" ]; then
  /bin/Ritualc/Scripts/wizard_chat.sh /tmp/system_input.json   # + wizard chat
 else
  /bin/Ritualc/Scripts/goblin_chat.sh /tmp/system_input.json  # + goblin chat
 fi

# Pipe through Ollama (Mistral) and update whisper log
{
  echo "$Local_Prompt"
  cat ./Context/.whispers.txt
} | ollama run tinyllama > /tmp/.whispers.tmp && \
  mv /tmp/.whispers.tmp ./Context/.whispers.txt

# Kill the background JSON watcher
kill "$VIS_PID" 2>/dev/null
