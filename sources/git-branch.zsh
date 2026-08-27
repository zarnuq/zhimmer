# Local branches, for the git subcommands that take one.
#
# for-each-ref is a fork, and a source is asked on every keystroke: 1.4ms a key
# in a repository with a single branch, which is more than ranking ten thousand
# history entries costs. Branches only change when a command runs, so the list
# is read once per command line and per directory instead -- HISTCMD is the same
# guard the history cache uses, and it moves exactly when a `git switch` could
# have changed the answer.
typeset -g _zhimmer_git_at= _zhimmer_git_dir=
typeset -ga _zhimmer_git_heads=()

_zhimmer_git_load() {
  [[ $_zhimmer_git_at == $HISTCMD && $_zhimmer_git_dir == $PWD ]] && return
  _zhimmer_git_heads=(
    ${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)"} )
  _zhimmer_git_at=$HISTCMD _zhimmer_git_dir=$PWD
}

_zhimmer_source_git-branch() {
  # Past the subcommand, not on it: at `git branch` there is no branch argument
  # yet, and matching there asked for branches to replace the word `branch`.
  (( CURRENT > 2 )) || return
  [[ $words[1] == git && $words[2] == (checkout|switch|merge|rebase|branch) ]] || return
  local -i limit=$2
  _zhimmer_git_load
  # Cut to the limit like every other source. Without it a repository with a few
  # hundred branches put all of them in the menu, which has no row budget of its
  # own -- it scrolls, so nothing stopped them.
  local -a reply
  _zhimmer_pick $limit ${(M)_zhimmer_git_heads:#${(b)PREFIX}*} || return
  _zhimmer_addwords zhimmer-git-branch branch "$reply[@]"
}
