#!/bin/bash
set -euo pipefail   # stop on any error or missing variable
IFS=$'\n\t'         # safe word-splitting

#echo "Goblin invoked"

if [ ! -f ./Context/conjuration_log.json ]; then
  cp /bin/Ritualc/Templates/template_conjuration_log.json ./Context/conjuration_log.json
fi

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
Fill in the keys, according to the Dark Lords wishes.
If you don't know what he is talking about, you may read ./Context/.whispers.txt

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
 RULE_JSON=$(jq -n --arg rule "$RULE" '[{ "role": "system", "content": $rule }]')

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

codex e "Read ./chat.txt and apply." | tee ./Context/.whispers.txt #| tee /dev/tty

rm ./chat.txt
