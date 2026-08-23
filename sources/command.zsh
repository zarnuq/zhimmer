# Executables on $PATH. $commands is a hash zsh maintains itself.

_zhimmer_source_command() {
  (( CURRENT == 1 )) || return
  local -i limit=$2
  local -a names=( ${(k)commands[(I)${PREFIX}*]} )
  _zhimmer_addwords zhimmer-command command ${(o)names[1,limit]}
}
