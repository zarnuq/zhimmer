# User-facing widgets. The completion widget itself is in complete.zsh.
#
# Widgets are wrapped by name, never bound by key: which widget a key reaches
# depends on the keymap (viins under EDITOR=nvim). Each wrapped widget gets a
# one-line stub calling a shared handler with the widget to fall through to.

# Builtins only, called underneath as `zle .$w`; anything else is skipped, since
# `zle .$w` would bypass another plugin's wrapper.
_zhimmer_wrap_builtin() {  # <handler> <widget>...
  local w
  for w in ${@:2}; do
    [[ ${widgets[$w]} == builtin ]] || continue
    functions[.zhimmer-wrap-$w]="$1 .$w"
    zle -N $w .zhimmer-wrap-$w
  done
}

# Copied aside with `zle -A` and the copy called, keeping whatever was already
# there in the chain -- other plugins' self-insert wrappers, and compsys behind
# the completion widgets (`.expand-or-complete` is zsh's dumb completion).
# Idempotent: re-run after zsh-vi-mode's init, it only wraps what changed.
_zhimmer_wrap_chain() {  # <handler> <widget>...
  local w
  for w in ${@:2}; do
    (( ${+widgets[$w]} )) || continue
    [[ ${widgets[$w]} == user:.zhimmer-wrap-$w ]] && continue
    zle -A $w .zhimmer-orig-$w
    functions[.zhimmer-wrap-$w]="$1 .zhimmer-orig-$w"
    zle -N $w .zhimmer-wrap-$w
  done
}

_zhimmer_refresh_with() {  # <widget>
  _zhimmer_zle_clear
  zle $1
  _zhimmer_maybe_show
}

