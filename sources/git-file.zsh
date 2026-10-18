# Changed files, for git subcommands that act on them. One `git status` fork
# per command line and directory.
typeset -g _zhimmer_gitfile_at=
typeset -ga _zhimmer_gitfile_paths=()

# Porcelain v1 in, paths out. A rename yields its new name; (Q) unquotes the
# paths git quotes.
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
  [[ $_zhimmer_gitfile_at == $HISTCMD:$PWD ]] && return
  local -a reply
  # Relative to $PWD, as the command line typed here needs.
  _zhimmer_git_status_paths "$(git status --porcelain 2>/dev/null)"
  _zhimmer_gitfile_paths=( $reply )
  _zhimmer_gitfile_at=$HISTCMD:$PWD
}

_zhimmer_source_git-file() {
  (( CURRENT > 2 )) || return
  [[ $words[1] == git ]] || return
  [[ $words[2] == (add|stage|restore|rm|diff|checkout|reset|stash) ]] || return
  local -i limit=$1
  _zhimmer_gitfile_load
  _zhimmer_addpicked zhimmer-git-file changed $limit _zhimmer_gitfile_paths
}
