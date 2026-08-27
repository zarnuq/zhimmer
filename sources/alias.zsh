# Aliases. These live only in the shell's memory, so there is nothing for the
# matcher binary to read -- filtering a few dozen keys in zsh is cheaper than a
# fork anyway.

_zhimmer_source_alias() {
  (( CURRENT == 1 )) || return
  local -i limit=$2
  local -a names=( ${(k)aliases[(I)${PREFIX}*]} ${(k)galiases[(I)${PREFIX}*]} )
  (( $#names )) || return
  names=( ${names[1,limit]} )

  # The match is the alias; the row says what it stands for.
  local -a rows=(); local n
  for n in $names; do rows+=( "$n  →  ${aliases[$n]:-${galiases[$n]}}" ); done

  _zhimmer_addwords zhimmer-alias alias $names -- $rows
}
