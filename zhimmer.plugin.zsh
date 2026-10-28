# zhimmer -- an as-you-type dropdown menu for zsh. See README.md.

(( ${+_zhimmer_loaded} )) && return 0
typeset -g _zhimmer_loaded=1

0=${(%):-%N}    # this file even when sourced
typeset -g ZHIMMER_DIR=${0:A:h}

zmodload -i zsh/complist || return 1    # draws Tab's listing

typeset -g _zhimmer_enabled=1

# Nothing runs at source time but definitions, so order does not matter. The
# loop variable is namespaced: at file scope there is no `local`.
typeset -g _zhimmer_f
for _zhimmer_f in $ZHIMMER_DIR/lib/*.zsh(N) $ZHIMMER_DIR/sources/*.zsh(N); do
  source $_zhimmer_f
done

# A colour override file, sourced once the tables exist and before anything
# reads them (the Tab styling below, the prompt). It assigns into the tables in
# lib/theme.zsh and lib/prompt.zsh; it is plain zsh, so a theme switcher can
# write one. Only new shells see a change.
_zhimmer_cfg theme-file
[[ -n $REPLY && -r ${~REPLY} ]] && source ${~REPLY}

zle -C zhimmer-show list-choices .zhimmer-complete

for _zhimmer_f in toggle search step-back down up magic-space; do
  zle -N zhimmer-$_zhimmer_f .zhimmer-$_zhimmer_f
done
unset _zhimmer_f
# self-insert, accept-line and Tab are chained from _zhimmer_bindkeys instead.
_zhimmer_wrap_builtin _zhimmer_refresh_with     $ZHIMMER_REFRESH_WIDGETS
_zhimmer_wrap_builtin _zhimmer_accept_with      $ZHIMMER_ACCEPT_WIDGETS
_zhimmer_wrap_builtin _zhimmer_accept_word_with $ZHIMMER_ACCEPT_WORD_WIDGETS

_zhimmer_tame_lists

_zhimmer_bool prompt && zhimmer-prompt-on

autoload -Uz add-zle-hook-widget
zle -N _zhimmer_ghost_guard
add-zle-hook-widget line-pre-redraw _zhimmer_ghost_guard
zle -N _zhimmer_line_reset
add-zle-hook-widget line-finish _zhimmer_line_reset
add-zle-hook-widget line-init   _zhimmer_line_reset
(( $+functions[TRAPINT] )) && functions[_zhimmer_orig_trapint]=$functions[TRAPINT]
TRAPINT() { _zhimmer_trapint "$@"; return }  # an explicit return: a bare status does not abort the line

# Idempotent: every wrapper it calls has its own guard.
_zhimmer_bindkeys() {
  local m k REPLY      # once, not per iteration: a repeat `local` prints
  _zhimmer_cfg toggle-key
  local tkey=$REPLY
  _zhimmer_cfg search-key
  local skey=$REPLY
  # Both cursor-key forms (normal and application mode) plus terminfo's.
  zmodload -i zsh/terminfo 2>/dev/null
  local -a down=( '^[[B' '^[OB' ${(V)terminfo[kcud1]} )
  local -a up=( '^[[A' '^[OA' ${(V)terminfo[kcuu1]} )
  local -a btab=( '^[[Z' ${(V)terminfo[kcbt]} )
  for m in emacs viins; do
    for k in $down; do bindkey -M $m $k zhimmer-down; done
    for k in $up;   do bindkey -M $m $k zhimmer-up;   done
    for k in $btab; do bindkey -M $m $k zhimmer-step-back; done
    [[ -n $tkey ]] && bindkey -M $m $tkey zhimmer-toggle
    [[ -n $skey ]] && bindkey -M $m $skey zhimmer-search
    bindkey -M $m ' '    zhimmer-magic-space
    _zhimmer_bind_motion $m
  done
  # compinit and zsh-vi-mode both replace widgets, so these are re-chained here.
  _zhimmer_wrap_chain _zhimmer_after_complete $ZHIMMER_COMPLETE_WIDGETS
  _zhimmer_wrap_chain _zhimmer_refresh_with self-insert
  _zhimmer_wrap_chain _zhimmer_accept_line_with accept-line
  _zhimmer_bind_menuselect
}

# Now *and* after zsh-vi-mode's init: zvm binds some of the same keys (^R) in
# an init deferred to the first precmd, but under ZVM_INIT_MODE=sourcing its
# after-init commands have already run. Detected on ZVM_VERSION, which zvm
# itself sets -- not on things the user may define.
_zhimmer_bindkeys
if (( ${+ZVM_VERSION} )) || (( ${+functions[zvm_init]} )); then
  typeset -ga zvm_after_init_commands
  zvm_after_init_commands+=( _zhimmer_bindkeys )
fi
