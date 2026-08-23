# Aliases. These live only in the shell's memory, so there is nothing for the
# matcher binary to read -- filtering a few dozen keys in zsh is cheaper than a
# fork anyway.

_zhimmer_source_alias() {
  (( CURRENT == 1 )) || return
  local -a names disp; local REPLY
  names=( ${(k)aliases[(I)${PREFIX}*]} ${(k)galiases[(I)${PREFIX}*]} )
  (( $#names )) || return
  local n
  for n in $names; do
    _zhimmer_row "$n  →  ${aliases[$n]:-${galiases[$n]}}"; disp+=( "$REPLY" )
  done
  _zhimmer_header alias; compadd -l -V zhimmer-alias -X "$REPLY" -d disp -- $names
}
