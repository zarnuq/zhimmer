# Executables on $PATH, from zsh's $commands hash.

_zhimmer_source_command() {
  (( CURRENT == 1 )) || return
  [[ -n $PREFIX ]] || return
  local -i limit=$1
  local -a reply
  # (I) filters inside the hash. (b) is required: an unquoted `[` in the
  # subscript makes it read out values instead of keys.
  _zhimmer_pick $limit ${(k)commands[(I)${(b)PREFIX}*]} || return
  _zhimmer_addwords zhimmer-command command "$reply[@]"
}
