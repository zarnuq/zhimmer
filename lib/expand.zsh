# In-buffer alias expansion on Space and Enter: `gs ` becomes `git status -s `.
# Command aliases only in command position, global aliases anywhere. Chains
# resolve one step at a time; an alias never re-expands inside its own
# expansion, so `ls='ls --color'` expands once.

# Command position: the last non-space character before the word is a
# delimiter, or there is none. (`echo a| b gs` is an argument to `b`.)
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
  # By length, not ${LBUFFER%$word}: the word may hold glob characters.
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

.zhimmer-magic-space() {
  _zhimmer_zle_clear
  _zhimmer_expand_alias
  zle .self-insert
  _zhimmer_maybe_show
}

# Enter: take the selected row, else expand a bare alias so the real command
# runs and lands in history. Chained onto whatever accept-line already is.
_zhimmer_accept_line_with() {  # <widget>
  _zhimmer_zle_accept && return
  _zhimmer_expand_alias
  zle $1
}
