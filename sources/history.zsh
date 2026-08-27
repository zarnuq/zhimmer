# Shell history, ranked by frecency: how often a command was run, weighted by
# how recently it last was.
#
# All of it is zsh's own. ${history[(R)pattern]} searches the parameter in
# place, newest first, without first expanding tens of thousands of entries
# into an array to filter afterwards -- that expansion alone is 4x the cost of
# the search, and it is what made an earlier pure-zsh attempt here too slow to
# keep. Reading $history rather than HISTFILE also matches this session's own
# commands the moment they run, with no INC_APPEND_HISTORY needed.

# Last keystroke's matches, and what they were found for. Typing extends the
# query, and the matches for a longer query are a subset of the ones already in
# hand -- so the search runs once per word rather than once per keystroke.
# HISTCMD guards it: a command run since means an entry that was never searched.
typeset -g _zhimmer_hist_q= _zhimmer_hist_at=
typeset -ga _zhimmer_hist_m=()

# Rank the history for <query>, best first, into reply. Split from the source
# below so zhimmer-doctor can ask the same question from outside a completion
# widget, where compadd does not exist.
_zhimmer_hist_rank() {  # <query> <limit>
  local q=$1
  local -i limit=$2
  typeset -ga reply=()
  (( $#q )) || return

  # Kept in the cache rather than copied out of it: at ten thousand entries a
  # `git ` search matches thousands of them, and one array copy per keystroke
  # is more than the search that produced it.
  if [[ -n $_zhimmer_hist_q && $_zhimmer_hist_at == $HISTCMD && $q == ${_zhimmer_hist_q}* ]]; then
    _zhimmer_hist_m=( ${(M)_zhimmer_hist_m:#${(b)q}*} )
  else
    # (b) quotes the query as a literal: a `[` or `*` typed at the prompt is a
    # character to match, not a pattern to run.
    _zhimmer_hist_m=( ${history[(R)${(b)q}*]} )
  fi
  _zhimmer_hist_q=$q _zhimmer_hist_at=$HISTCMD
  (( $#_zhimmer_hist_m )) || return

  # Only the newest occurrences are counted. Recency weights the newest at 4x
  # the oldest, so what happened further back than a few hundred runs of this
  # prefix cannot change the order -- and stopping there is what keeps the cost
  # flat as the history grows. Twenty occurrences per row asked for is generous
  # against a history that is mostly repeats.
  local -A cnt pos
  local c
  local -i i=0
  for c in ${_zhimmer_hist_m[1,limit*20]}; do
    (( i++ ))
    [[ $c == $q ]] && continue        # what is already typed is not a suggestion
    # zsh keeps a command containing a newline as one entry, and a row with a
    # newline in it cannot be drawn. Skipped here rather than filtered out of
    # the match list, which would be another pass over every match.
    [[ $c == *$'\n'* ]] && continue
    cnt[$c]=$(( ${cnt[$c]:-0} + 1 ))
    [[ -n ${pos[$c]} ]] || pos[$c]=$i # newest first, so the first seen is the last run
  done
  (( $#cnt )) || return

  # count x recency as one integer, so (On) can sort on it: 1x for the oldest
  # occurrence in the window, 4x for the newest, interpolated. The low three
  # digits hold recency on its own, which breaks ties between equal scores the
  # way the ranking already leans -- without them, equal scores would come out
  # in whatever order the hash happened to hold them.
  local -a scored=()
  local -i n=$i v r
  for c in ${(k)cnt}; do
    v=${cnt[$c]} r=$(( n - pos[$c] ))
    scored+=( "$(( (v * (1000 + 3000 * r / n)) * 1000 + r ))"$'\t'"$c" )
  done
  reply=( ${${(On)scored}[1,limit]#*$'\t'} )
}

_zhimmer_source_history() {
  local -i wstart=$1 limit=$2
  local -a reply
  _zhimmer_hist_rank "$LBUFFER" $limit
  (( $#reply )) || return
  # Remembered for ghost text: the top row is what the accept keys would take.
  typeset -g _zhimmer_top=$reply[1]
  _zhimmer_addgroup zhimmer-history history $wstart "$reply[@]"
}
