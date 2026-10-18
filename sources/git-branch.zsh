# Branches and remotes, for the git subcommands that take one. One
# for-each-ref fork per command line and directory (keyed on $HISTCMD:$PWD).
typeset -g _zhimmer_git_at=
typeset -ga _zhimmer_git_heads=() _zhimmer_git_remotes=() _zhimmer_git_rbranches=()

# Full refnames in, three lists out. <remote>/HEAD is a symref, not a branch.
# Remote names come from the refs, not a second `git remote` fork.
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
  [[ $_zhimmer_git_at == $HISTCMD:$PWD ]] && return
  _zhimmer_git_refs \
    "$(git for-each-ref --format='%(refname)' refs/heads refs/remotes 2>/dev/null)"
  _zhimmer_git_at=$HISTCMD:$PWD
}

_zhimmer_source_git-branch() {
  # Past the subcommand: at `git branch` there is no branch argument yet.
  (( CURRENT > 2 )) || return
  [[ $words[1] == git ]] || return
  # Filtered before the fork, so `git commit` never pays for it.
  [[ $words[2] == (push|pull|fetch|merge|rebase|checkout|switch|branch) ]] || return
  local -i limit=$1
  local group=branch
  _zhimmer_git_load

  local -a cands=( $_zhimmer_git_heads )
  case $words[2] in
    # `git push <remote> <branch>...`: a branch in the remote's place fails
    # at the far end.
    push|pull|fetch) (( CURRENT == 3 )) && { group=remote; cands=( $_zhimmer_git_remotes ) } ;;
    merge|rebase)    cands+=( $_zhimmer_git_rbranches ) ;;
  esac

  _zhimmer_addpicked zhimmer-git-$group $group $limit cands
}
