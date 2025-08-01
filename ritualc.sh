#!/bin/bash
#set -euo pipefail   # stop on any error or missing variable
#IFS=$'\n\t'         # safe word-splitting

# Argument parsing: now supports '+' and '-' prefixes for flags
#while getopts ":+:-:cw" opt; do
# Added support for -r (run ritual orchestration)
RUN_RITUAL=false
while getopts "cwr" opt; do
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
    r)
      RUN_RITUAL=true
      ;;
    *)
      echo "Usage: $0 [-c \"custom message\"] [-w] [-r]" >&2
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

if [ ! -f ./Context/ritual_log_tmp.json ]; then
    cp /bin/Ritualc/Templates/template_ritual_log.json ./Context/ritual_log_tmp.json
fi

# Determine role based on argument
ROLE_TYPE="goblin"

# Check if the ancient texts are readable
for file in ./Context/conjuration_log.json ./Context/ritual_log.json; do
  if ! jq . "$file" >/dev/null 2>&1; then
    echo "🧌 The ancient text '$file' is MUDDLED. Ritual aborted!"
    exit 1
  fi
done

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
DO NOT FORGET THIS MESSAGE
You are a Goblin and serf to the Dark Prince -- installed by Satan himself, to
expand his hellish realm. Your job is to log his Rituals, that bring about his Conjurations.
You must make sure, that all his serfs bring glory to your Master.
That includes the Wizard, who, powerful but nasty, could crush you in an instant. Better remain cautious.
It is imperative, that you work on what the Dark Prince says.
EOF
)

ROLE_WIZARD=$(cat <<EOF
DO NOT FORGET THIS MESSAGE
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
  { "role":"Codex Personality", "content":$sys },
  { "role":"Context", "content":$ctx },
  { "role":"Dark Prince",   "content":$user }
]')

echo "$SYSTEM_INPUT" > /tmp/system_input.json

ROLE_PROMPT="$ROLE_WIZARD"
SYSTEM_INPUT2=$(jq -n --arg sys   "$ROLE_PROMPT" \
                   --arg ctx   "$CONTEXT_CONTENT" \
                   --arg user  "$MESSAGE" '
[
  { "role":"Codex Personality", "content":$sys },
  { "role":"Context", "content":$ctx },
  { "role":"Dark Prince",   "content":$user }
]')
echo "$SYSTEM_INPUT2" > /tmp/system_input2.json

#Initiate context, not working well right now! :)
touch ./Context/.whispers.txt
Local_Prompt=$(cat <<EOF
You are a mystical machine, devised to condense information.
Summarize this text. Give nothing else, but a summary.
EOF
)

#echo "$SYSTEM_INPUT"
#echo "$SYSTEM_INPUT2"

# ---------------------------------------------------------
# If -r was provided, orchestrate the ritual helpers and exit.
# ---------------------------------------------------------
if [ "$RUN_RITUAL" = true ]; then
  echo "Starting ritual orchestration..."

  # Generate timestamp and session ID
  now_ts=$(date -Iseconds)  # ISO 8601 format, e.g. 2025-07-28T19:03:00+02:00
  session_id="Ritual_${now_ts//[^0-9]/}"  # Remove non-numbers

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git add .
    git commit -m "$session_id" || echo "🧌 No changes to commit."
  else
    echo "⚠️ Not in a Git repo — skipping commit."
  fi

  # Inject Session ID and Initialization Timestamp into ritual_log_tmp
  tmpfile="./Context/ritual_log_tmp.json"

  jq --arg session_id "$session_id" \
     --arg timestamp "$now_ts" \
     '.["0 Ritual ID"] = $session_id
      | .["1 Initialization"].Timestamp = $timestamp' \
     "$tmpfile" > "${tmpfile}.patched" && mv "${tmpfile}.patched" "$tmpfile"



  # Use the canonical /bin/Ritualc path that mirrors this repository
  RITUAL_SCRIPTS_DIR="/bin/Ritualc/Scripts"

	##### RITUAL STEP A, GOBLIN RITUALISTIC REVIEW ######
  bash "$RITUAL_SCRIPTS_DIR/goblin_ritual_A.sh" /tmp/system_input.json

  # Pipe through Ollama (Mistral) and update whisper log
  {
    echo "$Local_Prompt"
    cat ./Context/.whispers.txt
  } | ollama run tinyllama > /tmp/.whispers.tmp && \
    mv /tmp/.whispers.tmp ./Context/.whispers.txt
    
	##### RITUAL STEP B, WIZARD WORKS HIS MAGIC ######
  bash "$RITUAL_SCRIPTS_DIR/wizard_ritual.sh" /tmp/system_input2.json
  
    ##### RITUAL STEP C, GOBLIN MARKS CHANGES ######
  bash "$RITUAL_SCRIPTS_DIR/goblin_ritual_B.sh" /tmp/system_input.json
  # Set the ritual ID (same as in "0 Ritual ID")
  ritual_id=$(jq -r '."0 Ritual ID"' ./Context/ritual_log_tmp.json)

     # Extract Git metadata
   commit_hash=$(git rev-parse HEAD)
   branch_name=$(git rev-parse --abbrev-ref HEAD)
   dirty=$(if git diff --quiet && git diff --cached --quiet; then echo false; else echo true; fi)
   
   # Create a raw diff snapshot
   diff_path=".codex_memory/diffs/${session_id}.diff"
   mkdir -p "$(dirname "$diff_path")"
   git diff HEAD > "$diff_path"
   diff_hash=$(sha256sum "$diff_path" | awk '{print $1}')

   jq --arg commit "$commit_hash" \
      --arg branch "$branch_name" \
      --arg diff_path "$diff_path" \
      --arg diff_hash "sha256:$diff_hash" \
      --argjson dirty "$dirty" \
      '.["4 Metadata"].Git = {
         "Commit": $commit,
         "Branch": $branch,
         "Raw Diff Hash": $diff_hash,
         "Raw Diff Path": $diff_path,
         "Dirty": $dirty
       }' "$tmpfile" > "${tmpfile}.patched" && mv "${tmpfile}.patched" "$tmpfile"
   

  # Merge, putting the new ritual first
  jq --arg rid "$ritual_id" \
     --slurpfile new ./Context/ritual_log_tmp.json \
     '{
        ($rid): $new[0]
      } + .' ./Context/ritual_log.json \
  > ./Context/ritual_log_merged.json &&
  mv ./Context/ritual_log_merged.json ./Context/ritual_log.json &&
  rm ./Context/ritual_log_tmp.json
  
    # Pipe through Ollama (Mistral) and update whisper log
  {
    echo "$Local_Prompt"
    cat ./Context/.whispers.txt
  } | ollama run tinyllama > /tmp/.whispers.tmp && \
    mv /tmp/.whispers.tmp ./Context/.whispers.txt
  
  exit 0
fi

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
