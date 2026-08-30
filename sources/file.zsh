# Files and directories, for argument positions.

_zhimmer_source_file() {
  # An empty current word would glob the whole directory into the menu.
  (( CURRENT > 1 )) && [[ -n $PREFIX ]] || return
  local -i limit=$1

  # `~` does not expand inside a parameter's value, so globbing $PREFIX directly
  # matched nothing at all for `~/Doc` -- every path under home came up empty
  # while the same path spelled out matched fine. The leading `~` component is
  # expanded here, and only that component is put back on the matches, so what
  # the menu inserts replaces the word as written rather than rewriting `~/` to
  # the full path.
  local tilde= home=
  if [[ $PREFIX == \~* ]]; then
    tilde=${PREFIX%%/*}     # `~`, or `~user`
    home=${~tilde}
  fi

  # ${~pat} makes the rest of the word a pattern, so a glob typed into it works
  # the way it does everywhere else in the shell: `ls ./z*` lists what it
  # matches. The trailing `*` is only added when the word does not already end
  # in one -- appending it blindly spells `**`, which is zsh's recursive-descent
  # operator and matches nothing without a `/` after it, so `./z*` came back
  # empty.
  local pat=${home}${PREFIX:${#tilde}}
  [[ $pat == *\* ]] || pat=$pat\*
  local -a m=( ${~pat}(N) )
  (( $#m )) || return
  m=( "${(@)m[1,limit]}" )

  # Only the `~` is swapped back. The rest of each row is the match itself, not
  # the typed word plus a tail: with a glob in the word the two are not the same
  # string, and reconstructing from the typed form gave rows like
  # `./z*./zalpha`. A `~` expands to a plain path with nothing pattern-like in
  # it, which is what makes this one strip safe to write as a literal.
  [[ -n $tilde ]] && m=( ${tilde}${^m#"$home"} )

  _zhimmer_addwords zhimmer-file file "${(@)m}"
}
