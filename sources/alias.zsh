# Aliases. These live only in the shell's memory, so there is nothing on disk to
# read -- filtering a few dozen keys in zsh costs nothing.

_zhimmer_source_alias() {
  (( CURRENT == 1 )) || return
  # Nothing typed is not a query. An empty word matches every alias there is,
  # which put the whole table in the menu and a ghost of whichever one sorted
  # first on the line -- two spaces at an empty prompt was enough to do it. The
  # file source has always drawn this line for the same reason; the sources with
  # a command in front of them do not, because `git checkout ` has already said
  # what the list is of.
  [[ -n $PREFIX ]] || return
  local -i limit=$2
  # Sorted before the cut, not after: a hash has no order of its own, so cutting
  # first offered whichever ten the hash happened to hold first -- a different
  # ten in the next shell.
  local -a reply
  _zhimmer_pick $limit \
    ${(k)aliases[(I)${(b)PREFIX}*]} ${(k)galiases[(I)${(b)PREFIX}*]} || return

  # The match is the alias; the row says what it stands for.
  local -a rows=(); local n
  for n in $reply; do rows+=( "$n  →  ${aliases[$n]:-$galiases[$n]}" ); done

  _zhimmer_addwords zhimmer-alias alias "$reply[@]" -- "$rows[@]"
}
