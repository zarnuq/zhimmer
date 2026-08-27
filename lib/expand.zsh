# In-buffer alias expansion. Rather than offering an alias's expansion as a menu
# row, this rewrites the alias in the buffer so the real command fills the line:
# typing `gs ` leaves `git status -s ` in front of you, editable before it runs.
# It fires on Space and Enter -- the two points where a word is finished.
#
# Command aliases expand only in command position, matching zsh's own rule;
# global aliases expand anywhere. Chains resolve one alias at a time (gcm -> gc
# -> git commit), and seeding `seen` with the word reproduces zsh's rule that an
# alias is never re-expanded inside its own expansion, so `ls='ls --color'`
# expands exactly once.

_zhimmer_expand_alias() {
  emulate -L zsh
  _zhimmer_bool expand-alias || return 1

  local word=${LBUFFER##*[[:space:]]}
  [[ -n $word ]] || return 1
  local before=${LBUFFER%$word} exp=
  if [[ -n ${galiases[$word]} ]]; then
    exp=${galiases[$word]}
  elif [[ -n ${aliases[$word]} && $before != *[^[:space:]]* ]]; then
    exp=${aliases[$word]}
  fi
  [[ -n $exp ]] || return 1

  local -A seen; seen[$word]=1; local head
  while head=${exp%%[[:space:]]*}; [[ -n ${aliases[$head]} && -z ${seen[$head]} ]]; do
    seen[$head]=1; exp="${aliases[$head]}${exp#$head}"
  done

  LBUFFER=$before$exp
  return 0
}

# Space: expand the word just finished, then insert the space and refresh the
# menu as a normal keystroke would.
.zhimmer-magic-space() {
  _zhimmer_clear_ghost
  _zhimmer_expand_alias
  zle .self-insert
  _zhimmer_maybe_show
}

# Enter: expand a bare alias so the command that runs -- and lands in history --
# is the real one. Chains onto whatever accept-line already is (zsh-vi-mode,
# zsh-syntax-highlighting) instead of clobbering it.
_zhimmer_wrap_acceptline() {
  [[ ${widgets[accept-line]} == user:.zhimmer-accept-line ]] && return
  zle -A accept-line .zhimmer-orig-accept-line
  functions[.zhimmer-accept-line]='
    _zhimmer_expand_alias
    zle .zhimmer-orig-accept-line
  '
  zle -N accept-line .zhimmer-accept-line
}
