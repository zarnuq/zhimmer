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

# Up on an empty line opens the history above the prompt, newest next to it:
# the rows go in front of PROMPT, coloured with %F/%K instead of
# region_highlight (which cannot reach the prompt). _zhimmer_zprefix is exactly
# what was put in front, so it comes back out even after something else has
# rebuilt the rest of PROMPT.
typeset -gi _zhimmer_above=0
typeset -g _zhimmer_zprefix= _zhimmer_zmenu=

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

# Ghost on the first line, rows under it -- or, opened above, rows in the
# prompt in reverse so the first is nearest the line. Rebuilt from scratch each
# time, so a resize is picked up on the next keystroke. The memo lets the guard
# drop only zhimmer's highlights, not zsh-syntax-highlighting's.
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

  local -i h=$(( LINES - 4 ))
  if (( _zhimmer_above )); then
    _zhimmer_zle_baseprompt
    local nl=${REPLY//[^$'\n']/}
    h=$(( h - ${#nl} - 1 ))
    pos=-1                                       # rows are a string of their own
  fi
  local -a reply hl order
  _zhimmer_zle_window $#_zhimmer_zrow $_zhimmer_zsel $h $_zhimmer_ztop
  _zhimmer_ztop=$reply[1]
  order=( {$reply[1]..$reply[2]} )
  (( _zhimmer_above )) && order=( ${(Oa)order} )
  local -i i s e nlen
  local name rows=
  for i in $order; do
    name=$_zhimmer_zrow[i]
    if [[ -z $_zhimmer_zkind[i] ]]; then
      _zhimmer_zle_htext "$name"; nlen=$(( ${#name} + 2 ))
    else
      _zhimmer_row "$name"; nlen=0
    fi
    rows+=$'\n'$REPLY
    (( pos++ ))                                  # the newline itself
    s=$pos; e=$(( pos + ${#REPLY} )); pos=$e
    if (( i == _zhimmer_zsel )); then
      # The bar wins over the accent: two colours read as half-selected.
      hl+=( "$s $e bg=${ZHIMMER_SELECT_BG},memo=zhimmer" )
    elif (( nlen )); then
      hl+=(
        "$s $(( s + nlen )) fg=${ZHIMMER_COLORS[$name]:-$ZHIMMER_HEADER_COLOR},bold,memo=zhimmer"
        "$(( s + nlen )) $e fg=${ZHIMMER_RULE_COLOR},memo=zhimmer"
      )
    elif (( accents )); then
      _zhimmer_zle_token $s $name $_zhimmer_zkind[i]
    fi
  done
  # Leaving above always goes through _zhimmer_zle_clear, which takes the rows
  # back out of PROMPT -- so only the above case touches it here.
  if (( _zhimmer_above )); then
    _zhimmer_zle_promptify "${rows#$'\n'}" $hl
    _zhimmer_zle_setprompt "$REPLY"$'\n'
  else
    out+=$rows
    region_highlight+=( $hl )
  fi
  POSTDISPLAY=$out
  return 0
}

# PROMPT without the rows zhimmer put in front of it.
_zhimmer_zle_baseprompt() {  # -> REPLY
  REPLY=$PROMPT
  [[ -n $_zhimmer_zprefix && $REPLY == "$_zhimmer_zprefix"* ]] &&   # quoted: literal
    REPLY=${REPLY:${#_zhimmer_zprefix}}
  return 0
}

# Put rows in front of PROMPT, or with none take them back out. Under
# PROMPT_SUBST they go in through a parameter: its value is not expanded again,
# so a history line holding $( ) is text, not a command run on every redraw.
_zhimmer_zle_setprompt() {  # [<prompt text>]
  [[ -z $1 && -z $_zhimmer_zprefix ]] && return 0
  local REPLY; _zhimmer_zle_baseprompt
  _zhimmer_zmenu=$1 _zhimmer_zprefix=$1
  [[ -n $1 && -o promptsubst ]] && _zhimmer_zprefix='${_zhimmer_zmenu}'
  PROMPT=$_zhimmer_zprefix$REPLY
  zle && zle reset-prompt
  return 0
}

# Text plus region_highlight-style "start end spec" ranges, as prompt escapes.
# % (and ! under PROMPT_BANG) in the text is escaped.
_zhimmer_zle_promptify() {  # <text> <range>... -> REPLY
  local text=$1 h spec a o c out=
  local -a part
  local -i at=0 s e
  for h in ${(on)@:2} ''; do
    if [[ -n $h ]]; then
      s=${h%% *} h=${h#* } e=${h%% *} spec=${h#* }
    else
      s=${#text} e=${#text} spec=
    fi
    o= c=
    for a in ${(s:,:)spec}; do
      case $a in
        fg=*)      o+="%F{${a#fg=}}" c+='%f' ;;
        bg=*)      o+="%K{${a#bg=}}" c+='%k' ;;
        bold)      o+='%B' c+='%b' ;;
        underline) o+='%U' c+='%u' ;;
      esac
    done
    part=( "${text[at+1,s]}" "${text[s+1,e]}" )
    part=( "${(@)part//\%/%%}" )
    [[ -o promptbang ]] && part=( "${(@)part//!/!!}" )
    out+=$part[1]$o$part[2]$c
    at=$e
  done
  REPLY=$out
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
    hl+=( "$a $(( a + $#first )) ${ZHIMMER_ROW_PRECOMMAND_COLOR},memo=zhimmer" )
    local rest=${text#$first}
    local lead=${rest%%[^[:space:]]*}            # no `##`: EXTENDED_GLOB is never set
    local second=${${rest#$lead}%% *}
    (( $#second )) || return 0
    a=$(( a + $#first + $#lead ))
    first=$second
  fi
  hl+=( "$a $(( a + $#first )) fg=${colour},memo=zhimmer" )
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
  _zhimmer_zle_setprompt
  typeset -g _zhimmer_shown_for=
  return 0
}

# Wraps both ways: from nothing, Down lands on the first row and Up the last.
# Opened above, the rows run bottom to top, so the step turns round with them.
_zhimmer_zle_move() {  # <step>
  local REPLY
  local -i step=$1
  (( _zhimmer_above )) && step=-step
  _zhimmer_zle_next $_zhimmer_zsel $step || return 1
  _zhimmer_zsel=$REPLY
  _zhimmer_zle_show
  return 0
}

_zhimmer_zle_accept() {
  (( _zhimmer_zsel )) || return 1
  local buf=$_zhimmer_zbuf[_zhimmer_zsel]
  # Taking a row ends a search. Not in _zhimmer_zle_clear, which runs on every
  # keystroke and would end it on the first one.
  _zhimmer_search=0 _zhimmer_above=0
  _zhimmer_zle_clear
  BUFFER=$buf
  CURSOR=${#BUFFER}
  return 0
}
