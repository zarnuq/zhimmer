# Shell history, ranked by frecency. The matching is done by zhimmer-match
# because zsh's own array filtering degrades badly as history grows: at ~500k
# entries it costs ~221ms per keystroke against the binary's ~28ms.

_zhimmer_source_history() {
  local -i wstart=$1 limit=$2
  [[ -x $ZHIMMER_BIN && -r $HISTFILE ]] || return
  local -a lines
  lines=( ${(f)"$($ZHIMMER_BIN --history $HISTFILE --limit $limit -- "$LBUFFER" 2>/dev/null)"} )
  # Remembered for ghost text: the top row is what the accept keys would take.
  typeset -g _zhimmer_top=$lines[1]
  _zhimmer_addgroup zhimmer-history history $wstart "$lines[@]"
}
