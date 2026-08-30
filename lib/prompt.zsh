# An optional prompt, off unless asked for.
#
# Two tiers, split by what they cost. Everything that can be known without a
# fork -- the directory, the branch, the last command's exit status -- is drawn
# immediately. The one thing that cannot be, the working-tree status, is fetched
# in the background and the prompt redraws when it lands. So the prompt appears
# at the same speed everywhere, and a slow repository delays a few symbols
# rather than the shell.
#
# That split is the whole design. `git status` is not slow in the abstract: it
# is 1.5ms in a small repository and 67ms in one with 94,000 tracked files, and
# a prompt that blocks on it is fine right up until the day it is not. Pure
# reaches the same conclusion and pays for zsh-async to get there; this needs
# one file descriptor and a `zle -F` handler, because it has exactly one job to
# run rather than a general scheduler to offer.
#
# The branch does not need git at all. `.git/HEAD` is a line of text naming the
# ref, and reading it is 0.01ms against 16.75ms for vcs_info and 1.0ms for a
# `git symbolic-ref` fork. Almost every prompt in the wild pays one of the
# latter two for an answer sitting in a file.
#
# Off by default, and it saves and restores whatever prompt it found, so a user
# on Pure or starship can load zhimmer without this touching anything.

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

# Catppuccin Mocha, the same palette as the completion menu (see theme.zsh) and
# the same assignments the author's Pure configuration used, so switching over
# does not change what any colour means.
typeset -gA ZHIMMER_PROMPT_COLORS=(
  path    '#89b4fa'
  branch  '#cba6f7'
  status  '#f9e2af'
  arrows  '#fab387'
  ok      '#a6e3a1'
  error   '#f38ba8'
)

# Which order the symbols come out in. Spaceship builds its string by
# prepending, so this is the order that one actually renders in; kept because
# it is what the eye is already trained on rather than because it is better.
typeset -ga ZHIMMER_PROMPT_ORDER=(
  unmerged deleted renamed modified staged untracked
)

typeset -g ZHIMMER_PROMPT_SYMBOL=' >'

# ---------------------------------------------------------------------------
# The branch, without forking
# ---------------------------------------------------------------------------

# Walk up for the .git of the repository $PWD is in. A plain directory in the
# ordinary case; a *file* holding `gitdir: <path>` in a linked worktree or a
# submodule, which is the case every hand-rolled version of this forgets.
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
      # A relative gitdir is relative to the file that names it.
      [[ $REPLY == /* ]] || REPLY=$d/$REPLY
      return 0
    fi
    [[ -z $d || $d == / ]] && break
    d=${d%/*}
    [[ -z $d ]] && d=/
  done
  return 1
}

# HEAD is `ref: refs/heads/<name>` on a branch and a bare sha when detached.
#
# The name is taken by stripping the prefix, never with ${head##*/}: a branch
# called `feat/menu` is `refs/heads/feat/menu`, and the greedy strip returns
# `menu` -- the wrong branch, silently, and only on the branches whose names
# say the most.
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
    REPLY=${head[1,7]}          # detached: the short sha, as git would show it
  fi
  [[ -n $REPLY ]]
}

# ---------------------------------------------------------------------------
# The symbols
# ---------------------------------------------------------------------------

