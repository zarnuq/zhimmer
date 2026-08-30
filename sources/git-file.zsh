# The files git already knows have changed, for the subcommands that act on
# them. `git add <Tab>` completes every path in the directory; what is wanted
# there is almost always one of the handful that is actually modified.
#
# Cached per command line and per directory like the branch source, and for the
# same reason -- this is a fork, and a source is asked on every keystroke. The
# working tree does change under a command, which is exactly what HISTCMD moves
# on.
typeset -g _zhimmer_gitfile_at= _zhimmer_gitfile_dir=
typeset -ga _zhimmer_gitfile_paths=()

# Porcelain v1 in, paths out. Two columns of status, a space, then the path;
# a rename is written `R  old -> new`, and it is the new name that exists on
# disk to be acted on. A path with a space or a quote in it comes back quoted
# by git, and (Q) takes that back off rather than leaving a row with literal
# quotes in it that no command would match.
_zhimmer_git_status_paths() {  # <git status --porcelain text>  -> reply
  typeset -ga reply=()
  local l p
  for l in ${(f)1}; do
    (( ${#l} > 3 )) || continue
    p=${l[4,-1]}
    [[ $p == *' -> '* ]] && p=${p#* -> }
    [[ -n $p ]] && reply+=( ${(Q)p} )
  done
  (( $#reply ))
}

_zhimmer_gitfile_load() {
  [[ $_zhimmer_gitfile_at == $HISTCMD && $_zhimmer_gitfile_dir == $PWD ]] && return
  local -a reply
  # Relative to the current directory, not the repository root: the path is
  # going into a command line typed here, and `../` prefixes on everything are
  # what a root-relative list would give.
  if _zhimmer_git_status_paths "$(git status --porcelain 2>/dev/null)"; then
    _zhimmer_gitfile_paths=( $reply )
  else
    _zhimmer_gitfile_paths=()
  fi
  _zhimmer_gitfile_at=$HISTCMD _zhimmer_gitfile_dir=$PWD
}

_zhimmer_source_git-file() {
  (( CURRENT > 2 )) || return
  [[ $words[1] == git ]] || return
  [[ $words[2] == (add|stage|restore|rm|diff|checkout|reset|stash) ]] || return
  local -i limit=$1
  _zhimmer_gitfile_load
  local -a reply
  _zhimmer_pick $limit ${(M)_zhimmer_gitfile_paths:#${(b)PREFIX}*} || return
  _zhimmer_addwords zhimmer-git-file changed "$reply[@]"
}
