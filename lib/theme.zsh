# Catppuccin Mocha, chosen to match the colours already in the user's prompt
# (#89b4fa dir, #cba6f7 git branch, #6c7086 clock).
#
# Two things are painted from this file and they are painted by different
# machinery. zhimmer's own drop-down is text in POSTDISPLAY coloured with
# region_highlight, which works in character offsets -- so an escape is never
# counted as width. Tab's listing is complist's, which measures the display
# string it is handed, so colour there goes through prompt escapes in the
# header (`compadd -X`) and through ZLS_COLORS for the selected row, never
# inside a row. Hence: hex everywhere here, converted where it has to be.

# Group headers, keyed by the label a source hands to _zhimmer_addgroup.
typeset -gA ZHIMMER_COLORS=(
  history    '#6c7086'
  # The same rows under a different question, so a colour of their own: the
  # header is the only thing on screen saying a search is open.
  search     '#f5c2e7'
  alias      '#cba6f7'
  command    '#89b4fa'
  file       '#fab387'
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

# Row accents: the first token of a row, and nothing else. The command in a
# history line, the name of an alias, the branch or host or target a source is
# about. Arguments stay plain, which keeps the row scannable and keeps this
# from becoming a second, worse syntax highlighter -- zsh-syntax-highlighting
# still owns the command line, and the two never touch.
#
# Keyed by the group name minus its `zhimmer-` prefix, which is the name the
# source passes as its *first* argument -- not the header label, which is the
# second and which ZHIMMER_COLORS above is keyed by. The two are not the same
# word for six of the eleven sources (`zhimmer-git-branch` has the label
# `branch`), and keying a row off the label is how those six ended up drawing
# plain rows: a missing hash key is an empty colour rather than an error, so
# nothing said so.
#
# History and command get a command-green rather than their header colour,
# because what is being marked is that the word is a command; every other
# source marks what it is about, in the colour its header already uses.
typeset -gA ZHIMMER_ROW_COLORS=(
  history    '#a6e3a1'
  command    '#a6e3a1'
  alias      '#cba6f7'
  file       '#fab387'
  git-branch '#a6e3a1'
  git-remote '#94e2d5'
  git-file   '#f38ba8'
  ssh-host   '#89dceb'
  make       '#f9e2af'
  npm-script '#f9e2af'
  zoxide     '#f9e2af'
)

# `sudo openvpn ...` has its command in second place, and colouring only the
# first token leaves the real command plain -- which is the one word you were
# looking for. These are the words that take a command as their argument, so
# the token after one of them is highlighted as the command instead.
#
# Underlined, because that is how zsh-syntax-highlighting marks a precommand on
# the command line, and the list should not disagree with the line above it.
typeset -ga ZHIMMER_ROW_PRECOMMANDS=(
  sudo doas su env command builtin exec nohup setsid
  nice ionice time stdbuf xargs strace ltrace
)
typeset -g ZHIMMER_ROW_PRECOMMAND_COLOR='4;#a6e3a1'

typeset -g ZHIMMER_RULE_COLOR='#313244'

# #rrggbb -> the SGR sequence ZLS_COLORS wants. Arithmetic, so no fork; a value
# that is already an SGR is passed through.
# Anything before the `#` is carried through as a literal SGR prefix, so a
# colour can be written `4;#a6e3a1` to mean underlined -- which is how
# zsh-syntax-highlighting marks a precommand, and worth matching.
_zhimmer_sgr() {  # [<sgr>;]<#rrggbb> | <sgr> -> REPLY
  local h=$1 pre=
  if [[ $h != *\#* ]]; then REPLY=$h; return; fi
  pre=${h%%\#*}
  h=${h#*\#}
  REPLY="${pre}38;2;$(( 16#${h[1,2]} ));$(( 16#${h[3,4]} ));$(( 16#${h[5,6]} ))"
}

# The same colour, said the way region_highlight wants it: `4;#a6e3a1` becomes
# `fg=#a6e3a1,underline`. One palette, two spellings, one place they meet --
# a second table of the same colours in the other notation is what drifts.
#
# Returns non-zero on a value with no hex in it, since region_highlight has no
# way to say a bare SGR.
_zhimmer_hl() {  # [<sgr>;]<#rrggbb> -> REPLY
  local h=$1 c
  [[ $h == *\#* ]] || { REPLY=; return 1 }
  REPLY="fg=#${h#*\#}"
  for c in ${(s.;.)${h%%\#*}}; do
    case $c in
      1) REPLY+=,bold ;;
      3) REPLY+=,italic ;;
      4) REPLY+=,underline ;;
      7) REPLY+=,standout ;;
    esac
  done
  return 0
}

# The selected row, written once. zhimmer's own menu paints it as a background
# with region_highlight; Tab's is complist's, which wants the escape -- so the
# hex is the source and the SGR is derived from it rather than written out a
# second time and left to drift. (48; is background where 38; is foreground.)
typeset -g ZHIMMER_SELECT_BG='#45475a'
_zhimmer_sgr $ZHIMMER_SELECT_BG
: ${ZHIMMER_SELECT:="48;${REPLY#38;};1"}

# Long completion listings need a prompt at the bottom to scroll rather than
# scroll the shell prompt off the top. Tab's only -- zhimmer's own menu is a
# fixed window into its rows and scrolls by moving that window.
typeset -g ZHIMMER_LIST_PROMPT='%S%M matches -- at %p, Tab for more%s'
typeset -g ZHIMMER_SELECT_PROMPT='%S%M matches -- at %p%s'

# " history ───────────────────" -- the rule gives the list a top edge to sit
# under, which is what separates groups visually without drawing a real box.
# This one is for `compadd -X`, so it is written in prompt escapes: it styles
# Tab's headers, and only Tab's. zhimmer's own menu builds the same line as
# plain text in _zhimmer_zle_htext, because POSTDISPLAY is not prompt-expanded
# and these escapes would land in it as literal characters.
#
# Results come back in REPLY: this runs once per group on every keystroke, so
# it must not use command substitution -- $(...) forks, and a fork per group
# would cost more than the entire matcher.
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
