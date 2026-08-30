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
#
# The shape of the question is part of the key too. Lines *containing* `git com`
# are a subset of lines containing `git`, and lines *starting with* one are a
# subset of lines starting with the other -- but neither set is a subset of the
# other, so narrowing across a change of mode would answer from the wrong list.
typeset -g _zhimmer_hist_q= _zhimmer_hist_at= _zhimmer_hist_sub=0
typeset -ga _zhimmer_hist_m=()

# Rank the history for <query>, best first, into reply. Split from the source
# below so zhimmer-doctor can ask the same question from outside a completion
# widget, where compadd does not exist.
#
# <substring> is what Ctrl+R turns on: the query matches anywhere in a line
# rather than only at its start. Everything after the match is the same ranking
# either way -- searching is not a different feature, only a different anchor.
_zhimmer_hist_rank() {  # <query> <limit> [<substring>] -> reply
  local q=$1
  local -i limit=$2 sub=${3:-0}
  typeset -ga reply=()
  # A line of nothing but whitespace is as empty as an empty one: it is not a
  # prefix anybody is searching for, and ranking against it offered whatever
  # happened to be at the top of the history. A search is the exception -- an
  # empty one asks for everything, best first, which is what Ctrl+R opens on.
  (( sub )) || [[ -n ${q//[[:space:]]/} ]] || return

  # (b) quotes the query as a literal: a `[` or `*` typed at the prompt is a
  # character to match, not a pattern to run. The pattern is built in a
  # parameter and used with $~, since the anchor is now decided at runtime --
  # without the ~ the value is matched as a literal string, wildcards and all.
  local pat="${(b)q}*"
  (( sub )) && pat="*$pat"

  # Kept in the cache rather than copied out of it: at ten thousand entries a
  # `git ` search matches thousands of them, and one array copy per keystroke
  # is more than the search that produced it.
  if [[ -n $_zhimmer_hist_q && $_zhimmer_hist_at == $HISTCMD \
        && $_zhimmer_hist_sub == $sub && $q == ${_zhimmer_hist_q}* ]]; then
    _zhimmer_hist_m=( ${(M)_zhimmer_hist_m:#$~pat} )
  else
    _zhimmer_hist_m=( ${history[(R)$~pat]} )
  fi
  _zhimmer_hist_q=$q _zhimmer_hist_at=$HISTCMD _zhimmer_hist_sub=$sub
  (( $#_zhimmer_hist_m )) || return

  # A search answers in history order, newest first, and stops there. That is
  # what the key has always meant -- in fzf and in zsh's own bck-i-search alike
  # -- because you are looking for a thing you ran and *when* is how you
  # remember it. Frecency is for the drop-down, where there is no question yet
  # and the best guess is the one you run most; applied to a search it hides
  # this morning's command behind one from last year that you type every day.
  #
  # Duplicates collapse to their newest occurrence. A history is mostly
  # repeats, the window is twenty rows, and four screens of `ls` is not a
  # search result.
  if (( sub )); then
    local -A seen
    local c
    # The same window the ranking below uses. Without it a query matching
    # nothing much scans the whole history to come back with three rows.
    for c in ${_zhimmer_hist_m[1,limit*20]}; do
      # A row with a newline in it cannot be drawn.
      [[ $c == *$'\n'* ]] && continue
      [[ -n $seen[$c] ]] && continue
      seen[$c]=1
      reply+=( "$c" )
      (( $#reply >= limit )) && break
    done
    return
  fi

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
    # Both read outside the math, not as pos[$c] inside it: there the key is
    # parsed as an arithmetic subscript, and a history line holding a stray ( or
    # [ is an invalid one.
    v=${cnt[$c]} r=$(( n - ${pos[$c]} ))
    scored+=( "$(( (v * (1000 + 3000 * r / n)) * 1000 + r ))"$'\t'"$c" )
  done
  reply=( ${${(On)scored}[1,limit]#*$'\t'} )
}

_zhimmer_source_history() {
  local -i limit=$1
  local -a reply
  _zhimmer_hist_rank "$LBUFFER" $limit $_zhimmer_search
  (( $#reply )) || return
  # The top row goes to the ghost through _zhimmer_addgroup, which offers the
  # first row of every group it draws -- see ZHIMMER_GHOST_RANK in ghost.zsh.
  # In a search it offers nothing in practice: a candidate that merely contains
  # what is typed does not extend it, and the ghost drops any that does not.
  #
  # Two literal calls rather than one with the label in a variable: the header
  # says which of the two questions is being asked, and test/unit.zsh reads the
  # group and label straight out of this file to check both have a colour.
  if (( _zhimmer_search )); then
    _zhimmer_addgroup zhimmer-history search "$reply[@]"
  else
    _zhimmer_addgroup zhimmer-history history "$reply[@]"
  fi
}
