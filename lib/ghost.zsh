# Ghost text: which candidate wins, taking it into the buffer, and the guard
# that drops a stale display. Drawing is zlemenu.zsh's (same POSTDISPLAY).
# Replaces zsh-autosuggestions rather than coexisting: both would write POSTDISPLAY.

# Every group offers its first row; lowest rank wins, ties go to the first
# offered (the `sources` order). History wins: it is the only whole-line source.
typeset -gA ZHIMMER_GHOST_RANK=( history 0 )

_zhimmer_offer_ghost() {  # <source-name> <whole-line candidate>
  local -i rank=${ZHIMMER_GHOST_RANK[$1]:-1}
  [[ -n $_zhimmer_top ]] && (( rank >= _zhimmer_top_rank )) && return
  typeset -g _zhimmer_top=$2
  typeset -gi _zhimmer_top_rank=$rank
}

# line-pre-redraw: drop everything once BUFFER stops matching what it was drawn
# for. This catches every path that rewrites the line (Tab, unwrapped widgets);
# it can only drop, since a completion widget cannot run from a redraw hook.
_zhimmer_ghost_guard() {
  [[ ( -n $POSTDISPLAY || -n $_zhimmer_zprefix ) && $BUFFER != $_zhimmer_shown_for ]] &&
    _zhimmer_zle_clear
  return 0
}

# Take the ghost (never POSTDISPLAY, which holds the rows too). Non-zero when
# there is none, so the caller falls through to the key's normal widget.
#
# Given a widget, takes one word: the line is made whole and the user's own
# word widget moves the cursor, so WORDCHARS and vi/emacs decide where a word
# ends, then the line is cut there.
_zhimmer_accept_ghost() {  # [<widget to move by>]
  [[ -n $_zhimmer_zghost && -z $RBUFFER ]] || return 1
  local whole=$BUFFER$_zhimmer_zghost
  local -i orig=${#BUFFER}

  _zhimmer_zle_clear
  BUFFER=$whole          # before the cursor: BUFFER= can move CURSOR
  if (( $# )); then
    CURSOR=$orig
    zle $1
    (( CURSOR > orig )) || CURSOR=$orig   # the widget declined to move
    BUFFER=${whole[1,CURSOR]}
  fi
  CURSOR=${#BUFFER}
  _zhimmer_maybe_show    # regenerate, so the list describes the longer line
  return 0
}

# On line-finish (a ghost must not outlive an accepted line) and line-init
# (Ctrl+C skips line-finish, and a search must not leak into the next line).
_zhimmer_line_reset() {
  _zhimmer_search=0 _zhimmer_above=0
  _zhimmer_zle_clear
  return 0
}

# Ctrl+C aborts the line without line-finish, and zsh moves past whatever is
# drawn -- so the menu stayed on screen above the next prompt. Clear and redraw
# before the abort. Chains a TRAPINT that was already there; with none, the
# return status is the default behaviour.
_zhimmer_trapint() {
  zle && zle _zhimmer_line_reset && zle -R
  (( $+functions[_zhimmer_orig_trapint] )) && { _zhimmer_orig_trapint "$@"; return }
  return $(( 128 + $1 ))
}
