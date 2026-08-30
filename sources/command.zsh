# Executables on $PATH. $commands is a hash zsh maintains itself.

_zhimmer_source_command() {
  (( CURRENT == 1 )) || return
  # As in the alias source: an empty word matches every executable on $PATH,
  # and ten of those in alphabetical order is not a suggestion.
  [[ -n $PREFIX ]] || return
  local -i limit=$1
  local -a reply
  # Filtered inside the hash with (I) rather than by materialising every key
  # first: a normal $PATH puts a few thousand of them there. (b) quotes what was
  # typed into a literal pattern -- an unquoted `[` in the subscript is not just
  # a character class, it makes the subscript read out values instead of keys.
  _zhimmer_pick $limit ${(k)commands[(I)${(b)PREFIX}*]} || return
  _zhimmer_addwords zhimmer-command command "$reply[@]"
}
