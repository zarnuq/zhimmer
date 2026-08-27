# Files and directories, for argument positions.

_zhimmer_source_file() {
  # An empty current word would glob the whole directory into the menu.
  (( CURRENT > 1 )) && [[ -n $PREFIX ]] || return
  local -i limit=$2

  # `~` does not expand inside a parameter's value, so globbing $PREFIX directly
  # matched nothing at all for `~/Doc` -- every path under home came up empty
  # while the same path spelled out matched fine. ${~PREFIX} expands it, and the
  # typed form is put back on each match afterwards, so what the menu inserts
  # replaces the word as written rather than rewriting `~/` to the full path.
  local pat=${~PREFIX}
  local -a m=( ${pat}*(N) )
  (( $#m )) || return
  m=( ${m[1,limit]} )

  _zhimmer_addwords zhimmer-file file ${PREFIX}${^m#"$pat"}
}
