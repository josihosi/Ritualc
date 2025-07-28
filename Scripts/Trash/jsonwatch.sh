#!/usr/bin/env bash
FILE=${1:-./Context/conjuration_log.json}

spinner="/|\\-"  # animation frames
i=0

# ─────────────── Build baseline from current JSON ────────────────
BASE=/tmp/.jsonwatch_baseline.$$
jq -r '
  paths(scalars) as $p |
  "\($p | join(" → "))\t\(getpath($p))"
' "$FILE" > "$BASE"

# ─────────────── Terminal layout ────────────────
LINES=$(tput lines)            # total terminal rows
COLS=$(tput cols)              # total terminal cols
KEYW=$(( COLS/2 ))             # width of key column
table_top=2                    # table starts below header
header="📜 Conjuration dashboard  "
spin_col=${#header}            # column where spinner lives

# ─────────────── Centered printing with bias ────────────────
center () {
  local text="${1}" space pad BIAS=-20
  space=$(( COLS - KEYW - 2 )) # space for centered part
  [[ ${#text} -gt $space ]] && text="${text:0:space-3}…"
  pad=$(( (space - ${#text}) / 2 + BIAS ))
  (( pad < 0 )) && pad=0
  printf "%*s%s%*s" "$pad" '' "$text" "$(( space - pad - ${#text} ))" ''
}

# ─────────────── Static header printed once ────────────────
tput civis
tput clear
printf "%s[ ]\n" "$header"                           # row 0
printf '%*s\n' "$COLS" '' | tr ' ' '─'               # row 1 (rule)

# ─────────────── Live redraw loop ────────────────
while true; do
  # update spinner in-place
  tput cup 0 "$spin_col"
  printf "\033[2m%c\033[0m" "${spinner:i++%4:1}"

  # move to table start and clear below
  tput cup "$table_top" 0
  tput ed

  # flatten JSON into tmp file
  CUR=$(mktemp)
  jq -r '
    paths(scalars) as $p |
    "\($p | join(" → "))\t\(getpath($p))"
  ' "$FILE" > "$CUR"

  # draw table rows
  row=0
  while IFS=$'\t' read -r key val; do
    orig=$(grep -F "$key"$'\t' "$BASE" | cut -f2-)
    changed=$([[ "$val" != "$orig" ]] && echo 1 || echo 0)
    printf '• %-*s ' "$((KEYW-2))" "$key"
    if (( changed )); then
      printf '\033[33m'; center "$val"; printf '\033[0m\n'
    else
      center "$val"; echo
    fi
    ((row++))
  done < "$CUR"

  # pad to full height
  used=$(( row + table_top ))
  for (( r=used; r<LINES; r++ )); do echo; done

  rm -f "$CUR"
  sleep 1
done
