# Catppuccin Mocha. Two painters read this: zhimmer's own menu (region_highlight,
# by character offset) and Tab's complist listing (prompt escapes in `compadd -X`
# headers, ZLS_COLORS for the selected row). Escapes never go inside a row.

# Group headers, keyed by the *label* a source passes second (`branch`).
typeset -gA ZHIMMER_COLORS=(
  history    '#6c7086'
  search     '#f5c2e7'   # the only thing on screen saying a search is open
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
# Completion tags that are zsh internals rather than words.
typeset -gA ZHIMMER_GROUP_LABELS=(
  globbed-files    files
  all-files        files
  other-files      files
  common-commands  commands
  all-commands     commands
  original-array   parameters
)

# Row accents on the first token only, keyed by the *group* minus `zhimmer-`
# (`git-branch`), not the label. The two differ for six sources and a missing
# key is a silent empty colour; test/unit.zsh checks both tables cover them.
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

# After one of these the *next* token is the command (`sudo openvpn`), and the
# precommand itself is underlined, as zsh-syntax-highlighting marks it.
typeset -ga ZHIMMER_ROW_PRECOMMANDS=(
  sudo doas su env command builtin exec nohup setsid
  nice ionice time stdbuf xargs strace ltrace
)
typeset -g ZHIMMER_ROW_PRECOMMAND_COLOR='fg=#a6e3a1,underline'   # region_highlight spec

typeset -g ZHIMMER_RULE_COLOR='#313244'
typeset -g ZHIMMER_HEADER_COLOR='#6c7086'   # a label with no ZHIMMER_COLORS entry

# [<sgr>;]#rrggbb -> SGR for ZLS_COLORS, by arithmetic (no fork). A bare SGR
# passes through.
_zhimmer_sgr() {  # -> REPLY
  local h=$1 pre=
  if [[ $h != *\#* ]]; then REPLY=$h; return; fi
  pre=${h%%\#*}
  h=${h#*\#}
  REPLY="${pre}38;2;$(( 16#${h[1,2]} ));$(( 16#${h[3,4]} ));$(( 16#${h[5,6]} ))"
}

# The selection bar, written once in hex and derived for complist. A theme file
# that changes ZHIMMER_SELECT_BG calls this again.
typeset -g ZHIMMER_SELECT_BG='#45475a'
_zhimmer_select_from_bg() {
  _zhimmer_sgr $ZHIMMER_SELECT_BG
  ZHIMMER_SELECT="48;${REPLY#38;};1"
}
[[ -n $ZHIMMER_SELECT ]] || _zhimmer_select_from_bg

# Tab's listing only; zhimmer's menu scrolls by moving its window.
typeset -g ZHIMMER_LIST_PROMPT='%S%M matches -- at %p, Tab for more%s'
typeset -g ZHIMMER_SELECT_PROMPT='%S%M matches -- at %p%s'

# " name ─────" as prompt escapes, for `compadd -X` (Tab) only. POSTDISPLAY is
# not prompt-expanded, so the menu uses the plain _zhimmer_zle_htext instead.
_zhimmer_header() {  # <label> -> REPLY
  _zhimmer_zle_htext $1
  REPLY="%F{${ZHIMMER_COLORS[$1]:-$ZHIMMER_HEADER_COLOR}}%B ${1}%b%f %F{$ZHIMMER_RULE_COLOR}${REPLY:$(( ${#1} + 2 ))}%f"
}

# Indented, padded to full width so the selection is a solid bar, truncated so
# a row never wraps. Measured in columns, (m), not characters: CJK and emoji
# are two wide. Two columns are held back because a cut inside a wide
# character keeps it whole.
_zhimmer_row() {  # <text> -> REPLY
  local t="  $1"
  local -i w=$(( COLUMNS - 1 ))
  (( w < 10 )) && w=10
  if (( ${(m)#t} > w )); then
    local -i n=$(( w - 2 ))
    t="${(mr:n:)t}…"
  fi
  REPLY="${(mr:w:)t}"
}
