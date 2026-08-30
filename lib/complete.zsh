# The shared candidate generator, and the group helpers every source ends in.

# Every scalar setting and its default, in one table: _zhimmer_cfg and
# _zhimmer_bool read it and zhimmer-doctor prints it, so a default is written
# down once instead of at each call site and again in the diagnostics. The
# `sources` style is not here -- it is an array, read with zstyle -a.
#
# It lives beside the two functions that read it rather than in the plugin
# file, which is what lets the libraries be sourced and exercised on their own:
# with the table out of reach _zhimmer_bool answered no to every setting, and a
# test of alias expansion tested nothing but the guard at the top of it.
typeset -gA ZHIMMER_DEFAULTS=(
  max-suggestions   10
  min-chars         2
  ghost-text        yes
  ghost-color       'fg=#6c7086'
  row-colors        yes
  expand-alias      yes
  tame-lists        yes
  style-completion  yes
  toggle-key        '^@'
  search-key        '^R'
  search-suggestions 100
  # Off unless asked for: this plugin is loaded for its menu, and taking over
  # the prompt of everyone who does that is not a trade they agreed to. See
  # lib/prompt.zsh.
  prompt            no
  prompt-async      yes
)

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

# Whether Ctrl+R has turned the drop-down into a history search: the query
# matches anywhere in a line rather than only at its start, and history is the
# only source asked. It lives here rather than in the history source because
# three other files read it -- the gather below, the draw (which keeps a row
# selected while a search is open) and the widget that turns it on.
typeset -gi _zhimmer_search=0

