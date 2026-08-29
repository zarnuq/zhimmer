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
  branch     '#a6e3a1'
  remote     '#94e2d5'
  changed    '#f38ba8'
  host       '#89dceb'
  target     '#f9e2af'
  script     '#f9e2af'
  zoxide     '#f9e2af'
  # Tab's own groups, named by completion tag once group-name is set.
  files      '#fab387'
  directories '#fab387'
  options    '#89b4fa'
  commands   '#89b4fa'
  branches   '#a6e3a1'
  parameters '#cba6f7'
)
# Tab's groups are named by completion tag; a few of those are zsh's internals
# rather than words, and read better spelled out.
typeset -gA ZHIMMER_GROUP_LABELS=(
  globbed-files    files
  all-files        files
  other-files      files
  common-commands  commands
  all-commands     commands
  original-array   parameters
)

typeset -g ZHIMMER_RULE_COLOR='#313244'

# ma= is the selected match. Set on ZLS_COLORS rather than the list-colors style
# because a raw zle -C widget never goes through the completion system.
: ${ZHIMMER_SELECT:='48;2;69;71;90;1'}
typeset -g ZLS_COLORS="ma=${ZHIMMER_SELECT}"

# Menu selection scrolls once the list outgrows the screen -- but only if it has
# a prompt to show at the bottom. Without MENUPROMPT the top of an over-long
# menu, and the shell prompt above it, simply scroll away. Set on the parameters
# rather than the select-prompt and select-scroll styles for the same reason as
# ZLS_COLORS: a raw zle -C widget never goes through the completion system.
#
# Tab's own long lists say the same thing in the same words, through the
# list-prompt style (see _zhimmer_tame_lists), so the wording is written here
# once rather than kept in step in two files.
typeset -g ZHIMMER_MATCH_PROMPT='%M matches -- at %p'
: ${MENUPROMPT="%S${ZHIMMER_MATCH_PROMPT}%s"}
: ${MENUSCROLL=1}
: ${ZHIMMER_LIST_PROMPT="%S${ZHIMMER_MATCH_PROMPT}, Tab for more%s"}

# " history ───────────────────" -- the rule gives the list a top edge to sit
# under, which is what separates groups visually without drawing a real box.
# Results come back in REPLY. These run once per group and once per row on every
# keystroke, so they must not use command substitution -- $(...) forks, and a
# fork per row would cost more than the entire matcher.
_zhimmer_header() {
  local name=$1
  local color=${ZHIMMER_COLORS[$name]:-'#6c7086'}
  local -i w=$(( COLUMNS - ${(m)#name} - 4 ))
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
  # Columns, not characters. `~/文書/notes.txt` is 14 of one and 16 of the
  # other, so counting characters under-padded the bar and let a row run past
  # the right edge onto a second line -- the exact desync the truncation is
  # here to prevent. (m) counts what the terminal will actually draw.
  #
  # Two columns are held back rather than one because a cut that lands inside a
  # double-width character keeps that character whole: truncating to w-1 can
  # come back w wide, and the ellipsis would then make it w+1.
  if (( ${(m)#t} > w )); then
    local -i n=$(( w - 2 ))
    t="${(mr:n:)t}…"
  fi
  REPLY="${(mr:w:)t}"
}
