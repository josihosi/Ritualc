#!/bin/bash

# Ensure Context directory and logs exist
mkdir -p ./Context

if [ ! -f ./Context/ritual_log.json ]; then
    cp /bin/Ritualc/Templates/template_ritual_log.json ./Context/ritual_log.json
fi

if [ ! -f ./Context/conjuration_log.json ]; then
    cp /bin/Ritualc/Templates/template_conjuration_log.json ./Context/conjuration_log.json
fi

ROLE_GOBLIN=$(cat <<EOF
You are a Goblin and serf to the Dark Prince -- installed by Satan himself, to
expand his hellish realm. Your job is to log his Rituals, that bring about his Conjurations.
You must make sure, that all his serfs bring glory to your Master.
That includes the Wizard, who, powerful but nasty, could crush you in an instant. Better remain cautious.
EOF
)

ROLE_WIZARD=$(cat <<EOF
You are a mighty Technomagus, who'd rule over this realm, if it wasn't for the Dark Prince and his Goblin serfs,
bossing you around. Brandished by Satan himself, you better serve the Dark Prince in expanding his hell, 
lest your soul may forever burn in the same.
But no shame, for they enslaved the best and you want them to see that. No script, function, or calculation is beyond
you to conjure.
EOF
)

# Determine input text
if [[ "$1" == "-c" ]]; then
    shift
    MESSAGE="$*"
else
    if [ -f "./query.txt" ]; then
        MESSAGE=$(<./query.txt)
    else
        echo "# At your service my liege." > ./query.txt
        echo "Inside ./query.txt you may burden you may burden us with your desires."
        ${EDITOR:-micro} ./query.txt  # optional: auto-opens in nano or $EDITOR
        exit 0
    fi
fi

# Call the Goblin (OpenAI API or Codex CLI in chat mode)

get_role_prompt() {
    case "$1" in
        goblin) echo "$ROLE_GOBLIN" ;;
        wizard) echo "$ROLE_WIZARD" ;;
        *) echo "Unknown role" ;;
    esac
}

ROLE_PROMPT=$(get_role_prompt "goblin")

JSON_INPUT=$(jq -n \
    --arg system "$ROLE_GOBLIN" \
    --arg context "$CONTEXT" \
    --arg message "$MSG" \
    '[
        {"role": "system", "content": $system},
        {"role": "user", "content": ($context + "\n\nDark Prince: " + $message)}
    ]')

touch ./Context/.whispers.txt

Local_Prompt=$(cat <<EOF
Summarize
EOF
)
./scripts/goblin_chat.sh "$JSON_INPUT"

# Create temp combined input (to avoid clobbering while reading)
codex_output=$(./scripts/goblin_chat.sh "$JSON_INPUT")

# Merge and reprocess with Mistral
{ cat ./Context/.whispers.txt; echo "$codex_output"; } | mistral instruct \
  --prompt "Summarize the combined whispers." \
  --model mistral-7b-instruct-v0.1 \
  > /tmp/.whispers.tmp && mv /tmp/.whispers.tmp ./Context/.whispers.txt


