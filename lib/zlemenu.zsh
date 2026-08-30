# The drop-down, drawn by zhimmer itself into POSTDISPLAY.
#
# zsh ships a menu -- zsh/complist, driven by compadd and the menuselect keymap
# -- and zhimmer used it for a while. It went because of one thing it cannot
# do: filter an open menu without flickering. Its interactive mode is what
# filters, it resets that mode on every movement key (`mode = 0` in each mover
# in Src/Zle/complist.c), and it draws a hardcoded `interactive: []` row while
# the mode is on -- so keeping the mode alive across an arrow costs a
# `move, then vi-insert` macro that removes and reinserts a screen row on every
# keypress, shifting the list under the cursor.
#
# Drawing it here removes the question rather than answering it. There is no
# menu mode to be in: typing narrows the list because typing already recomputes
# it, the arrows only move an index, and nothing toggles. It is also less to
# write: 491 bytes a keystroke against complist's 2927.
#
# complist still draws Tab's listing, because that list is zsh's rather than
# zhimmer's -- see lib/tabstyle.zsh, which restyles it without generating it.
#
# The other half of why this works at all is that `region_highlight` colours by
# character offset, so an escape is never counted as width. That is the
# constraint that keeps colour out of a compadd display string, and it does not
# apply here. Rows are plain text; colour is applied over them.

# The rows on screen, and what each one means. Parallel arrays rather than one
# array of packed records: a row's text can hold anything, including whatever
# separator the packing would have used.
typeset -ga _zhimmer_zrow=()    # text, unpadded
typeset -ga _zhimmer_zkind=()   # the compadd-style group name, '' for a header
typeset -ga _zhimmer_zbuf=()    # the whole BUFFER this row would leave behind
typeset -gi _zhimmer_zsel=0     # index into the arrays, 0 for nothing selected
typeset -gi _zhimmer_ztop=1     # first row shown, for scrolling

# The greyed tail past the cursor, kept apart from POSTDISPLAY rather than read
# back out of it. POSTDISPLAY holds the ghost *and* every row under it, so the
# accept keys -- Right, Ctrl+E, End -- took the whole of it into the buffer:
# Ctrl+E on an open menu left the header rule and all its rows sitting in
# BUFFER, looking on screen exactly like the menu still being open, one Enter
# away from running. What the keys accept is this, which is only ever the tail.
typeset -g _zhimmer_zghost=

_zhimmer_zle_reset() {
  _zhimmer_zrow=() _zhimmer_zkind=() _zhimmer_zbuf=()
  _zhimmer_zsel=0 _zhimmer_ztop=1
}

# Which rows fit on screen, given where the selection is. Pure, so it is tested
# against a table in test/unit.zsh rather than by counting rows on a terminal.
#
# Answers in reply as (first last). The window only moves when the selection
# would leave it, which is what stops the list scrolling under a cursor that has
# not reached its edge yet.
_zhimmer_zle_window() {  # <total> <selected> <height> <current-first> -> reply
  local -i n=$1 sel=$2 h=$3 first=$4
  (( h < 1 )) && h=1
  (( first < 1 )) && first=1
  typeset -ga reply
  (( n <= h )) && { reply=( 1 $n ); return }
  (( sel && sel < first ))         && first=$sel
  (( sel && sel > first + h - 1 )) && first=$(( sel - h + 1 ))
  (( first > n - h + 1 ))          && first=$(( n - h + 1 ))
  (( first < 1 ))                  && first=1
  reply=( $first $(( first + h - 1 )) )
}

# Add one row. Called by the group helpers in complete.zsh, which is the only
# thing that knows a group is being drawn at all.
_zhimmer_zle_header() {  # <label>
  _zhimmer_zrow+=( "$1" ); _zhimmer_zkind+=( '' ); _zhimmer_zbuf+=( '' )
}
_zhimmer_zle_match() {   # <row text> <group> <resulting buffer>
  _zhimmer_zrow+=( "$1" ); _zhimmer_zkind+=( "$2" ); _zhimmer_zbuf+=( "$3" )
}

