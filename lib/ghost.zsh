# Ghost text: a greyed preview of the top candidate, drawn past the cursor with
# POSTDISPLAY. This is the same technique zsh-autosuggestions uses, which is why
# zhimmer replaces rather than coexists with it -- two plugins writing
# POSTDISPLAY would fight.
#
# It is only shown while the menu is merely listed. Once Down enters menuselect,
# zsh inserts the highlighted match into the buffer itself, and a ghost would be
# showing the same text twice.

_zhimmer_clear_ghost() {
  POSTDISPLAY=
  region_highlight=( ${region_highlight:#*memo=zhimmer*} )
  _zhimmer_ghost_for=
}

# Catch-all: drop the ghost as soon as the buffer stops matching what the ghost
# was computed against. Wrapping individual widgets does not scale -- backspace
# and Tab were both missed that way -- and Tab runs zsh's own completion, which
# rewrites the buffer with no idea zhimmer exists. A redraw hook catches every
# such path, including ones not yet thought of, for the cost of one string
# compare.
_zhimmer_ghost_guard() {
  [[ -n $POSTDISPLAY && $BUFFER != $_zhimmer_ghost_for ]] && _zhimmer_clear_ghost
  return 0
}

_zhimmer_ghost() {
  _zhimmer_clear_ghost

  _zhimmer_bool ghost-text || return

  # Only at end of line: a ghost in the middle of a line reads as real text.
  [[ -z $RBUFFER ]] || return
  [[ -n $_zhimmer_top && $_zhimmer_top == ${LBUFFER}?* ]] || return

  POSTDISPLAY=${_zhimmer_top#$LBUFFER}
  typeset -g _zhimmer_ghost_for=$BUFFER
  local REPLY; _zhimmer_cfg ghost-color
  region_highlight+=( "${#BUFFER} $(( ${#BUFFER} + ${#POSTDISPLAY} )) ${REPLY},memo=zhimmer" )
}

# Take the ghost into the buffer. Shared by the accept keys -- Right, Ctrl+F,
# Ctrl+E, End -- which all mean "accept what is on screen", after which the
# display must promise nothing the buffer does not hold. Returns non-zero when
# there is no ghost to accept, so callers can fall through to what the key
# normally does.
_zhimmer_accept_ghost() {
  [[ -n $POSTDISPLAY && -z $RBUFFER ]] || return 1
  BUFFER=$BUFFER$POSTDISPLAY
  CURSOR=${#BUFFER}
  _zhimmer_clear_ghost
  _zhimmer_maybe_show
  return 0
}

# The ghost is display-only -- it lives in POSTDISPLAY, not in BUFFER -- so a
# line accepted while one is showing runs less than it appears to run: the
# screen keeps the whole suggestion, the shell gets the typed prefix. Clearing
# at line-finish covers every way out of the editor, not just the accept-line
# that gets wrapped.
_zhimmer_ghost_finish() {
  _zhimmer_clear_ghost
  return 0
}
