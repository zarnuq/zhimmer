# The drop-down, drawn into POSTDISPLAY and coloured with region_highlight.
#
# Not complist: its interactive mode (the only way to filter an open menu)
# resets on every movement key and draws an `interactive: []` row, so it
# flickers. Here there is no mode -- typing recomputes, arrows move an index.
# region_highlight paints by character offset, so escapes never count as width.

# Parallel arrays, not packed records: row text can hold any separator.
typeset -ga _zhimmer_zrow=()    # text, unpadded
typeset -ga _zhimmer_zkind=()   # group name, '' for a header
typeset -ga _zhimmer_zbuf=()    # the whole BUFFER this row would leave behind
typeset -gi _zhimmer_zsel=0     # selected index, 0 for none
typeset -gi _zhimmer_ztop=1     # first row shown

# The greyed tail, kept apart from POSTDISPLAY (which also holds every row):
# the accept keys once took all of POSTDISPLAY, menu and all, into BUFFER.
typeset -g _zhimmer_zghost=

_zhimmer_zle_reset() {
  _zhimmer_zrow=() _zhimmer_zkind=() _zhimmer_zbuf=()
  _zhimmer_zsel=0 _zhimmer_ztop=1
}

# Rows that fit, as reply=(first last). The window moves only when the
# selection would leave it.
_zhimmer_zle_window() {  # <total> <selected> <height> <current-first> -> reply
  local -i n=$1 sel=$2 h=$3 first=$4
  (( h < 1 )) && h=1
  typeset -ga reply
  (( n <= h )) && { reply=( 1 $n ); return }
  (( sel && sel < first ))         && first=$sel
  (( sel && sel > first + h - 1 )) && first=$(( sel - h + 1 ))
  (( first > n - h + 1 ))          && first=$(( n - h + 1 ))
  (( first < 1 ))                  && first=1
  reply=( $first $(( first + h - 1 )) )
}

_zhimmer_zle_add() {  # <row text> [<group> <resulting buffer>]; no group = header
  _zhimmer_zrow+=( "$1" ); _zhimmer_zkind+=( "$2" ); _zhimmer_zbuf+=( "$3" )
}

# Next selectable row, wrapping, skipping headers. Gives up after one lap so a
# list of only headers cannot spin.
_zhimmer_zle_next() {  # <from> <step> -> REPLY, 0 when there is nothing to take
  local -i i=$1 step=$2 n=$#_zhimmer_zrow lap
  for (( lap = 0; lap < n; lap++ )); do
    (( i += step ))
    (( i > n )) && i=1
    (( i < 1 )) && i=n
    [[ -n $_zhimmer_zkind[i] ]] && { REPLY=$i; return 0 }
  done
  REPLY=0; return 1
}

