# Shell history, ranked by frecency: every run of a line counts, and counts for
# less the further back it was.
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

  # Frecency is the sum of what each run of a line was worth, and a run is
  # worth less the further back it was: full weight for the last one, half at
  # `history-halflife` matches back, a twentieth at four times that.
  #
  # Summing is the whole of it. The old score multiplied an unbounded count by
  # a single recency term that only ever spanned 1x to 4x, so frequency always
  # won in the end: fifty runs of a VPN config retired last month outranked the
  # one run twice this morning, and no amount of typing could move it, because
  # nothing typed changes the ratio. A sum has no such ceiling -- a line has to
  # keep being run to keep its score, and one that stopped being run decays
  # past the one that replaced it.
  #
  # Distance is counted in *matches*, not in history entries -- see the ranking
  # section of README.md for why that is the right clock.
  #
  # The window is what it always was, twenty matches per row asked for, and
  # stopping there is what keeps the cost flat as the history grows. What a run
  # at the edge of it is still worth depends on the halflife, though, not on
  # the window alone: at the default pair it is a quarter of a percent of a
  # fresh one and cannot change the order, but a large `history-halflife`
  # against a small `max-suggestions` cuts the window off while runs still
  # carry weight.
  local REPLY
  _zhimmer_cfg history-halflife
  # A user's zstyle on its way into a division, so two guards. Strip it to
  # digits, because an arithmetic error at the prompt is fatal rather than
  # catchable; then fall back if nothing usable is left, because zero divides
  # by zero. The fallback reads the table -- a number spelled here too would be
  # a second place to change the default.
  local -i half=${REPLY//[^0-9]/}
  (( half )) || half=${ZHIMMER_DEFAULTS[history-halflife]}
  local -i h2=half*half
  # What the newest run is worth. Large enough that a run at the far edge of
  # the window is still some thousands rather than rounding away to nothing,
  # small enough that the shift below stays clear of the integer ceiling.
  local -i fresh=1000000
  local -A score first
  local c
  local -i i=0 dist sum
  for c in ${_zhimmer_hist_m[1,limit*20]}; do
    (( i++ ))
    [[ $c == $q ]] && continue        # what is already typed is not a suggestion
    # zsh keeps a command containing a newline as one entry, and a row with a
    # newline in it cannot be drawn. Skipped here rather than filtered out of
    # the match list, which would be another pass over every match.
    [[ $c == *$'\n'* ]] && continue
    # Read out into a scalar first, never as score[$c] inside the math: there
    # the key is parsed as an arithmetic expression, and a history line holding
    # a stray ( or [ is an invalid one.
    sum=${score[$c]:-0} dist=i-1
    score[$c]=$(( sum + fresh * h2 / (h2 + dist * dist) ))
    [[ -n ${first[$c]} ]] || first[$c]=$i # newest first, so the first seen is the last run
  done
  (( $#score )) || return

  # One integer per line so (On) can sort on it: the score, shifted up to leave
  # room for how recently the line last ran. Recency is inside the sum now, so
  # the shift is no longer what makes the ranking lean -- two lines can only
  # meet here by their summed weights landing on the same integer, and it
  # settles that deterministically rather than leaving it to whatever order the
  # hash happened to hold them in. The shift is the window size rather than a
  # round number, so the tie-break can never carry into the score however large
  # `max-suggestions` is set.
  local -a scored=()
  local -i total last
  for c in ${(k)score}; do
    total=${score[$c]} last=${first[$c]}
    scored+=( "$(( total * (i + 1) + i - last ))"$'\t'"$c" )
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
