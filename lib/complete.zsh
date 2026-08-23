# The shared candidate generator, plus the two entry points that differ only in
# whether the result is merely listed or handed to menu selection.

# Read an integer setting, falling back to a default.
_zhimmer_cfg() {
  local v
  zstyle -s ':zhimmer:*' $1 v || v=$2
  print -r -- $v
}

.zhimmer-complete() {
  local -a srcs
  zstyle -a ':zhimmer:*' sources srcs || srcs=( history alias command )
  local -i limit=$(_zhimmer_cfg max-suggestions 10)
  # Never ask for more rows than the screen can hold. complist does not paginate
  # a raw zle -C listing: an over-long list simply scrolls the prompt off the
  # top, taking the earlier candidates with it. Reserve room for the prompt and
  # the group header.
  local -i room=$(( LINES - 5 ))
  (( room < 1 )) && room=1
  (( limit > room )) && limit=$room

  # Rows left on screen, shared across every group. Without a shared budget the
  # per-source cap multiplies: six sources at ten each is sixty rows, which
  # scrolls the earliest groups -- and the prompt -- off the top.
  typeset -g _zhimmer_budget=$room

  # zsh replaces only the *current word*, so a candidate holding a whole command
  # line has to be trimmed to the part that starts at the current word. That
  # offset is everything typed so far minus the part of the word before the
  # cursor. (Assigning PREFIX=$LBUFFER does NOT widen the replaced region --
  # verified; the match gets appended instead of substituted.)
  local -i wstart=$(( ${#LBUFFER} - ${#PREFIX} ))

  local s
  for s in $srcs; do
    # Each group costs a header row, so anything under 2 cannot show a result.
    (( _zhimmer_budget >= 2 )) || break
    (( ${+functions[_zhimmer_source_$s]} )) && _zhimmer_source_$s $wstart $limit
  done
}

.zhimmer-complete-list() {
  .zhimmer-complete
}

.zhimmer-complete-menu() {
  compstate[insert]='menu'
  .zhimmer-complete
}

# Add one group of whole-line candidates. Callers pass the full command lines;
# this trims each to the replaceable tail while keeping the full line on display.
#
#   _zhimmer_addgroup <group> <header> <wstart> <full-line>...
_zhimmer_addgroup() {
  local group=$1 name=$2; local -i wstart=$3; shift 3
  (( $# )) || return
  _zhimmer_take $#
  (( _zhimmer_taken )) || return
  set -- "${@[1,_zhimmer_taken]}"
  local REPLY
  _zhimmer_header $name; local header=$REPLY
  local -a full=() tails=()
  local c
  for c in "$@"; do
    _zhimmer_row "$c"; full+=( "$REPLY" )
    tails+=( "${c:$wstart}" )
  done
  # -l forces one match per line: a multi-column list makes Down ambiguous,
  # since menuselect moves within a column before wrapping to the next.
  compadd -l -Q -U -V $group -X $header -d full -a tails
}

# Add a group of word-level candidates -- ones that replace just the current
# word, so they need none of the whole-line trimming above.
#
#   _zhimmer_addwords <group> <header> <word>...
_zhimmer_addwords() {
  local group=$1 name=$2; shift 2
  (( $# )) || return
  _zhimmer_take $#
  (( _zhimmer_taken )) || return
  set -- "${@[1,_zhimmer_taken]}"
  # -l only takes effect alongside -d, so the display array is required even
  # when it mirrors the matches. Without it the list goes multi-column and Down
  # navigates columns instead of rows.
  local REPLY
  _zhimmer_header $name; local header=$REPLY
  local -a disp=() m=( "$@" )
  local c
  for c in "$@"; do _zhimmer_row "$c"; disp+=( "$REPLY" ); done
  compadd -l -V $group -X $header -d disp -a m
}

# Claim rows from the shared budget: one for the group header plus as many as
# are left for its matches. Answers in _zhimmer_taken rather than on stdout --
# a $( ) here would run in a subshell and silently discard the decrement.
_zhimmer_take() {
  local -i want=$1
  typeset -g _zhimmer_taken=0
  (( _zhimmer_budget >= 2 )) || return
  (( _zhimmer_budget-- ))                       # header
  _zhimmer_taken=$(( want < _zhimmer_budget ? want : _zhimmer_budget ))
  (( _zhimmer_budget -= _zhimmer_taken ))
}
