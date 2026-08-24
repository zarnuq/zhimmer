# zhimmer -- an as-you-type dropdown menu for zsh.
#
# The menu is drawn by zsh's own zsh/complist, fed through compadd, so it
# inherits scrolling, resize handling and terminal safety rather than
# reimplementing them. History matching and frecency ranking are done by the
# zhimmer-match binary (see zhimmer-match/). See README.md.

(( ${+_zhimmer_loaded} )) && return 0
typeset -g _zhimmer_loaded=1

# %N is this file even when sourced, unlike $0 under some options.
0=${(%):-%N}
typeset -g ZHIMMER_DIR=${0:A:h}
typeset -g ZHIMMER_BIN=$ZHIMMER_DIR/zhimmer-match/target/release/zhimmer-match

zmodload -i zsh/complist || return 1

# Toggled by zhimmer-toggle (Shift+Tab).
typeset -g _zhimmer_enabled=1

typeset -g f
for f in $ZHIMMER_DIR/lib/theme.zsh(N) $ZHIMMER_DIR/lib/*.zsh(N) $ZHIMMER_DIR/sources/*.zsh(N); do
  source $f
done
unset f

# Draw-only: lists candidates without touching the buffer, so it can run on
# every keystroke without blocking.
zle -C zhimmer-show list-choices .zhimmer-complete-list
# Interactive: hands off to the menuselect keymap for arrow navigation.
# This must bind against complist's `menu-select`, not `menu-complete` -- the
# `menu select` zstyle is read by _main_complete, which a raw zle -C widget
# never goes through.
zle -C zhimmer-menu menu-select .zhimmer-complete-menu

zle -N zhimmer-toggle      .zhimmer-toggle
zle -N zhimmer-down        .zhimmer-down
zle -N zhimmer-magic-space .zhimmer-magic-space
zle -N self-insert         .zhimmer-self-insert
_zhimmer_wrap_refresh
_zhimmer_wrap_accept

autoload -Uz add-zle-hook-widget
zle -N _zhimmer_ghost_guard
add-zle-hook-widget line-pre-redraw _zhimmer_ghost_guard

_zhimmer_bindkeys() {
  local m
  for m in emacs viins; do
    bindkey -M $m '^[[B' zhimmer-down         # Down
    bindkey -M $m '^[[Z' zhimmer-toggle       # Shift+Tab
    bindkey -M $m ' '    zhimmer-magic-space  # Space expands the alias in place
  done
  # Enter expands a bare alias too. Done here, after zsh-vi-mode's init, so the
  # chain wraps vi-mode's accept-line rather than being wiped by it.
  _zhimmer_wrap_acceptline
  # Inside the menu: Tab accepts, Esc backs out restoring the original line.
  # Esc is deliberately NOT bound outside the menu -- it is zsh-vi-mode's
  # normal-mode switch, and it prefixes every arrow-key sequence.
  bindkey -M menuselect '^I' accept-line
  bindkey -M menuselect '^[' send-break
}

# zsh-vi-mode wipes all keybindings during its own init, so registering ours
# before it loads would silently lose them.
if (( ${+ZVM_INIT_MODE} )) || (( ${+functions[zvm_before_init]} )); then
  typeset -ga zvm_after_init_commands
  zvm_after_init_commands+=( _zhimmer_bindkeys )
else
  _zhimmer_bindkeys
fi
