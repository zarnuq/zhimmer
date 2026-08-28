# zhimmer -- an as-you-type dropdown menu for zsh.
#
# The menu is drawn by zsh's own zsh/complist, fed through compadd, so it
# inherits scrolling, resize handling and terminal safety rather than
# reimplementing them. Nothing here is compiled and nothing forks: the history
# ranking is zsh's own $history, searched in place. See README.md.

(( ${+_zhimmer_loaded} )) && return 0
typeset -g _zhimmer_loaded=1

# %N is this file even when sourced, unlike $0 under some options.
0=${(%):-%N}
typeset -g ZHIMMER_DIR=${0:A:h}

zmodload -i zsh/complist || return 1

# Toggled by zhimmer-toggle, on toggle-key (Ctrl+Space by default).
typeset -g _zhimmer_enabled=1

# Alphabetical, and every file in one pass. Naming theme.zsh first as well as
# letting the glob find it sourced it twice; nothing here runs at source time
# beyond defining functions and setting defaults, so there is no order to keep.
# The loop variable is namespaced because this runs at file scope, where `local`
# does not exist -- a bare `f` would take the user's own `f` with it on unset.
typeset -g _zhimmer_f
for _zhimmer_f in $ZHIMMER_DIR/lib/*.zsh(N) $ZHIMMER_DIR/sources/*.zsh(N); do
  source $_zhimmer_f
done
unset _zhimmer_f

# Draw-only: lists candidates without touching the buffer, so it can run on
# every keystroke without blocking.
zle -C zhimmer-show list-choices .zhimmer-complete-list
# Interactive: hands off to the menuselect keymap for arrow navigation.
# This must bind against complist's `menu-select`, not `menu-complete` -- the
# `menu select` zstyle is read by _main_complete, which a raw zle -C widget
# never goes through.
zle -C zhimmer-menu menu-select .zhimmer-complete-menu

zle -N zhimmer-toggle      .zhimmer-toggle
zle -N zhimmer-step-back   .zhimmer-step-back
zle -N zhimmer-down        .zhimmer-down
zle -N zhimmer-magic-space .zhimmer-magic-space
_zhimmer_wrap_self_insert
_zhimmer_wrap_refresh
_zhimmer_wrap_accept
_zhimmer_wrap_complete

_zhimmer_tame_lists

autoload -Uz add-zle-hook-widget
zle -N _zhimmer_ghost_guard
add-zle-hook-widget line-pre-redraw _zhimmer_ghost_guard
# Ghost text is not part of BUFFER, so it must not survive onto an accepted line.
zle -N _zhimmer_ghost_finish
add-zle-hook-widget line-finish _zhimmer_ghost_finish

_zhimmer_bindkeys() {
  # Declared once, not per iteration: a second bare `local` on a name that is
  # already local prints it, so the loop would echo the binding at every startup.
  local m k REPLY
  # The on/off switch, on a key of its own so it is not hit by accident.
  _zhimmer_cfg toggle-key       # ^@ (Ctrl+Space) unless the style says otherwise
  local tkey=$REPLY
  # Which bytes Down arrives as depends on the terminal: ^[[B normally, ^[OB
  # once something has put it into application-cursor mode, and neither is
  # guaranteed to be what this terminfo entry names. zsh's own keymap binds both
  # forms for that reason, so zhimmer binds both and whatever terminfo adds on
  # top. (V) writes the terminfo string in the same caret notation bindkey and
  # _zhimmer_bind_eol read, and an entry the terminal does not have expands to
  # nothing rather than to an empty binding.
  zmodload -i zsh/terminfo 2>/dev/null
  local -a down=( '^[[B' '^[OB' ${(V)terminfo[kcud1]} )
  local -a btab=( '^[[Z' ${(V)terminfo[kcbt]} )
  for m in emacs viins; do
    for k in $down; do bindkey -M $m $k zhimmer-down; done          # Down
    for k in $btab; do bindkey -M $m $k zhimmer-step-back; done     # Shift+Tab
    [[ -n $tkey ]] && bindkey -M $m $tkey zhimmer-toggle
    bindkey -M $m ' '    zhimmer-magic-space  # Space expands the alias in place
    _zhimmer_bind_eol $m                      # Ctrl+E / End accept the ghost
  done
  # compinit replaces the completion widgets when it runs, so re-assert that wrap
  # here: sourcing zhimmer before compinit would otherwise lose it. self-insert
  # goes with it because this point is after zsh-vi-mode's init too, and the
  # guard makes it a no-op unless something in between has taken the widget.
  _zhimmer_wrap_complete
  _zhimmer_wrap_self_insert
  # Enter expands a bare alias too. Done here, after zsh-vi-mode's init, so the
  # chain wraps vi-mode's accept-line rather than being wiped by it.
  _zhimmer_wrap_acceptline
  # Inside the menu. Esc is bound there and deliberately nowhere else -- it is
  # zsh-vi-mode's normal-mode switch, and it prefixes every arrow-key sequence.
  _zhimmer_bind_menuselect
}

# zsh-vi-mode wipes all keybindings during its own init, so registering ours
# before it loads would silently lose them.
if (( ${+ZVM_INIT_MODE} )) || (( ${+functions[zvm_before_init]} )); then
  typeset -ga zvm_after_init_commands
  zvm_after_init_commands+=( _zhimmer_bindkeys )
else
  _zhimmer_bindkeys
fi
