# zoxide's directories, for cd/z. One `zoxide query` fork per command line.
typeset -g _zhimmer_zoxide_at=
typeset -ga _zhimmer_zoxide_dirs=()

_zhimmer_zoxide_load() {
  [[ $_zhimmer_zoxide_at == $HISTCMD ]] && return
  _zhimmer_zoxide_dirs=( ${(f)"$(zoxide query -l 2>/dev/null)"} )
  _zhimmer_zoxide_at=$HISTCMD
}

_zhimmer_source_zoxide() {
  (( CURRENT > 1 )) || return
  [[ $words[1] == (cd|z) ]] && (( $+commands[zoxide] )) || return
  local -i limit=$1
  _zhimmer_zoxide_load
  # Matched anywhere in the path, (b)-quoted; cut without sorting, since the
  # list arrives in zoxide's frecency order.
  local -a d=( ${(M)_zhimmer_zoxide_dirs:#*${~${(b)PREFIX}}*} )
  (( $#d )) || return
  _zhimmer_addwords zhimmer-zoxide zoxide "${(@)d[1,limit]}"
}
