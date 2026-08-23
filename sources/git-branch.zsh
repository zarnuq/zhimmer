# Local branches, for the git subcommands that take one.

_zhimmer_source_git-branch() {
  [[ $words[1] == git && $words[2] == (checkout|switch|merge|rebase|branch) ]] || return
  local -a b=( ${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)"} )
  _zhimmer_addwords zhimmer-git-branch branch ${(M)b:#${PREFIX}*}
}
