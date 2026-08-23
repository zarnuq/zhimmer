# Catppuccin Mocha, chosen to match the colours already in the user's prompt
# (#89b4fa dir, #cba6f7 git branch, #6c7086 clock).
#
# Group headers go through compadd -X, which honours prompt escapes including
# truecolor %F{#rrggbb}. Row text does not: display strings are laid out by
# width, so colour inside them is unreliable. Hence the palette is spent on
# headers and on the selection bar, and rows stay plain.

typeset -gA ZHIMMER_COLORS=(
  history    '#6c7086'
  alias      '#cba6f7'
  command    '#89b4fa'
  file       '#fab387'
  git-branch '#a6e3a1'
  zoxide     '#f9e2af'
)
typeset -g ZHIMMER_RULE_COLOR='#313244'

# ma= is the selected match. Set on ZLS_COLORS rather than the list-colors style
# because a raw zle -C widget never goes through the completion system.
: ${ZHIMMER_SELECT:='48;2;69;71;90;1'}
typeset -g ZLS_COLORS="ma=${ZHIMMER_SELECT}"

# " history ───────────────────" -- the rule gives the list a top edge to sit
# under, which is what separates groups visually without drawing a real box.
# Results come back in REPLY. These run once per group and once per row on every
# keystroke, so they must not use command substitution -- $(...) forks, and a
# fork per row would cost more than the entire matcher.
_zhimmer_header() {
  local name=$1
  local color=${ZHIMMER_COLORS[$name]:-'#6c7086'}
  local -i w=$(( COLUMNS - ${#name} - 4 ))
  (( w < 0 )) && w=0
  REPLY="%F{$color}%B ${name}%b%f %F{$ZHIMMER_RULE_COLOR}${(l:w::─:):-}%f"
}

# Rows are indented and padded to the full width so the selection reads as a
# solid bar rather than ragged text, and truncated so a long path cannot wrap
# onto a second line and desynchronise the layout from the menu.
_zhimmer_row() {
  local t="  $1"
  local -i w=$(( COLUMNS - 1 ))
  (( w < 10 )) && w=10
  (( ${#t} > w )) && t="${t[1,w-1]}…"
  REPLY="${(r:w:)t}"
}
