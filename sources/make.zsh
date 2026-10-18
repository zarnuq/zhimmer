# Makefile targets, read as text (`make -pn` forks and runs the makefile's own
# shell assignments). Re-read when the mtime moves.
typeset -g _zhimmer_make_at=
typeset -ga _zhimmer_make_targets_c=()

# First column, `:` before any `=` (so not `VAR := x`). `.PHONY`, `%.o` and
# anything with `$` are rules or patterns, not names to type.
_zhimmer_make_targets() {  # <makefile text>  -> reply
  typeset -ga reply=()
  local l head t
  local -A seen
  for l in ${(f)1}; do
    [[ -z $l || $l == [[:space:]]* || $l == \#* ]] && continue
    [[ $l == *:* ]] || continue
    head=${l%%:*}
    [[ $head == *=* || $l == *:=* ]] && continue
    for t in ${(z)head}; do
      [[ $t == *[%\$\(\)]* ]] && continue
      [[ $t == .* ]] && continue
      (( ${+seen[$t]} )) && continue
      seen[$t]=1
      reply+=( $t )
    done
  done
  (( $#reply ))
}

_zhimmer_make_load() {
  local f found=
  for f in Makefile makefile GNUmakefile; do
    [[ -r $f ]] && { found=$f; break }
  done
  local REPLY
  _zhimmer_mtime $found
  [[ $_zhimmer_make_at == "$found:$REPLY:$PWD" ]] && return
  _zhimmer_make_at="$found:$REPLY:$PWD"

  local -a reply
  if [[ -n $found ]] && _zhimmer_make_targets "$(<$found)"; then
    _zhimmer_make_targets_c=( $reply )
  else
    _zhimmer_make_targets_c=()
  fi
}

_zhimmer_source_make() {
  (( CURRENT > 1 )) || return
  [[ $words[1] == (make|gmake) ]] || return
  local -i limit=$1
  _zhimmer_make_load
  _zhimmer_addpicked zhimmer-make target $limit _zhimmer_make_targets_c
}
