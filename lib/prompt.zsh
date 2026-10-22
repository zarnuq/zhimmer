# Optional prompt, off unless `zstyle ':zhimmer:*' prompt yes`.
#
# Directory, branch and exit status are drawn synchronously with no forks (the
# branch is read from .git/HEAD). Working-tree symbols come from one background
# `git status`, delivered by a `zle -F` handler that redraws the prompt. It
# saves and restores whatever PROMPT it found.

typeset -gA ZHIMMER_PROMPT_SYMBOLS=(
  untracked '?'
  staged    '+'
  modified  '!'
  renamed   '»'
  deleted   '✘'
  unmerged  '='
  ahead     '⇡'
  behind    '⇣'
)

typeset -gA ZHIMMER_PROMPT_COLORS=(
  path    '#89b4fa'
  branch  '#cba6f7'
  status  '#f9e2af'
  arrows  '#fab387'
  ok      '#a6e3a1'
  error   '#f38ba8'
)

# Spaceship's rendering order.
typeset -ga ZHIMMER_PROMPT_ORDER=(
  unmerged deleted renamed modified staged untracked
)

typeset -g ZHIMMER_PROMPT_SYMBOL=' >'

# The .git of the repository $PWD is in. A *file* holding `gitdir: <path>` in a
# linked worktree or submodule, not always a directory.
_zhimmer_prompt_gitdir() {  # -> REPLY
  local d=$PWD g line
  REPLY=
  while :; do
    g=$d/.git
    if [[ -d $g ]]; then
      REPLY=$g; return 0
    elif [[ -f $g ]]; then
      read -r line < $g 2>/dev/null || return 1
      [[ $line == 'gitdir: '* ]] || return 1
      REPLY=${line#gitdir: }
      [[ $REPLY == /* ]] || REPLY=$d/$REPLY   # relative to the file naming it
      return 0
    fi
    [[ -z $d || $d == / ]] && break
    d=${d%/*}
    [[ -z $d ]] && d=/
  done
  return 1
}

# Strip the literal prefix, never ${head##*/}: `refs/heads/feat/menu` would
# come back as `menu`.
_zhimmer_prompt_branch() {  # -> REPLY, empty outside a repository
  local head
  REPLY=
  _zhimmer_prompt_gitdir || return 1
  read -r head < $REPLY/HEAD 2>/dev/null || { REPLY=; return 1 }
  if [[ $head == 'ref: refs/heads/'* ]]; then
    REPLY=${head#ref: refs/heads/}
  elif [[ $head == 'ref: '* ]]; then
    REPLY=${head#ref: }
  else
    REPLY=${head[1,7]}          # detached: the short sha
  fi
  [[ -n $REPLY ]]
}

# Porcelain v1 text in, symbols out. X is the index column, Y the work tree;
# combinations are Spaceship's. Independent tests, since `MM` is both staged
# and modified.
_zhimmer_prompt_symbols() {  # <git status --porcelain=v1 --branch text> -> REPLY
  local -A f
  local l x y k
  local ahead= behind=
  REPLY=

  for l in ${(f)1}; do
    if [[ $l == '## '* ]]; then
      # `## main...origin/main [ahead 1, behind 2]`
      [[ $l == *'[ahead '* ]] && { ahead=${l#*\[ahead }; ahead=${ahead%%[,\]]*} }
      [[ $l == *'behind '* ]] && { behind=${l#*behind }; behind=${behind%%[,\]]*} }
      continue
    fi
    (( ${#l} > 2 )) || continue
    x=${l[1]} y=${l[2]}

    if [[ $x == '?' && $y == '?' ]]; then f[untracked]=1; continue; fi
    [[ $x == '!' && $y == '!' ]] && continue          # ignored

    [[ $x == A && $y == (' '|M|D|A|U) ]] && f[staged]=1
    [[ $x == M && $y == (' '|M|D) ]]     && f[staged]=1
    [[ $x == U && $y == A ]]             && f[staged]=1

    [[ $x == (' '|M|A|R|C) && $y == M ]] && f[modified]=1

    [[ $x == R && $y == (' '|M|D) ]]     && f[renamed]=1

    [[ $x == (M|A|R|C|D|U|' ') && $y == D ]] && f[deleted]=1
    [[ $x == D && $y == (' '|U|M) ]]         && f[deleted]=1

    [[ $x == U && $y == (U|D|A) ]] && f[unmerged]=1
    [[ $x == A && $y == A ]]       && f[unmerged]=1
    [[ $x == D && $y == D ]]       && f[unmerged]=1
    [[ $x == (D|A) && $y == U ]]   && f[unmerged]=1
  done

  for k in $ZHIMMER_PROMPT_ORDER; do
    (( ${+f[$k]} )) && REPLY+=${ZHIMMER_PROMPT_SYMBOLS[$k]}
  done

  [[ -n $ahead  ]] && (( ahead ))  && REPLY+=${ZHIMMER_PROMPT_SYMBOLS[ahead]}$ahead
  [[ -n $behind ]] && (( behind )) && REPLY+=${ZHIMMER_PROMPT_SYMBOLS[behind]}$behind
  [[ -n $REPLY ]]
}

# One fork for everything. GIT_OPTIONAL_LOCKS=0 keeps it off the index lock, so
# it does not fight a `git commit` in another pane.
_zhimmer_prompt_git_query() {  # -> REPLY
  _zhimmer_prompt_symbols \
    "$(GIT_OPTIONAL_LOCKS=0 command git status --porcelain=v1 --branch 2>/dev/null)"
}

typeset -g _zhimmer_prompt_ret=0
typeset -g _zhimmer_prompt_br=
typeset -g _zhimmer_prompt_git=

# Exit status is baked in, never `%(?..)`: after the async `zle reset-prompt`,
# $? describes the redraw. `%` in a branch name is escaped.
_zhimmer_prompt_build() {
  local -A c=( "${(@kv)ZHIMMER_PROMPT_COLORS}" )
  local line=" %F{$c[path]}%~%f"
  [[ -n $_zhimmer_prompt_br ]]  && line+=" %F{$c[branch]}${_zhimmer_prompt_br//\%/%%}%f"
  [[ -n $_zhimmer_prompt_git ]] && line+=" %F{$c[status]}${_zhimmer_prompt_git}%f"
  local col=$c[ok]
  (( _zhimmer_prompt_ret )) && col=$c[error]
  PROMPT="$line"$'\n'"%F{$col}${ZHIMMER_PROMPT_SYMBOL}%f "
}

typeset -g _zhimmer_prompt_fd=
typeset -gi _zhimmer_prompt_gen=0

_zhimmer_prompt_cancel() {
  [[ -n $_zhimmer_prompt_fd ]] || return 0
  zle -F $_zhimmer_prompt_fd 2>/dev/null
  # Braced: on a bare `exec` the 2>/dev/null would be permanent.
  { exec {_zhimmer_prompt_fd}<&- } 2>/dev/null
  _zhimmer_prompt_fd=
  return 0
}

# The child parses and prints one short line -- atomic under PIPE_BUF, so one
# `read` gets it all. The generation number marks a result from a directory
# since left.
_zhimmer_prompt_start() {
  _zhimmer_prompt_cancel
  setopt localoptions nomonitor nonotify   # no `[1] 12345` over the prompt
  local -i gen=$(( ++_zhimmer_prompt_gen ))
  exec {_zhimmer_prompt_fd}< <(
    local REPLY
    _zhimmer_prompt_git_query
    print -r -- "$gen"$'\t'"$REPLY"
  )
  zle -F $_zhimmer_prompt_fd _zhimmer_prompt_ready
  return 0
}

_zhimmer_prompt_ready() {  # <fd>
  local fd=$1 line= gen= sym=
  read -r -u $fd line 2>/dev/null
  zle -F $fd 2>/dev/null
  { exec {fd}<&- } 2>/dev/null
  [[ $fd == $_zhimmer_prompt_fd ]] && _zhimmer_prompt_fd=

  [[ $line == *$'\t'* ]] || return 0
  gen=${line%%$'\t'*} sym=${line#*$'\t'}
  (( gen == _zhimmer_prompt_gen )) || return 0       # stale
  [[ $sym == $_zhimmer_prompt_git ]] && return 0     # unchanged: skip the redraw

  _zhimmer_prompt_git=$sym
  _zhimmer_prompt_build
  # A history menu open above the prompt lives in front of PROMPT, put there
  # by _zhimmer_zle_setprompt (zlemenu.zsh); the rebuild just dropped it.
  PROMPT=$_zhimmer_zprefix$PROMPT
  zle reset-prompt 2>/dev/null
  return 0
}

_zhimmer_prompt_precmd() {
  _zhimmer_prompt_ret=$?       # first: any command replaces $?
  local REPLY

  _zhimmer_prompt_git=
  _zhimmer_prompt_branch
  _zhimmer_prompt_br=$REPLY

  if [[ -z $_zhimmer_prompt_br ]]; then
    _zhimmer_prompt_cancel
  elif _zhimmer_bool prompt-async; then
    _zhimmer_prompt_start
  else
    _zhimmer_prompt_git_query
    _zhimmer_prompt_git=$REPLY
  fi

  _zhimmer_prompt_build
  return 0
}

typeset -g _zhimmer_prompt_on=0
typeset -g _zhimmer_prompt_saved=

zhimmer-prompt-on() {
  (( _zhimmer_prompt_on )) && return 0
  autoload -Uz add-zsh-hook
  _zhimmer_prompt_saved=$PROMPT
  add-zsh-hook precmd _zhimmer_prompt_precmd
  _zhimmer_prompt_on=1
  return 0
}

zhimmer-prompt-off() {
  (( _zhimmer_prompt_on )) || return 0
  add-zsh-hook -d precmd _zhimmer_prompt_precmd
  _zhimmer_prompt_cancel
  PROMPT=$_zhimmer_prompt_saved
  _zhimmer_prompt_on=0
  return 0
}
