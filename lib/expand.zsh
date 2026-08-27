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

# Where a command alias is allowed to expand. Not just the start of the line:
# `make; gs` and `ls | gs` are command positions too, and testing for "nothing
# but whitespace before it" left the alias sitting there unexpanded in every
# pipeline and after every `;`.
#
# The test is on the last non-whitespace character before the word, so a `|`
# earlier in the line does not make everything after it look like a command:
# `echo a| b gs` is an argument to `b`, and asking only whether the text
# contains a delimiter would have expanded it.
_zhimmer_command_pos() {  # <the text before the word>
  local b=$1
  b=${b[1,${#b}-${#${b##*[^[:space:]]}}]}   # without its trailing whitespace
  [[ -z $b || $b == *[\;\|\&\(\)\{\}] ]]
}

_zhimmer_expand_alias() {
  emulate -L zsh
  _zhimmer_bool expand-alias || return 1

  local word=${LBUFFER##*[[:space:]]}
  [[ -n $word ]] || return 1
  # By length rather than by pattern. ${LBUFFER%$word} matches the word as a
  # glob, so a word ending in `*` or holding a `[1]` strips the wrong amount --
  # or, when the pattern happens not to match at all, nothing, leaving the alias
  # duplicated in the line.
  local before=${LBUFFER[1,${#LBUFFER}-${#word}]} exp=
  if [[ -n $galiases[$word] ]]; then
    exp=$galiases[$word]
  elif [[ -n $aliases[$word] ]] && _zhimmer_command_pos $before; then
    exp=$aliases[$word]
  fi
  [[ -n $exp ]] || return 1

  local -A seen; seen[$word]=1; local head
  while head=${exp%%[[:space:]]*}; [[ -n $aliases[$head] && -z $seen[$head] ]]; do
    seen[$head]=1; exp=$aliases[$head]${exp:${#head}}
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
