# The shared candidate generator, plus the two entry points that differ only in
# whether the result is merely listed or handed to menu selection.

# Read a setting. The answer comes back in REPLY rather than on stdout, for the
# same reason the row and header helpers do it: these run on every keystroke and
# $( ) forks, which costs more than the matcher it is about to call. Defaults
# live in ZHIMMER_DEFAULTS, so each one is written down in exactly one place.
_zhimmer_cfg() {
  zstyle -s ':zhimmer:*' $1 REPLY || REPLY=${ZHIMMER_DEFAULTS[$1]}
}

# The same for the yes/no settings. Every caller used to spell the accepted
# words out for itself, so the vocabulary could drift between them.
_zhimmer_bool() {
  local REPLY
  _zhimmer_cfg $1
  [[ $REPLY == (yes|true|1|on) ]]
}

# Whether anything was drawn, set by _zhimmer_take as a group claims its rows
# and cleared before each redraw. Down walks into whatever is on screen, so this
# is what answers "is there a menu to open?" -- asking a source again instead
# left every list Down could not have opened unreachable.
typeset -g _zhimmer_drew=0

.zhimmer-complete() {
  local mode=$1
  local -a srcs
  zstyle -a ':zhimmer:*' sources srcs || srcs=( history alias command )
  local -i limit
  local REPLY

  if [[ $mode == menu ]]; then
    # The menu scrolls (see MENUPROMPT in theme.zsh), so it is not bound by the
    # screen: it can hold more than fits and the user walks down into the rest.
    # That is the whole difference between the two entry points -- a listing has
    # to fit, a menu only has to be reachable -- and a budget of -1 says so,
    # leaving the per-source limit as the only cap.
    _zhimmer_cfg menu-suggestions; limit=$REPLY
    typeset -g _zhimmer_budget=-1
  else
    # Never ask for more rows than the screen can hold. complist does not
    # paginate a raw zle -C listing: an over-long list simply scrolls the prompt
    # off the top, taking the earlier candidates with it. Reserve room for the
    # prompt and the group header.
    #
    # The budget is shared across every group. Without that the per-source cap
    # multiplies: six sources at ten each is sixty rows, which in a listing
    # scrolls the earliest groups -- and the prompt -- off the top.
    local -i room=$(( LINES - 5 ))
    (( room < 1 )) && room=1
    _zhimmer_cfg max-suggestions; limit=$REPLY
    (( limit > room )) && limit=$room
    typeset -g _zhimmer_budget=$room
  fi

  # zsh replaces only the *current word*, so a candidate holding a whole command
  # line has to be trimmed to the part that starts at the current word. That
  # offset is everything typed so far minus the part of the word before the
  # cursor. (Assigning PREFIX=$LBUFFER does NOT widen the replaced region --
  # verified; the match gets appended instead of substituted.)
  local -i wstart=$(( ${#LBUFFER} - ${#PREFIX} ))

  local s
  for s in $srcs; do
    # Each group costs a header row, so anything under 2 cannot show a result.
    (( _zhimmer_budget < 0 || _zhimmer_budget >= 2 )) || break
    (( ${+functions[_zhimmer_source_$s]} )) && _zhimmer_source_$s $wstart $limit
  done
}

# Which of the two entry points is running decides how many rows may be asked
# for, so the generator is told rather than left to guess.
.zhimmer-complete-list() { .zhimmer-complete list }

.zhimmer-complete-menu() {
  compstate[insert]='menu'
  # Typing inside the menu narrows it rather than accepting the highlighted row
  # (type-to-filter; the keys that keep it that way are in widgets.zsh). Tab's
  # menu is told the same thing through the `menu` style, which a raw zle -C
  # widget never goes through, so here it is set on the parameter compsys would
  # have set. Unset rather than left alone when off: that same style path is
  # what wrote the global last.
  if _zhimmer_bool type-to-filter; then
    MENUMODE=interactive
  else
    unset MENUMODE
  fi
  .zhimmer-complete menu
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
#   _zhimmer_addwords <group> <header> <word>... [-- <row>...]
#
# Rows show the word itself unless rows are given after --, which is what an
# alias needs: the match is `gs`, the row reads `gs  →  git status -s`. The two
# lists are trimmed together, so a row never describes a different match.
#
# Rows travel as arguments rather than as the name of an array to read back:
# `local -a disp` here would shadow a caller's array of the same name, and the
# group would silently lose its rows.
_zhimmer_addwords() {
  local group=$1 name=$2; shift 2
  local -a words=( "$@" ) rows=()
  local -i sep=$argv[(i)--]
  if (( sep <= $# )); then
    words=( "${(@)argv[1,sep-1]}" )
    rows=( "${(@)argv[sep+1,-1]}" )
  fi
  (( $#words )) || return
  _zhimmer_take $#words
  (( _zhimmer_taken )) || return
  words=( "${(@)words[1,_zhimmer_taken]}" )
  if (( $#rows )); then
    rows=( "${(@)rows[1,_zhimmer_taken]}" )
  else
    rows=( "${(@)words}" )
  fi

  local REPLY
  _zhimmer_header $name; local header=$REPLY
  # -l only takes effect alongside -d, so the display array is required even
  # when it mirrors the matches. Without it the list goes multi-column and Down
  # navigates columns instead of rows.
  local -a disp=(); local c
  for c in "$rows[@]"; do _zhimmer_row "$c"; disp+=( "$REPLY" ); done
  # -U because a source has already decided what matches. Without it compadd
  # keeps only the candidates that literally begin with the word on the line and
  # drops the rest without saying so, which silently threw away every match a
  # source found by any rule other than a plain prefix: zoxide matches anywhere
  # in a path -- `z hmr` for ~/src/zhimmer -- and none of those survived, and a
  # glob in a filename (`ls ./z*`) left the list empty because `./zalpha` does
  # not start with `./z*`.
  compadd -l -U -V $group -X $header -d disp -a words
}

# Sort a source's matches and cut them to its limit, in reply. The two steps
# every source shares, in the order that makes them mean something: sort the
# whole match set, then take from the front. Cutting first and sorting after --
# which the command source did -- sorts an arbitrary handful of the matches and
# throws the rest away, so `gi` offered ten of the gi* commands picked by hash
# order rather than the first ten of them.
#
# Filtering stays at each source. A hash filters inside itself with (I), which
# is cheaper than materialising every key to match afterwards, and $commands
# holds a few thousand of them.
#
# Not every source wants this: zoxide's list arrives ranked by frecency, and
# sorting it alphabetically would throw away the only thing that made it worth
# asking. Those cut without sorting.
_zhimmer_pick() {  # <limit> <candidate>...  -> reply
  local -i limit=$1; shift
  typeset -ga reply=( ${(o)argv} )
  (( $#reply > limit )) && reply=( "${(@)reply[1,limit]}" )
  (( $#reply ))
}

# Claim rows from the shared budget: one for the group header plus as many as
# are left for its matches. Answers in _zhimmer_taken rather than on stdout --
# a $( ) here would run in a subshell and silently discard the decrement -- and
# is the one place that knows a group is about to be drawn.
_zhimmer_take() {
  local -i want=$1
  typeset -g _zhimmer_taken=0
  if (( _zhimmer_budget < 0 )); then
    _zhimmer_taken=$want                        # a menu is not bounded by rows
  else
    (( _zhimmer_budget >= 2 )) || return 0
    (( _zhimmer_budget-- ))                     # header
    _zhimmer_taken=$(( want < _zhimmer_budget ? want : _zhimmer_budget ))
    (( _zhimmer_budget -= _zhimmer_taken ))
  fi
  (( _zhimmer_taken )) && _zhimmer_drew=1
  return 0
}