# A header as plain text. Not _zhimmer_header: its prompt escapes would land in
# POSTDISPLAY as literal characters.
_zhimmer_zle_htext() {  # <label> -> REPLY
  local name=$1
  local -i w=$(( COLUMNS - ${(m)#name} - 4 ))
  (( w < 0 )) && w=0
  REPLY=" ${name} ${(l:w::─:):-}"
}

# Ghost on the first line, rows under it. Rebuilt from scratch each time, so a
# resize is picked up on the next keystroke. The memo lets the guard drop only
# zhimmer's highlights, not zsh-syntax-highlighting's.
_zhimmer_zle_draw() {
  region_highlight=( ${region_highlight:#*memo=zhimmer*} )
  local -i base=${#BUFFER}
  local out=$_zhimmer_zghost REPLY
  local -i pos=$(( base + ${#_zhimmer_zghost} ))
  if [[ -n $_zhimmer_zghost ]]; then
    _zhimmer_cfg ghost-color
    region_highlight+=( "$base $pos $REPLY,memo=zhimmer" )
  fi

  (( $#_zhimmer_zrow )) || { POSTDISPLAY=$out; return 0 }

  local -i accents=0
  _zhimmer_bool row-colors && accents=1

  local -a reply
  _zhimmer_zle_window $#_zhimmer_zrow $_zhimmer_zsel $(( LINES - 4 )) $_zhimmer_ztop
  _zhimmer_ztop=$reply[1]
  local -i i first=$reply[1] last=$reply[2] s e nlen
  local name
  for (( i = first; i <= last; i++ )); do
    name=$_zhimmer_zrow[i]
    if [[ -z $_zhimmer_zkind[i] ]]; then
      _zhimmer_zle_htext "$name"; nlen=$(( ${#name} + 2 ))
    else
      _zhimmer_row "$name"; nlen=0
    fi
    out+=$'\n'$REPLY
    (( pos++ ))                                  # the newline itself
    s=$pos; e=$(( pos + ${#REPLY} )); pos=$e
    if (( i == _zhimmer_zsel )); then
      # The bar wins over the accent: two colours read as half-selected.
      region_highlight+=( "$s $e bg=${ZHIMMER_SELECT_BG},memo=zhimmer" )
    elif (( nlen )); then
      region_highlight+=(
        "$s $(( s + nlen )) fg=${ZHIMMER_COLORS[$name]:-$ZHIMMER_HEADER_COLOR},bold,memo=zhimmer"
        "$(( s + nlen )) $e fg=${ZHIMMER_RULE_COLOR},memo=zhimmer"
      )
    elif (( accents )); then
      _zhimmer_zle_token $s $name $_zhimmer_zkind[i]
    fi
  done
  POSTDISPLAY=$out
  return 0
}

# Colour a row's command word -- or, after a precommand, the precommand and the
# word after it. Keyed by group, not label (see theme.zsh).
_zhimmer_zle_token() {  # <row start> <row text> <group>
  local -i s=$1; local text=$2
  local colour=${ZHIMMER_ROW_COLORS[${3#zhimmer-}]}
  [[ -n $colour ]] || return 0
  local first=${text%% *}
  (( $#first )) || return 0
  local -i a=$(( s + 2 ))                       # past the two-space indent
  if (( ${ZHIMMER_ROW_PRECOMMANDS[(I)$first]} )); then
    region_highlight+=( "$a $(( a + $#first )) ${ZHIMMER_ROW_PRECOMMAND_COLOR},memo=zhimmer" )
    local rest=${text#$first}
    local lead=${rest%%[^[:space:]]*}            # no `##`: EXTENDED_GLOB is never set
    local second=${${rest#$lead}%% *}
    (( $#second )) || return 0
    a=$(( a + $#first + $#lead ))
    first=$second
  fi
  region_highlight+=( "$a $(( a + $#first )) fg=${colour},memo=zhimmer" )
  return 0
}

# Draw the last gather, deciding the ghost: only at end of line, and only when
# the candidate extends what is typed.
_zhimmer_zle_show() {
  # A search always has a row selected, so Enter always has one to take.
  if (( _zhimmer_search && ! _zhimmer_zsel )); then
    local REPLY
    _zhimmer_zle_next 0 1 && _zhimmer_zsel=$REPLY
  fi
  # The ghost follows the selection, so bar, Right and Enter all agree.
  local top=$_zhimmer_top
  (( _zhimmer_zsel )) && top=$_zhimmer_zbuf[_zhimmer_zsel]
  _zhimmer_zghost=
  if [[ -z $RBUFFER && -n $top && $top == ${LBUFFER}?* ]] && _zhimmer_bool ghost-text; then
    _zhimmer_zghost=${top#$LBUFFER}
  fi
  _zhimmer_zle_draw
  return 0
}

_zhimmer_zle_clear() {
  _zhimmer_zle_reset
  _zhimmer_zghost=
  POSTDISPLAY=
  region_highlight=( ${region_highlight:#*memo=zhimmer*} )
  typeset -g _zhimmer_shown_for=
  return 0
}

# Wraps both ways: from nothing, Down lands on the first row and Up the last.
_zhimmer_zle_move() {  # <step>
  local REPLY
  _zhimmer_zle_next $_zhimmer_zsel $1 || return 1
  _zhimmer_zsel=$REPLY
  _zhimmer_zle_show
  return 0
}

_zhimmer_zle_accept() {
  (( _zhimmer_zsel )) || return 1
  local buf=$_zhimmer_zbuf[_zhimmer_zsel]
  # Taking a row ends a search. Not in _zhimmer_zle_clear, which runs on every
  # keystroke and would end it on the first one.
  _zhimmer_search=0
  _zhimmer_zle_clear
  BUFFER=$buf
  CURSOR=${#BUFFER}
  return 0
}
