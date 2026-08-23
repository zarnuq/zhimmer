# User-facing widgets. The completion widgets themselves live in complete.zsh.

.zhimmer-self-insert() {
  _zhimmer_clear_ghost
  zle .self-insert
  _zhimmer_maybe_show
}

_zhimmer_maybe_show() {
  (( _zhimmer_enabled )) || return
  # Skip while input is still arriving. During fast typing or a paste the result
  # would be discarded by the next keystroke anyway, so this is the cheapest
  # guard available and it matters more than any micro-optimisation inside the
  # generator.
  (( PENDING || KEYS_QUEUED_COUNT )) && return
  local -i minc=$(_zhimmer_cfg min-chars 2)
  (( ${#LBUFFER} >= minc )) || return

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
  if (( _zhimmer_enabled )) && _zhimmer_have_candidates; then
    zle zhimmer-menu
  else
    zle .down-line-or-history
  fi
}

_zhimmer_have_candidates() {
  [[ -x $ZHIMMER_BIN && -r $HISTFILE && -n $LBUFFER ]] || return 1
  [[ -n "$($ZHIMMER_BIN --history $HISTFILE --limit 1 -- "$LBUFFER" 2>/dev/null)" ]]
}

.zhimmer-toggle() {
  _zhimmer_enabled=$(( ! _zhimmer_enabled ))
  (( _zhimmer_enabled )) || zle -R -c
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

# Right accepts the ghost when the cursor is at the end of the line, matching
# zsh-autosuggestions, which zhimmer replaces. Anywhere else it must still move
# the cursor, so the original widget is called through. Wrapped by name for the
# same reason as the refresh widgets: with EDITOR=nvim, Right is
# vi-forward-char, not forward-char.
typeset -ga ZHIMMER_ACCEPT_WIDGETS=( forward-char vi-forward-char )

_zhimmer_wrap_accept() {
  local w
  for w in $ZHIMMER_ACCEPT_WIDGETS; do
    [[ ${widgets[$w]} == builtin ]] || continue
    functions[.zhimmer-accept-$w]="
      if [[ -n \$POSTDISPLAY && -z \$RBUFFER ]]; then
        BUFFER=\$BUFFER\$POSTDISPLAY
        CURSOR=\${#BUFFER}
        _zhimmer_clear_ghost
        _zhimmer_maybe_show
      else
        zle .$w
      fi
    "
    zle -N $w .zhimmer-accept-$w
  done
}
