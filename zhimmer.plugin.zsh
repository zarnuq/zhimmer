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

# Toggled by zhimmer-toggle, on toggle-key (Ctrl+Space by default).
typeset -g _zhimmer_enabled=1

# Every scalar setting and its default, in one table: _zhimmer_cfg and
# _zhimmer_bool read it and zhimmer-doctor prints it, so a default is written
# down once instead of at each call site and again in the diagnostics. The
# `sources` style is not here -- it is an array, read with zstyle -a.
typeset -gA ZHIMMER_DEFAULTS=(
  max-suggestions   10
  menu-suggestions  50
  min-chars         2
  ghost-text        yes
  ghost-color       'fg=#6c7086'
  expand-alias      yes
  tame-lists        yes
  type-to-filter    yes
  style-completion  yes
  toggle-key        '^@'
)

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
zle -N zhimmer-step-back   .zhimmer-step-back
zle -N zhimmer-down        .zhimmer-down
zle -N zhimmer-magic-space .zhimmer-magic-space
zle -N self-insert         .zhimmer-self-insert
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
  local m REPLY
  # The on/off switch, on a key of its own so it is not hit by accident.
  _zhimmer_cfg toggle-key       # ^@ (Ctrl+Space) unless the style says otherwise
  local tkey=$REPLY
  for m in emacs viins; do
    bindkey -M $m '^[[B' zhimmer-down         # Down
    bindkey -M $m '^[[Z' zhimmer-step-back    # Shift+Tab steps back up
    [[ -n $tkey ]] && bindkey -M $m $tkey zhimmer-toggle
    bindkey -M $m ' '    zhimmer-magic-space  # Space expands the alias in place
    _zhimmer_bind_eol $m                      # Ctrl+E / End accept the ghost
  done
  # compinit replaces the completion widgets when it runs, so re-assert the wrap
  # here as well: sourcing zhimmer before compinit would otherwise lose it.
  _zhimmer_wrap_complete
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
