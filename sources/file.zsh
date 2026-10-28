# Files and directories, for argument positions.

_zhimmer_source_file() {
  # An empty word would glob the whole directory into the menu.
  (( CURRENT > 1 )) && [[ -n $PREFIX ]] || return
  local -i limit=$1

  # `~` does not expand inside a parameter: expand the leading component here
  # and put only that back on the matches.
  local tilde= home=
  if [[ $PREFIX == \~* ]]; then
    tilde=${PREFIX%%/*}     # `~`, or `~user`
    home=${~tilde}
  fi

  # The word is a pattern, so a typed glob works. `*` is only appended when
  # absent (`**` is recursive descent). A word that is not a valid pattern
  # (`http://[IP`) comes back unexpanded under NO_BAD_PATTERN, and is retried
  # as a literal.
  # NO_EQUALS: a leading `=` (`emerge =cat/pkg-1.0`) is otherwise a command
  # lookup, and a miss is a hard "not found" error at the prompt.
  setopt localoptions nobadpattern noequals
  local word=${home}${PREFIX:${#tilde}} pat
  [[ $word == *\* ]] && pat=$word || pat=$word\*
  local -a m=( ${~pat}(N) )
  [[ $m == "$pat(N)" ]] && m=( ${~${(b)word}}*(N) )
  (( $#m )) || return
  m=( "${(@)m[1,limit]}" )

  [[ -n $tilde ]] && m=( ${tilde}${^m#"$home"} )

  _zhimmer_addwords zhimmer-file file "${(@)m}"
}
