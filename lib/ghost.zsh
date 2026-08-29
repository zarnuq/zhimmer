# Ghost text: a greyed preview of the top candidate, drawn past the cursor with
# POSTDISPLAY. This is the same technique zsh-autosuggestions uses, which is why
# zhimmer replaces rather than coexists with it -- two plugins writing
# POSTDISPLAY would fight.
#
# It is only shown while the menu is merely listed. Once Down enters menuselect,
# zsh inserts the highlighted match into the buffer itself, and a ghost would be
# showing the same text twice.

# Which source's top row becomes the ghost when more than one group is drawn.
# Every group offers its first row as it is added; the lowest rank wins, and
# ties keep whichever offered first -- which is the order the `sources` style
# lists them in.
#
# History outranks everything because it is the only source offering a whole
# remembered line. Completing `gi` to `git` from $commands is worth less than
# the `git push --force-with-lease` the line is actually heading for, and
# without a rank the winner would just be whichever source the user happened to
# name first.
typeset -gA ZHIMMER_GHOST_RANK=( history 0 )

# Offer a candidate for the ghost. Kept apart from the group helpers, which
# cannot run outside a completion widget, so the precedence rule itself is
# testable on its own.
_zhimmer_offer_ghost() {  # <source-name> <whole-line candidate>
  local -i rank=${ZHIMMER_GHOST_RANK[$1]:-1}
  [[ -n $_zhimmer_top ]] && (( rank >= _zhimmer_top_rank )) && return
  typeset -g _zhimmer_top=$2
  typeset -gi _zhimmer_top_rank=$rank
}

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
  # The drop-down has the same problem and needs the same answer. Naming the
  # widgets that shorten a line does not scale -- backspace was missed once,
  # and ^U is vi-kill-line under viins, which zsh selects on EDITOR=nvim -- so
  # a list for a word that is no longer typed sat under an empty prompt.
  #
  # Only dropped, never redrawn: a completion widget cannot be called from a
  # redraw hook. Whatever is wrapped refreshes properly; whatever is not takes
  # its rows down, which is right either way, because rows that no longer
  # describe the line are worse than no rows.
  if (( _zhimmer_drew )) && [[ $BUFFER != $_zhimmer_rows_for ]]; then
    _zhimmer_drew=0
    _zhimmer_drop_rows 1
  fi
  return 0
}

_zhimmer_ghost() {
  _zhimmer_clear_ghost

  _zhimmer_bool ghost-text || return

  # Only at end of line: a ghost in the middle of a line reads as real text.
  [[ -z $RBUFFER ]] || return
  [[ -n $_zhimmer_top && $_zhimmer_top == ${LBUFFER}?* ]] || return

  POSTDISPLAY=${_zhimmer_top#$LBUFFER}
  _zhimmer_paint_ghost
}

# Colour whatever is already in POSTDISPLAY, and remember the buffer it belongs
# to so the redraw guard knows when it has gone stale. Split out because the
# word-at-a-time accept below puts the remainder of a suggestion back without
# going through the matcher to work out what it is.
_zhimmer_paint_ghost() {
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

# Take one word of the ghost instead of all of it -- the habit a switcher from
# zsh-autosuggestions would otherwise lose, and the difference between running
# `git push --force` and `git push --force-with-lease origin feature`.
#
# Where a word ends is not decided here. The line is temporarily made whole,
# suggestion and all, and the user's own word widget is run on it, so WORDCHARS,
# vi versus emacs, and any plugin that has taken forward-word all still decide
# where the cursor lands. Splitting the string here with a pattern of our own
# would answer differently from the same key pressed one character later, on
# text that is really in the buffer.
#
# Returns non-zero when there is no ghost to take, so the caller falls through
# to what the key normally does.
_zhimmer_accept_ghost_word() {  # <widget to move by>
  [[ -n $POSTDISPLAY && -z $RBUFFER ]] || return 1
  local whole=$BUFFER$POSTDISPLAY
  local -i orig=${#BUFFER}

  _zhimmer_clear_ghost
  BUFFER=$whole          # assigned before the cursor: BUFFER= can move CURSOR
  CURSOR=$orig
  zle $1

  # The widget declined to move into the suggestion -- already at the last word,
  # or a motion that stops short. Nothing is taken and the ghost stands.
  (( CURSOR > orig )) || CURSOR=$orig

  BUFFER=${whole[1,CURSOR]}
  POSTDISPLAY=${whole[CURSOR+1,-1]}
  CURSOR=${#BUFFER}
  if [[ -n $POSTDISPLAY ]]; then
    _zhimmer_paint_ghost
  else
    # The last word: this was a whole accept after all, so the list has to
    # catch up with the line the same way the other accept keys make it.
    _zhimmer_maybe_show
  fi
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
