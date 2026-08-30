# Ghost text: a greyed preview of the top candidate, drawn past the cursor.
# This is the same technique zsh-autosuggestions uses, which is why zhimmer
# replaces rather than coexists with it -- two plugins writing POSTDISPLAY
# would fight.
#
# The drawing itself is lib/zlemenu.zsh's, since the ghost is the first line of
# the same POSTDISPLAY the rows are drawn into. What is here is the parts that
# are not drawing: which candidate wins, taking one into the buffer, and the
# guard that drops a display that has gone stale.

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

# Catch-all: drop the whole display as soon as the buffer stops matching what
# it was computed against. Naming the widgets that rewrite a line does not
# scale -- backspace and Tab were both missed that way, and ^U is vi-kill-line
# under viins, which zsh selects on EDITOR=nvim -- and Tab runs zsh's own
# completion, which rewrites the buffer with no idea zhimmer exists. A redraw
# hook catches every such path, including ones not yet thought of, for the cost
# of one string compare.
#
# Only dropped, never redrawn: a completion widget cannot be called from a
# redraw hook. Whatever is wrapped in widgets.zsh refreshes properly; whatever
# is not takes its rows down, which is right either way, because a list that no
# longer describes the line is worse than no list.
_zhimmer_ghost_guard() {
  [[ -n $POSTDISPLAY && $BUFFER != $_zhimmer_shown_for ]] && _zhimmer_zle_clear
  return 0
}

# Take the ghost into the buffer. Shared by the accept keys -- Right, Ctrl+F,
# Ctrl+E, End -- which all mean "accept what is on screen", after which the
# display must promise nothing the buffer does not hold. Returns non-zero when
# there is no ghost to accept, so callers can fall through to what the key
# normally does.
#
# It reads _zhimmer_zghost and not POSTDISPLAY, which also holds every row of
# the menu: appending that put the header rule and all its rows into BUFFER,
# and the result looked on screen exactly like the menu still being open.
_zhimmer_accept_ghost() {
  [[ -n $_zhimmer_zghost && -z $RBUFFER ]] || return 1
  local g=$_zhimmer_zghost
  _zhimmer_zle_clear
  BUFFER=$BUFFER$g
  CURSOR=${#BUFFER}
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
  [[ -n $_zhimmer_zghost && -z $RBUFFER ]] || return 1
  local whole=$BUFFER$_zhimmer_zghost
  local -i orig=${#BUFFER}

  _zhimmer_zle_clear
  BUFFER=$whole          # assigned before the cursor: BUFFER= can move CURSOR
  CURSOR=$orig
  zle $1

  # The widget declined to move into the suggestion -- already at the last word,
  # or a motion that stops short. Nothing is taken and the line is left as it
  # was; the redraw below puts the same ghost back.
  (( CURSOR > orig )) || CURSOR=$orig

  BUFFER=${whole[1,CURSOR]}
  CURSOR=${#BUFFER}
  # Regenerated rather than sliced out of `whole`. It costs one keystroke's
  # work on a key pressed rarely, and it is the only way the list under the
  # ghost describes the longer line rather than the one before it.
  _zhimmer_maybe_show
  return 0
}

# Every line starts and ends with nothing of zhimmer's on screen and no mode
# left over. Two hooks, one function.
#
# line-finish is about the ghost: it is display-only -- it lives in POSTDISPLAY,
# not in BUFFER -- so a line accepted while one is showing runs less than it
# appears to run, the screen keeping the whole suggestion and the shell getting
# the typed prefix. Clearing there covers every way out of the editor, not just
# the accept-line that gets wrapped.
#
# line-init is about the search mode, and it is not the same thing: Ctrl+C does
# not run line-finish, so a search abandoned that way stayed on and the *next*
# line was still matching substrings and offering nothing else. Whatever ended
# the last line, a new one begins out of the mode.
_zhimmer_line_reset() {
  _zhimmer_search=0
  _zhimmer_zle_clear
  return 0
}