# The next selectable row in a direction, wrapping at the ends. Headers are rows
# on screen but never selectable, so movement steps over them -- otherwise Down
# would land on ' history' and Enter would take it.
#
# Wrapping is also what lets Up open the menu: from nothing, stepping back once
# lands on the last row. It gives up after a full lap rather than looping, which
# is what stops a list of nothing but headers spinning forever.
_zhimmer_zle_next() {  # <from> <step> -> REPLY, 0 when there is nothing to take
  local -i i=$1 step=$2 n=$#_zhimmer_zrow lap
  (( n )) || { REPLY=0; return 1 }
  for (( lap = 0; lap < n; lap++ )); do
    (( i += step ))
    (( i > n )) && i=1
    (( i < 1 )) && i=n
    [[ -n $_zhimmer_zkind[i] ]] && { REPLY=$i; return 0 }
  done
  REPLY=0; return 1
}

# A group header as plain text. Deliberately not _zhimmer_header, which emits
# prompt escapes for `compadd -X`: POSTDISPLAY is not prompt-expanded, so those
# would be literal characters -- counted in the layout and painted over by the
# offsets, which is the same width trap that keeps colour out of a display
# string. Text here, colour through region_highlight.
_zhimmer_zle_htext() {  # <label> -> REPLY
  local name=$1
  local -i w=$(( COLUMNS - ${(m)#name} - 4 ))
  (( w < 0 )) && w=0
  REPLY=" ${name} ${(l:w::─:):-}"
}

# Draw. POSTDISPLAY carries the ghost on the first line and the rows under it;
# region_highlight colours them by offset. Both are rebuilt from scratch on
# every draw, which is what makes a resize correct for free: widths are read
# here, so the next keystroke lays out to the new terminal.
_zhimmer_zle_draw() {
  region_highlight=( ${region_highlight:#*memo=zhimmer*} )
  local -i base=${#BUFFER}
  local out=$_zhimmer_zghost
  local -i pos=$(( base + ${#_zhimmer_zghost} ))
  [[ -n $_zhimmer_zghost ]] && _zhimmer_zle_paint $base $pos ghost

  (( $#_zhimmer_zrow )) || { POSTDISPLAY=$out; return 0 }

  # Read once for the whole draw rather than once a row: this is a zstyle
  # lookup and there can be twenty rows on screen.
  local -i accents=0
  _zhimmer_bool row-colors && accents=1

  local -a reply
  local -i h=$(( LINES - 4 ))
  _zhimmer_zle_window $#_zhimmer_zrow $_zhimmer_zsel $h $_zhimmer_ztop
  _zhimmer_ztop=$reply[1]
  local -i i first=$reply[1] last=$reply[2] s e nlen
  local REPLY name
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
      # The bar wins over the row accent: two colours on one row read as a
      # half-selected row.
      _zhimmer_zle_paint $s $e select
    elif (( nlen )); then
      _zhimmer_zle_paint $s $(( s + nlen )) header "$name"
      _zhimmer_zle_paint $(( s + nlen )) $e rule
    elif (( accents )); then
      _zhimmer_zle_token $s $name $_zhimmer_zkind[i]
    fi
  done
  POSTDISPLAY=$out
  return 0
}

# Colour the command word of a row, and the command after a precommand:
# `sudo openvpn ...` has the word you are looking for in second place, so
# lighting up only `sudo` misses it.
#
# Keyed off the group -- the name a source passes first, `zhimmer-git-branch`
# -- and not off the header label it passes second. ZHIMMER_ROW_COLORS is
# written in those terms; the label is a different word for six of the eleven
# sources, and looking a row up by it silently returned nothing.
_zhimmer_zle_token() {  # <row start> <row text> <group>
  local -i s=$1; local text=$2
  local REPLY colour=${ZHIMMER_ROW_COLORS[${3#zhimmer-}]}
  [[ -n $colour ]] || return 0
  local first=${text%% *}
  (( $#first )) || return 0
  local -i a=$(( s + 2 ))                       # past the two-space indent
  if (( ${ZHIMMER_ROW_PRECOMMANDS[(I)$first]} )); then
    _zhimmer_hl $ZHIMMER_ROW_PRECOMMAND_COLOR &&
      region_highlight+=( "$a $(( a + $#first )) ${REPLY},memo=zhimmer" )
    local rest=${text#$first}
    # The run of spaces between the two words, by taking everything up to the
    # first non-space. No `[[:space:]]##` -- that needs EXTENDED_GLOB, which
    # this plugin never sets.
    local lead=${rest%%[^[:space:]]*}
    local second=${${rest#$lead}%% *}
    (( $#second )) || return 0
    a=$(( a + $#first + $#lead ))
    first=$second
  fi
  region_highlight+=( "$a $(( a + $#first )) fg=${colour},memo=zhimmer" )
  return 0
}

# One region_highlight entry. The memo is what lets the redraw guard tell
# zhimmer's own highlighting from zsh-syntax-highlighting's and drop only ours.
_zhimmer_zle_paint() {  # <start> <end> <what> [<label>]
  local spec
  case $3 in
    ghost)  local REPLY; _zhimmer_cfg ghost-color; spec=$REPLY ;;
    select) spec="bg=${ZHIMMER_SELECT_BG}" ;;
    header) spec="fg=${ZHIMMER_COLORS[$4]:-#6c7086},bold" ;;
    rule)   spec="fg=${ZHIMMER_RULE_COLOR}" ;;
  esac
  region_highlight+=( "$1 $2 ${spec},memo=zhimmer" )
}

# Draw whatever the last gather produced, working out the ghost as it goes.
# Only at end of line -- a ghost in the middle of a line reads as real text --
# and only when the candidate actually extends what is typed.
_zhimmer_zle_show() {
  # A search always has a row selected, so Enter always has one to take and the
  # bar says which. Regenerating drops the selection every keystroke, so it is
  # put back here rather than by whatever moved the line.
  if (( _zhimmer_search && ! _zhimmer_zsel )); then
    local REPLY
    _zhimmer_zle_next 0 1 && _zhimmer_zsel=$REPLY
  fi
  local top=$_zhimmer_top
  # Once a row is selected the ghost follows it rather than the top candidate.
  # Otherwise the two disagree: the bar marks one row while the greyed tail
  # promises another, and Right and Enter would put different lines on screen.
  (( _zhimmer_zsel )) && top=$_zhimmer_zbuf[_zhimmer_zsel]
  _zhimmer_zghost=
  if [[ -z $RBUFFER && -n $top && $top == ${LBUFFER}?* ]] && _zhimmer_bool ghost-text; then
    _zhimmer_zghost=${top#$LBUFFER}
  fi
  _zhimmer_zle_draw
  return 0
}

# Take the menu off the screen. POSTDISPLAY is the whole of it, so there is
# nothing to clear on the terminal -- the next redraw simply draws less.
_zhimmer_zle_clear() {
  _zhimmer_zle_reset
  _zhimmer_zghost=
  POSTDISPLAY=
  region_highlight=( ${region_highlight:#*memo=zhimmer*} )
  typeset -g _zhimmer_shown_for=
  return 0
}

# Move the selection, wrapping at both ends. With nothing selected, Down lands
# on the first row and Up on the last -- which is how Up opens the menu at all,
# rather than falling through to history navigation.
_zhimmer_zle_move() {  # <step>
  (( $#_zhimmer_zrow )) || return 1
  local REPLY
  _zhimmer_zle_next $_zhimmer_zsel $1 || return 1
  _zhimmer_zsel=$REPLY
  _zhimmer_zle_show
  return 0
}

# Take the highlighted row. The buffer each row would leave was worked out when
# it was added, so there is no re-deriving of what replaces what here.
_zhimmer_zle_accept() {
  (( _zhimmer_zsel )) || return 1
  local buf=$_zhimmer_zbuf[_zhimmer_zsel]
  # Taking a row ends a search: the line now holds a whole command rather than
  # the fragment that was being searched for, and typing after it should mean
  # what it means everywhere else. Cleared here and not in _zhimmer_zle_clear,
  # which runs on every keystroke and would end the search on the first one.
  _zhimmer_search=0
  _zhimmer_zle_clear
  BUFFER=$buf
  CURSOR=${#BUFFER}
  return 0
}
