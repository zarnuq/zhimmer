# zoxide's directory database, for cd-like commands.
#
# `zoxide query -l` is a fork -- 4.4ms measured, twice what ranking ten thousand
# history entries costs -- and a source is asked on every keystroke. The
# database only changes when a directory is visited, which is a command, so it
# is read once per command line, the same guard the history cache uses.
typeset -g _zhimmer_zoxide_at=
typeset -ga _zhimmer_zoxide_dirs=()

_zhimmer_zoxide_load() {
  [[ $_zhimmer_zoxide_at == $HISTCMD ]] && return
  _zhimmer_zoxide_dirs=( ${(f)"$(zoxide query -l 2>/dev/null)"} )
  _zhimmer_zoxide_at=$HISTCMD
}

_zhimmer_source_zoxide() {
  # Not while the command word itself is still being typed: `z` and `cd` are
  # each a whole word, so word 1 matching is not the same as there being an
  # argument to complete.
  (( CURRENT > 1 )) || return
  [[ $words[1] == (cd|z) ]] && (( $+commands[zoxide] )) || return
  local -i limit=$2
  _zhimmer_zoxide_load
  # Matched anywhere in the path, which is the point of zoxide: `z hmr` finds
  # ~/src/zhimmer. (b) quotes the query into a literal, the same way the history
  # matcher does -- a path typed at the prompt is text, and the plugin does not
  # leave it to chance which characters in it the shell decides are operators.
  #
  # Cut without sorting: this list arrives ranked by frecency, and that ranking
  # is the whole reason to ask zoxide rather than glob the filesystem.
  local -a d=( ${(M)_zhimmer_zoxide_dirs:#*${(b)PREFIX}*} )
  (( $#d )) || return
  _zhimmer_addwords zhimmer-zoxide zoxide "${(@)d[1,limit]}"
}
