# zhimmer -- an as-you-type dropdown menu for zsh.
#
# The menu is drawn by zhimmer itself, into POSTDISPLAY, coloured with
# region_highlight (lib/zlemenu.zsh). zsh/complist is still loaded because it
# is what draws Tab's listing, which lib/tabstyle.zsh restyles. Nothing here is
# compiled and nothing forks: the history ranking is zsh's own $history,
# searched in place. See README.md.

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

# The one completion widget, and it adds nothing: what it is for is the
# completion context -- $words, $PREFIX, $CURRENT -- which is how every source
# decides whether it applies. The rows it gathers are drawn by lib/zlemenu.zsh
# rather than listed by zsh, so this never touches the buffer and can run on
# every keystroke.
zle -C zhimmer-show list-choices .zhimmer-complete

zle -N zhimmer-toggle      .zhimmer-toggle
zle -N zhimmer-search      .zhimmer-search
zle -N zhimmer-step-back   .zhimmer-step-back
zle -N zhimmer-down        .zhimmer-down
zle -N zhimmer-up          .zhimmer-up
zle -N zhimmer-magic-space .zhimmer-magic-space
_zhimmer_wrap_self_insert
_zhimmer_wrap_refresh
_zhimmer_wrap_accept
_zhimmer_wrap_accept_word
_zhimmer_wrap_complete

_zhimmer_tame_lists

# The prompt is opt-in, and reads its style here rather than at source time so
# the libraries stay side-effect free for test/unit.zsh.
_zhimmer_bool prompt && zhimmer-prompt-on

autoload -Uz add-zle-hook-widget
zle -N _zhimmer_ghost_guard
add-zle-hook-widget line-pre-redraw _zhimmer_ghost_guard
# Ghost text is not part of BUFFER, so it must not survive onto an accepted
# line; and a search abandoned with Ctrl+C -- which never reaches line-finish --
# must not still be on when the next line starts.
zle -N _zhimmer_line_reset
add-zle-hook-widget line-finish _zhimmer_line_reset
add-zle-hook-widget line-init   _zhimmer_line_reset

_zhimmer_bindkeys() {
  # Declared once, not per iteration: a second bare `local` on a name that is
  # already local prints it, so the loop would echo the binding at every startup.
  local m k REPLY
  # The on/off switch, on a key of its own so it is not hit by accident.
  _zhimmer_cfg toggle-key       # ^@ (Ctrl+Space) unless the style says otherwise
  local tkey=$REPLY
  _zhimmer_cfg search-key       # ^R, the key it already was
  local skey=$REPLY
  # Which bytes Down arrives as depends on the terminal: ^[[B normally, ^[OB
  # once something has put it into application-cursor mode, and neither is
  # guaranteed to be what this terminfo entry names. zsh's own keymap binds both
  # forms for that reason, so zhimmer binds both and whatever terminfo adds on
  # top. (V) writes the terminfo string in the same caret notation bindkey and
  # _zhimmer_bind_motion read, and an entry the terminal does not have expands to
  # nothing rather than to an empty binding.
  zmodload -i zsh/terminfo 2>/dev/null
  local -a down=( '^[[B' '^[OB' ${(V)terminfo[kcud1]} )
  local -a up=( '^[[A' '^[OA' ${(V)terminfo[kcuu1]} )
  local -a btab=( '^[[Z' ${(V)terminfo[kcbt]} )
  for m in emacs viins; do
    for k in $down; do bindkey -M $m $k zhimmer-down; done          # Down
    for k in $up;   do bindkey -M $m $k zhimmer-up;   done          # Up
    for k in $btab; do bindkey -M $m $k zhimmer-step-back; done     # Shift+Tab
    [[ -n $tkey ]] && bindkey -M $m $tkey zhimmer-toggle
    [[ -n $skey ]] && bindkey -M $m $skey zhimmer-search
    bindkey -M $m ' '    zhimmer-magic-space  # Space expands the alias in place
    _zhimmer_bind_motion $m                   # Ctrl+E / End, and Ctrl+Right
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

# Bind now, and again after zsh-vi-mode's init if that is coming.
#
# zvm binds some of these keys itself -- `zvm_bindkey viins '^R'
# history-incremental-search-backward` is in its init -- and by default that
# init is deferred to the first precmd, which is after every plugin has loaded.
# So binding at load time alone loses whichever keys zvm also wants, silently
# and only for those keys: Down and Ctrl+Space survived, Ctrl+R did not, which
# reads as one broken key rather than as a load-order problem.
#
# Detected on ZVM_VERSION, which zvm sets `typeset -gr` as it is sourced. The
# two markers this used to test -- ZVM_INIT_MODE and a zvm_before_init function
# -- are things the *user* may define, not things zvm defines, so with a stock
# zsh-vi-mode neither existed and this test was never once true.
#
# Bound immediately as well as deferred, rather than one or the other, because
# `ZVM_INIT_MODE=sourcing` inits zvm as it is sourced: the after-init commands
# have then already run by the time this file is read, and appending to them
# would be appending to a list nothing will look at again. _zhimmer_bindkeys is
# idempotent -- bindkey is, and every wrapper it calls has its own guard -- so
# running it twice costs a few bindkey calls at startup and nothing else.
_zhimmer_bindkeys
if (( ${+ZVM_VERSION} )) || (( ${+functions[zvm_init]} )); then
  typeset -ga zvm_after_init_commands
  zvm_after_init_commands+=( _zhimmer_bindkeys )
fi