# Every way out says what becomes of the rows: deciding not to draw must clear,
# or a deleted line leaves a list describing a buffer that no longer exists.
_zhimmer_maybe_show() {
  (( _zhimmer_enabled )) || { _zhimmer_zle_clear; return }
  # Mid-burst (fast typing, paste): skip, and leave the rows standing so they
  # do not flicker; the last key of the burst redraws.
  (( PENDING || KEYS_QUEUED_COUNT )) && return
  # A search is the question itself, so min-chars does not apply to it.
  if (( ! _zhimmer_search )); then
    local REPLY; _zhimmer_cfg min-chars
    (( ${#LBUFFER} >= REPLY )) || { _zhimmer_zle_clear; return }
  fi

  typeset -g _zhimmer_top=
  typeset -gi _zhimmer_top_rank=0
  # Before the draw: the redraw the draw provokes must not see it as stale.
  typeset -g _zhimmer_shown_for=$BUFFER
  zle zhimmer-show      # the gather, inside `zle -C` for $words/$PREFIX
  _zhimmer_zle_show
}

# Down/Up move over drawn rows (wrapping, so from nothing they land on the
# first/last). With none drawn, Down is plain history and Up opens the history.
.zhimmer-down() {
  (( _zhimmer_enabled )) && _zhimmer_zle_move 1 && return
  zle .down-line-or-history
}

.zhimmer-up() {
  (( _zhimmer_enabled )) || { zle .up-line-or-history; return }
  _zhimmer_zle_move -1 && return
  # Nothing drawn (empty line, under min-chars): open the history as a search,
  # which answers an empty query with every line newest first, then wrap to the
  # last row as Up does on an open menu.
  _zhimmer_search=1
  _zhimmer_maybe_show
  _zhimmer_zle_move -1 && return
  _zhimmer_search=0
  _zhimmer_zle_clear
  zle .up-line-or-history
}

# Shift+Tab steps back through what Tab is stepping through. Whether there is
# anything to step through cannot come from LASTWIDGET (fzf-completion wraps
# Tab), so the completion records "<cursor> <buffer>" and this matches it.
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

# Ctrl+R: the same drop-down, matching anywhere in a line. Pressed again, steps
# to the next match. With zhimmer off the key keeps its usual meaning.
.zhimmer-search() {
  if (( ! _zhimmer_enabled )); then
    zle .history-incremental-search-backward
    return
  fi
  if (( _zhimmer_search )); then
    _zhimmer_zle_move 1
    return
  fi
  _zhimmer_search=1
  _zhimmer_maybe_show
}

# Off draws nothing, which looks broken, so say so and how to undo it.
.zhimmer-toggle() {
  _zhimmer_enabled=$(( ! _zhimmer_enabled ))
  if (( _zhimmer_enabled )); then
    _zhimmer_maybe_show
  else
    _zhimmer_zle_clear
    local REPLY; _zhimmer_cfg toggle-key
    [[ $REPLY == '^@' ]] && REPLY='Ctrl+Space'
    zle -M "zhimmer off -- $REPLY turns it back on"
  fi
}

# Widgets that shorten or rewrite the line, refreshed rather than left stale. A
# convenience: the redraw guard in ghost.zsh drops rows for anything missing.
typeset -ga ZHIMMER_REFRESH_WIDGETS=(
  backward-delete-char    vi-backward-delete-char
  backward-kill-word      vi-backward-kill-word
  delete-char             vi-delete-char
  kill-word               kill-line
  backward-kill-line      kill-whole-line
  kill-region             yank                    yank-pop
  undo                    redo
  vi-kill-line            vi-kill-eol             vi-delete
  vi-change               vi-change-eol           vi-change-whole-line
  vi-substitute           vi-put-after            vi-put-before
)

# Keys that take the whole ghost at end of line (as zsh-autosuggestions) and
# move the cursor anywhere else. Not Tab: that is compsys's.
typeset -ga ZHIMMER_ACCEPT_WIDGETS=(
  forward-char  vi-forward-char
  end-of-line   vi-end-of-line   vi-add-eol
)

_zhimmer_accept_with() {  # <widget>
  _zhimmer_accept_ghost || zle $1
}

# The same, a word at a time, measured by the wrapped widget itself.
typeset -ga ZHIMMER_ACCEPT_WORD_WIDGETS=(
  forward-word  vi-forward-word  vi-forward-word-end  emacs-forward-word
)

_zhimmer_accept_word_with() {  # <widget>
  _zhimmer_accept_ghost $1 || zle $1
}

# Tab owns the listing area but only takes it back from zhimmer: clear our rows
# before completing, never zsh's (it keeps one list across a run of Tabs).
# Redraw ours only when exactly one match means the word is finished.
typeset -ga ZHIMMER_COMPLETE_WIDGETS=(
  expand-or-complete  complete-word  expand-or-complete-prefix
  menu-complete       menu-expand-or-complete
)

_zhimmer_after_complete() {  # <saved-widget>
  _zhimmer_zle_clear
  _zhimmer_style_matches
  { zle $1 } always { _zhimmer_unstyle_matches }
  (( ${_lastcomp[nmatches]:-0} == 1 )) && _zhimmer_maybe_show
  _zhimmer_note_menu
  return 0
}

# Point Ctrl+E/End at end-of-line, and Ctrl+Right/Alt+Right/Alt+f at
# forward-word, where they are unbound or self-insert (bare viins). The keymap
# is read once -- reading bindkey back is a fork -- not once per key.
_zhimmer_bind_motion() {
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
  for k in '^[[1;5C' '^[[1;3C' '^[f'; do
    [[ ${bound[$k]} == (self-insert|) ]] && bindkey -M $m $k forward-word
  done
  return 0
}

# Tab's menu (complist's menuselect). Esc backs out -- bound here and nowhere
# else, as it is vi-mode's switch and every arrow's prefix. Backspace must name
# the builtin, or it leaves the menu taking the row. Shift+Tab has no default
# here and fell through to the main keymap, completing a second word.
_zhimmer_bind_menuselect() {
  bindkey -M menuselect '^[' send-break
  bindkey -M menuselect '^?' backward-delete-char
  bindkey -M menuselect '^H' backward-delete-char
  bindkey -M menuselect '^[[Z' reverse-menu-complete
  return 0
}
