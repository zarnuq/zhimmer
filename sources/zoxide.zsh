# zoxide's directory database, for cd-like commands.

_zhimmer_source_zoxide() {
  [[ $words[1] == (cd|z) ]] && (( $+commands[zoxide] )) || return
  local -i limit=$2
  local -a d=( ${(f)"$(zoxide query -l 2>/dev/null)"} )
  _zhimmer_addwords zhimmer-zoxide zoxide ${${(M)d:#*${PREFIX}*}[1,limit]}
}
