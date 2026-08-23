# Files and directories, for argument positions.

_zhimmer_source_file() {
  # An empty current word would glob the whole directory into the menu.
  (( CURRENT > 1 )) && [[ -n $PREFIX ]] || return
  local -i limit=$2
  local -a m=( ${PREFIX}*(N) )
  _zhimmer_addwords zhimmer-file file ${m[1,limit]}
}