# Gather the candidates. This runs inside a `zle -C` widget for one reason: the
# completion system is what splits the line into $words and hands a source
# $PREFIX and $CURRENT, and every source decides whether it applies from those.
# Nothing is added with compadd -- the rows go to lib/zlemenu.zsh, which draws
# them -- so what the widget itself would list is always empty.
.zhimmer-complete() {
  _zhimmer_zle_reset
  local -a srcs
  # A search asks one question, so it gets one answer. Offering the files in
  # this directory alongside the remembered lines that contain what was typed
  # is two different searches sharing a screen.
  if (( _zhimmer_search )); then
    srcs=( history )
  else
    zstyle -a ':zhimmer:*' sources srcs || srcs=( history alias command )
  fi

  # A cap on the total rows, shared across every group -- without it the
  # per-source limit multiplies, and eleven sources at ten each is a hundred
  # and ten rows built on every keystroke.
  #
  # It is deliberately *not* tied to $LINES. The drawn window is bounded by the
  # screen already (_zhimmer_zle_draw lays out only the rows that fit) and it
  # scrolls, so a candidate past the bottom of the terminal is still reachable
  # by walking down to it. Clamping the list itself to the screen is what stops
  # a menu holding more than fits, which is the one thing a menu is for.
  #
  # A search gets its own, larger number and the whole budget to itself. It is
  # one source and it is meant to be scrolled through -- ten rows is a
  # suggestion, not a search result -- so `search-suggestions` is what decides
  # how deep it goes. Everything else bounds the work instead: five groups'
  # worth, which puts the sources named first (history, by convention) ahead of
  # the rest when the budget runs out.
  local REPLY
  local -i limit
  if (( _zhimmer_search )); then
    _zhimmer_cfg search-suggestions; limit=$REPLY
    typeset -g _zhimmer_budget=$(( limit + 1 ))    # the rows, plus their header
  else
    _zhimmer_cfg max-suggestions; limit=$REPLY
    typeset -g _zhimmer_budget=$(( limit * 5 ))
  fi

  local s
  for s in $srcs; do
    # Each group costs a header row, so anything under 2 cannot show a result.
    (( _zhimmer_budget >= 2 )) || break
    (( ${+functions[_zhimmer_source_$s]} )) && _zhimmer_source_$s $limit
  done

  # A search that found nothing still says so. With the rows gone there is
  # otherwise nothing on screen saying the mode is on -- and it changes what
  # Enter does, so it has to be visible even when it has nothing to offer.
  (( _zhimmer_search && ! $#_zhimmer_zrow )) && _zhimmer_zle_header 'search: no match'
  return 0
}

# Add one group of whole-line candidates -- rows that are a whole command line
# and become one when taken.
#
#   _zhimmer_addgroup <group> <label> <full-line>...
_zhimmer_addgroup() {
  local group=$1 name=$2; shift 2
  (( $# )) || return
  _zhimmer_take $#
  (( _zhimmer_taken )) || return
  set -- "${@[1,_zhimmer_taken]}"
  _zhimmer_offer_ghost $name "$1"
  # Shown and taken are the same string here, which is what makes this the
  # simple case: a remembered line replaces the whole buffer. Copied to a named
  # array first -- `argv` inside _zhimmer_emit is its own positional list, not
  # this one.
  local -a lines=( "$@" )
  _zhimmer_emit $group $name lines lines
}

# Add a group of word-level candidates -- ones that replace just the current
# word.
#
#   _zhimmer_addwords <group> <label> <word>... [-- <row>...]
#
# Rows show the word itself unless rows are given after --, which is what an
# alias needs: the match is `gs`, the row reads `gs  →  git status -s`. The two
# lists are trimmed together, so a row never describes a different match.
#
# Rows travel as arguments rather than as the name of an array to read back:
# `local -a disp` here would shadow a caller's array of the same name, and the
# group would silently lose its rows.
# The match list is `matches`, not `words`: `words` is the completion system's
# own array of the words on the command line, which sources/git-branch.zsh and
# sources/zoxide.zsh read as $words[1] and $words[2] to decide whether they
# apply at all. A local of that name here shadows it, so the same expression
# means the command line two files over and the match list inside this one.
_zhimmer_addwords() {
  local group=$1 name=$2; shift 2
  local -a matches=( "$@" ) rows=()
  local -i sep=$argv[(i)--]
  if (( sep <= $# )); then
    matches=( "${(@)argv[1,sep-1]}" )
    rows=( "${(@)argv[sep+1,-1]}" )
  fi
  (( $#matches )) || return
  _zhimmer_take $#matches
  (( _zhimmer_taken )) || return
  matches=( "${(@)matches[1,_zhimmer_taken]}" )
  if (( $#rows )); then
    rows=( "${(@)rows[1,_zhimmer_taken]}" )
  else
    rows=( "${(@)matches}" )
  fi

  # A word source replaces only the current word, so the line a row would leave
  # is everything before that word, the match, and whatever was after the
  # cursor. The ghost is compared against the whole of LBUFFER and needs the
  # same thing: a candidate that does not extend what is typed simply draws no
  # ghost, which is what happens to zoxide, matching anywhere in a path -- `z
  # hmr` offers a line that does not begin with `z hmr`.
  local head=${LBUFFER[1,${#LBUFFER}-${#PREFIX}]}
  _zhimmer_offer_ghost $name "$head${matches[1]}"

  local -a bufs=(); local m
  for m in "$matches[@]"; do bufs+=( "$head$m$RBUFFER" ); done
  _zhimmer_emit $group $name rows bufs
}

# Hand one finished group to the menu. Both helpers above end here, which is
# the point of it: the label a header is drawn under and the group a row's
# colour is keyed by are decided once instead of twice.
#
# The group and the label are two different strings and it matters which is
# used where. ZHIMMER_COLORS is keyed by label (`branch`), ZHIMMER_ROW_COLORS
# by group (`git-branch`), and for six of the eleven sources those are not the
# same word -- so a row looked up by its label came back with no colour at all,
# silently, because a missing hash key is an empty string rather than an error.
#
# The two lists travel by name: parallel arrays cannot be flattened into "$@".
# Every local is prefixed so it cannot shadow the array a caller named --
# `local -a rows` takes effect before its own right-hand side is evaluated, so
# a collision would read the list back empty.
#
#   _zhimmer_emit <group> <label> <display array> <buffer array>
_zhimmer_emit() {
  local -a _zedisp=( "${(@P)3}" ) _zebuf=( "${(@P)4}" )
  local -i _zei
  # Rows go in unpadded: the menu pads at draw time, so a resize is picked up
  # without regenerating anything.
  _zhimmer_zle_header $2
  for (( _zei = 1; _zei <= $#_zedisp; _zei++ )); do
    _zhimmer_zle_match "$_zedisp[_zei]" $1 "$_zebuf[_zei]"
  done
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
# a $( ) here would run in a subshell and silently discard the decrement.
_zhimmer_take() {
  local -i want=$1
  typeset -g _zhimmer_taken=0
  (( _zhimmer_budget >= 2 )) || return 0
  (( _zhimmer_budget-- ))                       # header
  _zhimmer_taken=$(( want < _zhimmer_budget ? want : _zhimmer_budget ))
  (( _zhimmer_budget -= _zhimmer_taken ))
  return 0
}
