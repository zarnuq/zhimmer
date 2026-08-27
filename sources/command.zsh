# Executables on $PATH. $commands is a hash zsh maintains itself.

_zhimmer_source_command() {
  (( CURRENT == 1 )) || return
  local -i limit=$2
  local -a reply
  # Filtered inside the hash with (I) rather than by materialising every key
  # first: a normal $PATH puts a few thousand of them there. (b) quotes what was
  # typed into a literal pattern -- an unquoted `[` in the subscript is not just
  # a character class, it makes the subscript read out values instead of keys.
  _zhimmer_pick $limit ${(k)commands[(I)${(b)PREFIX}*]} || return
  _zhimmer_addwords zhimmer-command command "$reply[@]"
}
