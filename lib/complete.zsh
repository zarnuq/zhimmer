# The candidate gather, and the group helpers every source ends in.

# Every scalar setting and its default, read by _zhimmer_cfg/_zhimmer_bool and
# printed by zhimmer-doctor. Here, not in the plugin file, so the libraries can
# be sourced and tested alone. `sources` is an array, read with zstyle -a.
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
  history-halflife  10   # in matches: a run that far back is worth half a fresh one
  prompt            no
  prompt-async      yes
)
# The array setting's default, beside the scalars.
typeset -ga ZHIMMER_DEFAULT_SOURCES=( history alias command )

_zhimmer_sources() {  # -> reply
  zstyle -a ':zhimmer:*' sources reply || reply=( $ZHIMMER_DEFAULT_SOURCES )
}

# In REPLY, never on stdout: $( ) forks, and this runs on every keystroke.
_zhimmer_cfg() {
  zstyle -s ':zhimmer:*' $1 REPLY || REPLY=${ZHIMMER_DEFAULTS[$1]}
}

_zhimmer_bool() {
  local REPLY
  _zhimmer_cfg $1
  [[ $REPLY == (yes|true|1|on) ]]
}

# Ctrl+R's mode: substring matching, history only. Read by the gather, the
# draw (keeps a row selected) and the widgets.
typeset -gi _zhimmer_search=0

# Runs inside `zle -C` only for the context -- $words, $PREFIX, $CURRENT. Adds
# nothing with compadd; rows go to zlemenu.zsh.
#
# One row budget shared by every group, so per-source limits do not multiply.
# Not tied to $LINES: the drawn window scrolls. A search gets its own, larger
# limit and the whole budget.
.zhimmer-complete() {
  _zhimmer_zle_reset
  local REPLY
  local -a srcs reply
  local -i limit
  if (( _zhimmer_search )); then
    srcs=( history )
    _zhimmer_cfg search-suggestions; limit=$REPLY
    typeset -g _zhimmer_budget=$(( limit + 1 ))    # the rows, plus their header
  else
    _zhimmer_sources; srcs=( $reply )
    _zhimmer_cfg max-suggestions; limit=$REPLY
    typeset -g _zhimmer_budget=$(( limit * 5 ))
  fi

  local s
  for s in $srcs; do
    (( _zhimmer_budget >= 2 )) || break             # a header plus one row
    (( ${+functions[_zhimmer_source_$s]} )) && _zhimmer_source_$s $limit
  done

  # An empty search still says it is on: it changes what Enter does.
  (( _zhimmer_search && ! $#_zhimmer_zrow )) && _zhimmer_zle_add 'search: no match'
  return 0
}

# Whole-line candidates: shown and taken are the same string.
#   _zhimmer_addgroup <group> <label> <full-line>...
_zhimmer_addgroup() {
  local -a lines=( "${(@)argv[3,-1]}" )
  _zhimmer_emit $1 $2 lines lines
}

# Word candidates, replacing only the current word. Rows after `--` are shown
# instead of the words (an alias shows its expansion).
#   _zhimmer_addwords <group> <label> <word>... [-- <row>...]
# Not `words`: that is compsys's array, which the sources read.
_zhimmer_addwords() {
  local group=$1 name=$2; shift 2
  local -a matches=( "$@" ) rows=( "$@" )
  local -i sep=$argv[(i)--]
  if (( sep <= $# )); then
    matches=( "${(@)argv[1,sep-1]}" )
    rows=( "${(@)argv[sep+1,-1]}" )
  fi
  local head=${LBUFFER[1,${#LBUFFER}-${#PREFIX}]}
  local -a bufs=( "$head${^matches[@]}$RBUFFER" )
  _zhimmer_emit $group $name rows bufs
}

# One finished group into the menu: budget, ghost offer, header, rows. Arrays
# travel by name, and locals are prefixed so they cannot shadow the caller's.
# <group> keys row colours, <label> keys header colours -- see theme.zsh.
#   _zhimmer_emit <group> <label> <display array> <buffer array>
_zhimmer_emit() {
  local -a _zedisp=( "${(@P)3}" ) _zebuf=( "${(@P)4}" )
  (( $#_zebuf && _zhimmer_budget >= 2 )) || return
  (( _zhimmer_budget-- ))                       # header
  local -i _zen=$(( $#_zebuf < _zhimmer_budget ? $#_zebuf : _zhimmer_budget )) _zei
  (( _zhimmer_budget -= _zen ))

  _zhimmer_offer_ghost $2 "$_zebuf[1]"
  _zhimmer_zle_add $2
  for (( _zei = 1; _zei <= _zen; _zei++ )); do
    _zhimmer_zle_add "$_zedisp[_zei]" $1 "$_zebuf[_zei]"
  done
}

# Sort, then cut -- cutting first sorts an arbitrary handful. Filtering stays at
# each source, where a hash can filter itself with (I).
_zhimmer_pick() {  # <limit> <candidate>...  -> reply
  local -i limit=$1; shift
  typeset -ga reply=( ${(o)argv} )
  (( $#reply > limit )) && reply=( "${(@)reply[1,limit]}" )
  (( $#reply ))
}

# Tail of every cached-array source: prefix-match, pick, draw. By name, so a
# known_hosts of thousands is not copied into argv per keystroke.
_zhimmer_addpicked() {  # <group> <label> <limit> <array name>
  local -a reply
  _zhimmer_pick $3 ${(M)${(P)4}:#${~${(b)PREFIX}}*} || return
  _zhimmer_addwords $1 $2 "$reply[@]"
}

# mtime for file-backed caches. Without zsh/stat REPLY stays empty and each
# file is read once.
zmodload -F zsh/stat b:zstat 2>/dev/null
_zhimmer_mtime() {  # <file>  -> REPLY
  local -a st
  REPLY=
  zstat -A st +mtime $1 2>/dev/null && REPLY=$st[1]
}
