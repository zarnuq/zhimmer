# User-facing widgets. The completion widgets themselves live in complete.zsh.

# self-insert is the busiest widget in the shell, and other plugins wrap it too
# -- autopair, abbreviation expanders, anything that reacts to a character as it
# is typed. Replacing it outright and calling `zle .self-insert` underneath drops
# whatever was already there; copying the existing widget aside and calling the
# copy keeps the chain, which is what accept-line and the completion widgets
# already do.
#
# Called at load and again after zsh-vi-mode's init, so the wrap survives
# whatever loaded in between. The guard makes the second call a no-op unless
# something has taken the widget since, in which case it wraps that instead.
_zhimmer_wrap_self_insert() {
  [[ ${widgets[self-insert]} == user:.zhimmer-self-insert ]] && return
  zle -A self-insert .zhimmer-orig-self-insert
  zle -N self-insert .zhimmer-self-insert
}

.zhimmer-self-insert() {
  _zhimmer_clear_ghost
  zle .zhimmer-orig-self-insert
  _zhimmer_maybe_show
}

_zhimmer_maybe_show() {
  _zhimmer_drew=0
  (( _zhimmer_enabled )) || return
  # Skip while input is still arriving. During fast typing or a paste the result
  # would be discarded by the next keystroke anyway, so this is the cheapest
  # guard available and it matters more than any micro-optimisation inside the
  # generator.
  (( PENDING || KEYS_QUEUED_COUNT )) && return
  local REPLY; _zhimmer_cfg min-chars
  (( ${#LBUFFER} >= REPLY )) || return

  typeset -g _zhimmer_top=
  zle zhimmer-show
  _zhimmer_ghost
}

# Down opens the menu, but only when there is something to show -- otherwise it
# has to keep behaving like plain history navigation, which is muscle memory.
.zhimmer-down() {
  # menuselect inserts the highlighted match into the buffer itself, so a ghost
  # left over from typing would be redrawn after it -- showing the tail of the
  # suggestion twice.
  _zhimmer_clear_ghost
  # Down walks into whatever was last drawn (_zhimmer_drew, declared in
  # complete.zsh), not into a fresh question put to the matcher: the list on
  # screen is exactly what Down should open.
  if (( _zhimmer_enabled && _zhimmer_drew )); then
    zle zhimmer-menu
  else
    zle .down-line-or-history
  fi
}

# Shift+Tab steps back up through the matches Tab is stepping down through.
# It used to share the key with the on/off switch, which was a bad trade: the
# step-back is pressed constantly and the switch almost never, so the switch was
# reachable by accident -- and a silently disabled zhimmer looks exactly like a
# broken one. The switch has its own key now (toggle-key, Ctrl+Space by
# default), and this key only ever does the one thing.
#
# Whether there is anything to step through cannot be read from LASTWIDGET:
# with fzf's completion loaded Tab is `fzf-completion`, with zhimmer's wrapper
# running underneath it. So the state is recorded where the completion actually
# happens and matched against the line it left behind -- anything that types,
# deletes or moves the cursor leaves a different line, and there is nothing to
# step back into. One string holds all of it -- cursor and line -- and is empty
# when the last completion had nothing to step through.
typeset -g _zhimmer_menu_at=

_zhimmer_note_menu() {
  if (( ${_lastcomp[nmatches]:-0} > 1 )); then
    _zhimmer_menu_at="$CURSOR $BUFFER"
  else
    _zhimmer_menu_at=
  fi
}

.zhimmer-step-back() {
  [[ -n $_zhimmer_menu_at && $_zhimmer_menu_at == "$CURSOR $BUFFER" ]] || return 0
  zle reverse-menu-complete
  _zhimmer_note_menu
}

.zhimmer-toggle() {
  _zhimmer_enabled=$(( ! _zhimmer_enabled ))
  # Say so. Off, zhimmer draws nothing at all, which looks exactly like it being
  # broken; the message names the state and how to undo it. Turning it back on
  # needs no message -- the list coming straight back says it, without anything
  # drawn over the top of it.
  if (( _zhimmer_enabled )); then
    _zhimmer_maybe_show
  else
    zle -R -c
    local REPLY; _zhimmer_cfg toggle-key
    [[ $REPLY == '^@' ]] && REPLY='Ctrl+Space'   # the default, said readably
    zle -M "zhimmer off -- $REPLY turns it back on"
  fi
}

# Anything that shortens or rewrites the line has to refresh the menu and the
# ghost, or both keep describing a prefix that is no longer there. Wrapping by
# widget name rather than by key matters: which widget backspace reaches depends
# on the keymap -- with EDITOR=nvim zsh selects viins, where it is
# vi-backward-delete-char, not backward-delete-char.
typeset -ga ZHIMMER_REFRESH_WIDGETS=(
  backward-delete-char    vi-backward-delete-char
  backward-kill-word      vi-backward-kill-word
  delete-char             vi-delete-char
  kill-word               kill-line
  backward-kill-line      kill-whole-line
)

_zhimmer_wrap_refresh() {
  local w
  for w in $ZHIMMER_REFRESH_WIDGETS; do
    # Only wrap builtins: `zle .$w` would bypass another plugin's wrapper.
    [[ ${widgets[$w]} == builtin ]] || continue
    functions[.zhimmer-refresh-$w]="
      _zhimmer_clear_ghost
      zle .$w
      _zhimmer_maybe_show
    "
    zle -N $w .zhimmer-refresh-$w
  done
}

# The keys that take the ghost into the buffer, matching zsh-autosuggestions,
# which zhimmer replaces: Right and Ctrl+F at end of line, plus Ctrl+E and End.
# "Go to end of line" and "take the suggestion" mean the same thing when the
# suggestion is what stands between the cursor and the end.
#
# Tab is deliberately not among them. It belongs to zsh's completion system,
# which knows nothing about the ghost, and completing a word is not the same
# gesture as accepting a whole remembered line.
#
# Anywhere but end of line these keys must still move the cursor, so the
# original widget is called through. Wrapped by name for the same reason as the
# refresh widgets: with EDITOR=nvim, Right is vi-forward-char, not forward-char.
typeset -ga ZHIMMER_ACCEPT_WIDGETS=(
  forward-char  vi-forward-char
  end-of-line   vi-end-of-line   vi-add-eol
)

_zhimmer_wrap_accept() {
  local w
  for w in $ZHIMMER_ACCEPT_WIDGETS; do
    [[ ${widgets[$w]} == builtin ]] || continue
    functions[.zhimmer-accept-$w]="
      _zhimmer_accept_ghost || zle .$w
    "
    zle -N $w .zhimmer-accept-$w
  done
}

# Tab belongs to zsh's completion system, not to zhimmer, so nothing refreshed
# the drop-down after it rewrote the line: completing `./Doc` to `./Documents/`
# left the file list still showing the matches for `./Doc` -- two lines on
# screen describing different buffers.
#
# Tab hands the listing area over to completion, but only takes it away from
# zhimmer -- never from zsh. The rows are dropped only when they are zhimmer's
# own, since those describe the word as it was; a list zsh put there is left
# alone, because zsh keeps one list across a run of Tabs and clearing it on
# every press left the area blank from the second Tab onwards, which is the
# whole point of tabbing through a directory.
#
# What comes back is decided from _lastcomp, zsh giving no direct answer to
# "did you list?". Exactly one match means there was nothing to list and the
# word is now finished, which is when zhimmer's own list is worth redrawing.
# With several the area is zsh's, whether it listed them or inserted the first.
typeset -ga ZHIMMER_COMPLETE_WIDGETS=(
  expand-or-complete  complete-word  expand-or-complete-prefix
  menu-complete       menu-expand-or-complete
)

# Wrapped by copying the widget aside rather than by calling `zle .$w`: after
# compinit these are completion widgets (`completion:.expand-or-complete:
# _main_complete`), and the dot-prefixed builtin behind them is zsh's own dumb
# completion, with none of compsys behind it.
#
# The per-widget stub is one line calling the real function below. Spelling the
# whole policy into `functions[...]` instead put five copies of it in the shell,
# each a string nothing could syntax-check, differing only in a name.
_zhimmer_wrap_complete() {
  local w
  for w in $ZHIMMER_COMPLETE_WIDGETS; do
    (( ${+widgets[$w]} )) || continue
    [[ ${widgets[$w]} == user:.zhimmer-after-$w ]] && continue
    zle -A $w .zhimmer-orig-$w
    functions[.zhimmer-after-$w]="_zhimmer_after_complete .zhimmer-orig-$w"
    zle -N $w .zhimmer-after-$w
  done
}

# Run one completion with zhimmer's rows out of the way and its display strings
# in place, then decide what the listing area is left showing.
_zhimmer_after_complete() {  # <saved-widget>
  if (( _zhimmer_drew )); then
    zle -R -c
    _zhimmer_drew=0
  fi
  _zhimmer_style_matches
  { zle $1 } always { _zhimmer_unstyle_matches }
  (( ${_lastcomp[nmatches]:-0} == 1 )) && _zhimmer_maybe_show
  _zhimmer_note_menu
  return 0
}

# Ctrl+E and End reach the ghost through the end-of-line widget wrapped above,
# which only works where those keys are bound to it. They are under emacs, and
# under zsh-vi-mode's insert keymap, but a bare viins leaves them self-insert or
# unbound -- and a literal ^E in the buffer helps nobody. Point them at
# end-of-line where they are not already doing something else.
#
# The keymap is read once and asked about all four keys, rather than queried per
# key: bindkey is a builtin, but reading its answer back needs a $( ), and that
# is the fork -- one per keymap here instead of one per key per keymap.
# A key bound through a range (`bindkey -R "!"-"~" self-insert`) does not appear
# by name here and so reads as unbound -- which lands on the same answer, since
# the ranges cover printable characters and these four are not among them.
_zhimmer_bind_eol() {
  local m=$1 k l
  local -a w
  local -A bound
  for l in ${(f)"$(bindkey -M $m -L 2>/dev/null)"}; do
    w=( ${(z)l} )
    bound[${(Q)w[-2]}]=$w[-1]     # bindkey [-R] -M <keymap> "<key>" <widget>
  done
  for k in '^E' '^[[F' '^[[4~' '^[OF' ${(V)terminfo[kend]}; do
    [[ ${bound[$k]} == (self-insert|) ]] && bindkey -M $m $k end-of-line
  done
  return 0
}

# Inside the menu: Enter takes the highlighted row, Esc backs out, and Tab and
# the arrows walk the list. Tab moves rather than accepts, because the row the
# cursor is on is not chosen until Enter -- stepping through a list and picking
# from it are two gestures, and only one of them should end the menu.
#
# Typing narrows the list instead of ending it (type-to-filter, switched on in
# complete.zsh and tabstyle.zsh). complist calls that interactive mode, and it
# drops out of it the moment a key moves the selection -- which would quietly
# turn the next character typed back into "accept this row, then insert it",
# the behaviour the mode exists to avoid. So every movement key is a two-key
# macro: move, then vi-insert, which is complist's own toggle back into
# interactive mode. The primitives it is built from are bound under a prefix
# nobody presses, since pressing one of them on its own would leave the mode.
_zhimmer_bind_menuselect() {
  bindkey -M menuselect '^[' send-break
  # Backspace has to be named here, though the main keymap already has it:
  # complist reads it as "take a character back off what I am filtering on"
  # only while the key is bound to the builtin, and zhimmer rebinds it to
  # refresh the ghost. That made backspace leave the menu instead, accepting
  # whichever row it was on as it went.
  bindkey -M menuselect '^?' backward-delete-char
  bindkey -M menuselect '^H' backward-delete-char

  if ! _zhimmer_bool type-to-filter; then
    bindkey -M menuselect '^I' accept-line   # Tab accepts; nothing filters
    return 0
  fi

  bindkey -M menuselect '^X^N' down-line-or-history
  bindkey -M menuselect '^X^P' up-line-or-history
  bindkey -M menuselect '^X^F' vi-insert
  local k
  for k in '^[[B' '^[OB' '^I'   '^N'; do bindkey -M menuselect -s $k '^X^N^X^F'; done
  for k in '^[[A' '^[OA' '^[[Z' '^P'; do bindkey -M menuselect -s $k '^X^P^X^F'; done
  return 0
}