# Porcelain v1 text in, symbol string out. A pure function of its argument, so
# it is tested against fixtures in test/unit.zsh rather than against whatever
# repository the tests happen to run in -- the same split every file-reading
# source in this plugin uses.
#
# The status codes are two columns: X is the index, Y is the working tree. The
# combinations below are Spaceship's, which is where these symbols come from,
# and are matched by indexing the two characters rather than by pattern. The
# patterns would need a space inside a bracket expression, which is exactly the
# kind of quoting that goes wrong quietly.
#
# Each test stands on its own rather than in an if/elif chain: one line can be
# both staged and modified (`MM`), and the prompt should say so.
_zhimmer_prompt_symbols() {  # <git status --porcelain=v1 --branch text> -> REPLY
  local -A f
  local l x y k
  local ahead= behind=
  REPLY=

  for l in ${(f)1}; do
    if [[ $l == '## '* ]]; then
      # `## main...origin/main [ahead 1, behind 2]`. Absent when there is no
      # upstream, which is not the same as being in step with one.
      [[ $l == *'[ahead '* ]] && { ahead=${l#*\[ahead }; ahead=${ahead%%[,\]]*} }
      [[ $l == *'behind '* ]] && { behind=${l#*behind }; behind=${behind%%[,\]]*} }
      continue
    fi
    (( ${#l} > 2 )) || continue
    x=${l[1]} y=${l[2]}

    if [[ $x == '?' && $y == '?' ]]; then f[untracked]=1; continue; fi
    [[ $x == '!' && $y == '!' ]] && continue          # ignored, only with --ignored

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

  # Counts, not just arrows: `⇡3` answers "should I push?" where `⇡` only says
  # that the question exists. Divergence is both arrows rather than a `⇕` of its
  # own, which says the same thing and drops the two numbers to do it.
  [[ -n $ahead  ]] && (( ahead ))  && REPLY+=${ZHIMMER_PROMPT_SYMBOLS[ahead]}$ahead
  [[ -n $behind ]] && (( behind )) && REPLY+=${ZHIMMER_PROMPT_SYMBOLS[behind]}$behind
  [[ -n $REPLY ]]
}

# One fork, and it answers everything: branch, upstream distance, and every
# status column. Pure spends five forks and 89ms on the same question, most of
# it because vcs_info is asked for the branch separately.
#
# GIT_OPTIONAL_LOCKS=0 stops the read from taking the index lock to refresh it,
# which is what makes a prompt's `git status` fight a `git commit` in another
# pane of the same repository.
_zhimmer_prompt_git_query() {  # -> REPLY
  REPLY=
  _zhimmer_prompt_symbols \
    "$(GIT_OPTIONAL_LOCKS=0 command git status --porcelain=v1 --branch 2>/dev/null)"
}

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

typeset -g _zhimmer_prompt_ret=0
typeset -g _zhimmer_prompt_br=
typeset -g _zhimmer_prompt_git=

# The exit status is baked into the string rather than left to `%(?..)`. The
# async half redraws the prompt with `zle reset-prompt` well after the command
# finished, and `$?` at that point is whatever the redraw itself last did -- so
# a conditional prompt escape would report success on a line that failed.
#
# The branch is escaped because a `%` in it is a prompt escape: a branch named
# `feat/100%done` would otherwise be read as a format specifier and print
# something else entirely, or nothing.
_zhimmer_prompt_build() {
  local -A c=( "${(@kv)ZHIMMER_PROMPT_COLORS}" )
  local line=" %F{$c[path]}%~%f"
  [[ -n $_zhimmer_prompt_br ]]  && line+=" %F{$c[branch]}${_zhimmer_prompt_br//\%/%%}%f"
  [[ -n $_zhimmer_prompt_git ]] && line+=" %F{$c[status]}${_zhimmer_prompt_git}%f"
  local col=$c[ok]
  (( _zhimmer_prompt_ret )) && col=$c[error]
  PROMPT="$line"$'\n'"%F{$col}${ZHIMMER_PROMPT_SYMBOL}%f "
}

# ---------------------------------------------------------------------------
# The background half
# ---------------------------------------------------------------------------

typeset -g _zhimmer_prompt_fd=
typeset -gi _zhimmer_prompt_gen=0

_zhimmer_prompt_cancel() {
  [[ -n $_zhimmer_prompt_fd ]] || return 0
  zle -F $_zhimmer_prompt_fd 2>/dev/null
  exec {_zhimmer_prompt_fd}<&- 2>/dev/null
  _zhimmer_prompt_fd=
  return 0
}

# The child runs git *and* parses it, and prints one short line. That is what
# makes the read on this end safe: a few bytes go out in a single write, which
# is atomic under PIPE_BUF, so one `read` gets the whole answer. Handing back
# the raw status of a large repository instead would arrive in chunks and need
# a reassembly buffer for no gain -- the prompt wants six characters of it.
#
# The generation number rides along so a result that arrives after a `cd` is
# recognised as describing the directory you have left, and dropped.
_zhimmer_prompt_start() {
  _zhimmer_prompt_cancel
  # no_monitor/no_notify: without them the job control machinery announces the
  # background process, printing `[1] 12345` over the prompt it is drawing.
  setopt localoptions nomonitor nonotify
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
  exec {fd}<&- 2>/dev/null
  [[ $fd == $_zhimmer_prompt_fd ]] && _zhimmer_prompt_fd=

  [[ $line == *$'\t'* ]] || return 0
  gen=${line%%$'\t'*} sym=${line#*$'\t'}
  # A result for a directory that is no longer the one on screen.
  (( gen == _zhimmer_prompt_gen )) || return 0
  # Redrawing costs a full prompt render, so it is worth asking whether the
  # answer changed at all: on a clean tree, every prompt would otherwise redraw
  # itself once for no visible difference.
  [[ $sym == $_zhimmer_prompt_git ]] && return 0

  _zhimmer_prompt_git=$sym
  _zhimmer_prompt_build
  zle reset-prompt 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------------
# Hooks and the switch
# ---------------------------------------------------------------------------

# $? has to be the first thing read: any command here, including a test,
# replaces it.
_zhimmer_prompt_precmd() {
  _zhimmer_prompt_ret=$?
  local REPLY

  _zhimmer_prompt_git=
  if _zhimmer_prompt_branch; then
    _zhimmer_prompt_br=$REPLY
  else
    _zhimmer_prompt_br=
  fi

  # Drawn now, with whatever costs nothing. The symbols land later, or -- in a
  # small repository, where the child finishes before the line editor starts --
  # so soon after that there is nothing to see.
  _zhimmer_prompt_build

  if [[ -n $_zhimmer_prompt_br ]]; then
    if _zhimmer_bool prompt-async; then
      _zhimmer_prompt_start
    else
      _zhimmer_prompt_git_query
      _zhimmer_prompt_git=$REPLY
      _zhimmer_prompt_build
    fi
  else
    _zhimmer_prompt_cancel
  fi
  return 0
}

typeset -g _zhimmer_prompt_on=0
typeset -g _zhimmer_prompt_saved=

# Saving and restoring the prompt rather than just setting one: this is a
# plugin that people load for its completion menu, and taking their prompt
# permanently in the process is not a trade any of them agreed to.
zhimmer-prompt-on() {
  (( _zhimmer_prompt_on )) && return 0
  autoload -Uz add-zsh-hook
  typeset -g _zhimmer_prompt_saved=$PROMPT
  add-zsh-hook precmd _zhimmer_prompt_precmd
  _zhimmer_prompt_on=1
  return 0
}

zhimmer-prompt-off() {
  (( _zhimmer_prompt_on )) || return 0
  autoload -Uz add-zsh-hook
  add-zsh-hook -d precmd _zhimmer_prompt_precmd
  _zhimmer_prompt_cancel
  PROMPT=$_zhimmer_prompt_saved
  _zhimmer_prompt_on=0
  return 0
}
