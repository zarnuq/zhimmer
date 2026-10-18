# Aliases, from the shell's own tables.

_zhimmer_source_alias() {
  (( CURRENT == 1 )) || return
  # An empty word matches every alias, and two spaces would ghost the first.
  [[ -n $PREFIX ]] || return
  local -i limit=$1
  local -a reply
  _zhimmer_pick $limit \
    ${(k)aliases[(I)${(b)PREFIX}*]} ${(k)galiases[(I)${(b)PREFIX}*]} || return

  local -a rows=(); local n
  for n in $reply; do rows+=( "$n  →  ${aliases[$n]:-$galiases[$n]}" ); done

  _zhimmer_addwords zhimmer-alias alias "$reply[@]" -- "$rows[@]"
}
