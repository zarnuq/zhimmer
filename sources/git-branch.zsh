# Branches and remotes, for the git subcommands that take one.
#
# for-each-ref is a fork, and a source is asked on every keystroke: 1.4ms a key
# in a repository with a single branch, which is more than ranking ten thousand
# history entries costs. Refs only change when a command runs, so they are read
# once per command line and per directory instead -- HISTCMD is the same guard
# the history cache uses, and it moves exactly when a `git switch` could have
# changed the answer.
#
# One call covers both namespaces. Asking for heads and remotes separately
# would double the fork this whole arrangement exists to avoid.
typeset -g _zhimmer_git_at= _zhimmer_git_dir=
typeset -ga _zhimmer_git_heads=() _zhimmer_git_remotes=() _zhimmer_git_rbranches=()

# Full refnames in, three lists out. Kept apart from the fork so it can be
# tested against a fixture rather than against whatever repository the tests
# happen to run in.
#
# refs/remotes/<remote>/HEAD is a symbolic ref to the remote's default branch,
# not a branch of its own: offering it puts `origin/HEAD` in a menu next to the
# `origin/main` it stands for.
#
# Remote names come from the refs rather than from `git remote`, which would be
# a second fork on a path that exists to avoid the first one. The difference is
# a remote that has never been fetched from, which has no refs to be named by
# and so does not appear -- one missing row, on a remote that is one `git
# fetch` away from having them.
_zhimmer_git_refs() {  # <refname per line>
  _zhimmer_git_heads=() _zhimmer_git_remotes=() _zhimmer_git_rbranches=()
  local r rest
  local -A seen
  for r in ${(f)1}; do
    case $r in
      refs/heads/*)
        _zhimmer_git_heads+=( ${r#refs/heads/} ) ;;
      refs/remotes/*)
        rest=${r#refs/remotes/}
        [[ $rest == */HEAD ]] && continue
        [[ $rest == */* ]] || continue
        _zhimmer_git_rbranches+=( $rest )
        (( ${+seen[${rest%%/*}]} )) || _zhimmer_git_remotes+=( ${rest%%/*} )
        seen[${rest%%/*}]=1 ;;
    esac
  done
}

_zhimmer_git_load() {
  [[ $_zhimmer_git_at == $HISTCMD && $_zhimmer_git_dir == $PWD ]] && return
  _zhimmer_git_refs \
    "$(git for-each-ref --format='%(refname)' refs/heads refs/remotes 2>/dev/null)"
  _zhimmer_git_at=$HISTCMD _zhimmer_git_dir=$PWD
}

_zhimmer_source_git-branch() {
  # Past the subcommand, not on it: at `git branch` there is no branch argument
  # yet, and matching there asked for branches to replace the word `branch`.
  (( CURRENT > 2 )) || return
  [[ $words[1] == git ]] || return
  local -i limit=$1
  local group=branch

  # Decided before anything is read, so an unrelated subcommand costs nothing:
  # `git commit` never reaches the fork the cache above exists to avoid.
  case $words[2] in
    # `git push origin main` -- the first argument is the remote, and every
    # argument after it is a local branch. Offering branches in the remote's
    # place is the one that actually costs something: `git push main` is a
    # remote named main, and the error comes back from the far end.
    push|pull|fetch)         (( CURRENT == 3 )) && group=remote ;;
    merge|rebase)            ;;
    checkout|switch|branch)  ;;
    *) return ;;
  esac

  _zhimmer_git_load

  local -a cands=()
  case $words[2] in
    push|pull|fetch)
      if (( CURRENT == 3 )); then cands=( $_zhimmer_git_remotes )
      else                        cands=( $_zhimmer_git_heads ); fi ;;
    # `git merge origin/main` and `git rebase origin/main` are as common as the
    # local form, so the remote-tracking refs are offered here and nowhere else.
    merge|rebase)            cands=( $_zhimmer_git_heads $_zhimmer_git_rbranches ) ;;
    checkout|switch|branch)  cands=( $_zhimmer_git_heads ) ;;
  esac

  # Cut to the limit like every other source. Without it a repository with a few
  # hundred branches put all of them in the menu, which has no row budget of its
  # own -- it scrolls, so nothing stopped them.
  local -a reply
  _zhimmer_pick $limit ${(M)cands:#${(b)PREFIX}*} || return
  _zhimmer_addwords zhimmer-git-$group $group "$reply[@]"
}
