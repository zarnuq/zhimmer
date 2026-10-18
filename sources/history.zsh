# Shell history, ranked by frecency. ${history[(R)pat]} searches the parameter
# in place; expanding $history into an array first costs 4x the search.

# Last keystroke's matches and what they were for. A longer query narrows the
# matches already in hand instead of searching again. Keyed on the anchor too:
# prefix and substring match sets are not subsets of each other.
typeset -g _zhimmer_hist_q= _zhimmer_hist_at= _zhimmer_hist_sub=0
typeset -ga _zhimmer_hist_m=()

# Rank history for <query> into reply, best first. <substring> (Ctrl+R) matches
# anywhere in a line instead of at its start. Split from the source so
# zhimmer-doctor can call it outside a completion widget.
_zhimmer_hist_rank() {  # <query> <limit> [<substring>] -> reply
  local q=$1
  local -i limit=$2 sub=${3:-0}
  typeset -ga reply=()
  # A blank query is not a prefix; an empty search means "everything".
  (( sub )) || [[ -n ${q//[[:space:]]/} ]] || return

  local pat="${(b)q}*"            # (b): typed text is literal, not a pattern
  (( sub )) && pat="*$pat"

  if [[ -n $_zhimmer_hist_q && $_zhimmer_hist_at == $HISTCMD \
        && $_zhimmer_hist_sub == $sub && $q == ${_zhimmer_hist_q}* ]]; then
    _zhimmer_hist_m=( ${(M)_zhimmer_hist_m:#$~pat} )
  else
    _zhimmer_hist_m=( ${history[(R)$~pat]} )
  fi
  _zhimmer_hist_q=$q _zhimmer_hist_at=$HISTCMD _zhimmer_hist_sub=$sub
  (( $#_zhimmer_hist_m )) || return

  # A search answers newest first, deduplicated: you remember *when* you ran
  # it. Frecency is for the drop-down, where there is no question yet.
  if (( sub )); then
    local -A seen
    local c
    for c in ${_zhimmer_hist_m[1,limit*20]}; do
      [[ $c == *$'\n'* ]] && continue   # a row cannot hold a newline
      [[ -n $seen[$c] ]] && continue
      seen[$c]=1
      reply+=( "$c" )
      (( $#reply >= limit )) && break
    done
    return
  fi

  # Frecency: the sum over every run of fresh*h²/(h²+d²), where d is the run's
  # distance back *in matches* (see README) and h is history-halflife. A sum
  # has no ceiling, so a line must keep being run to keep its score. The window
  # is twenty matches per row asked for, which keeps the cost flat.
  local REPLY
  _zhimmer_cfg history-halflife
  # Digits only (an arithmetic error is fatal), and never zero.
  local -i half=${REPLY//[^0-9]/}
  (( half )) || half=${ZHIMMER_DEFAULTS[history-halflife]}
  local -i h2=half*half
  local -i fresh=1000000
  local -A score first
  local c
  local -i i=0 dist sum
  for c in ${_zhimmer_hist_m[1,limit*20]}; do
    (( i++ ))
    [[ $c == $q ]] && continue        # what is already typed is not a suggestion
    [[ $c == *$'\n'* ]] && continue
    # Into a scalar first: score[$c] inside $(( )) parses the key as arithmetic.
    sum=${score[$c]:-0} dist=i-1
    score[$c]=$(( sum + fresh * h2 / (h2 + dist * dist) ))
    [[ -n ${first[$c]} ]] || first[$c]=$i # newest first, so the first seen is the last run
  done
  (( $#score )) || return

  # Sort key: score, shifted by the window size to break ties on recency
  # without ever carrying into the score.
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
  # Two literal calls: test/unit.zsh reads group and label out of this file.
  if (( _zhimmer_search )); then
    _zhimmer_addgroup zhimmer-history search "$reply[@]"
  else
    _zhimmer_addgroup zhimmer-history history "$reply[@]"
  fi
}
