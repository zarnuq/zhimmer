# Targets from the Makefile in the current directory.
#
# Read as text rather than asked of make: `make -pn` runs the makefile's own
# shell assignments to build its database, which is a fork and a side effect
# for something being asked on every keystroke. A first-column `name:` is what
# a target looks like, and that is nearly all of what anyone types.
#
# Re-read when the file's mtime moves, which is the same free check the ssh
# source uses; without zsh/stat the stamp stays empty and the file is read once
# per directory.
zmodload -F zsh/stat b:zstat 2>/dev/null

typeset -g _zhimmer_make_at= _zhimmer_make_dir=
typeset -ga _zhimmer_make_targets_c=()

# A target line starts in the first column and has a `:` before any `=`. The
# order of that test is what separates `target: dep` from `VAR := value`, and
# `.PHONY`, `%.o` and anything holding a `$` are rules and patterns rather than
# names to type.
_zhimmer_make_targets() {  # <makefile text>  -> reply
  typeset -ga reply=()
  local l head t
  local -A seen
  for l in ${(f)1}; do
    [[ -z $l || $l == [[:space:]]* || $l == \#* ]] && continue
    [[ $l == *:* ]] || continue
    head=${l%%:*}
    # `VAR := x`, `VAR ::= x` and `VAR ?= x` all put the = before the colon or
    # immediately after it; a real target has neither.
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
  local -a st
  local stamp=
  [[ -n $found ]] && zstat -A st +mtime $found 2>/dev/null && stamp=$st[1]
  [[ $_zhimmer_make_at == "$found:$stamp" && $_zhimmer_make_dir == $PWD ]] && return
  _zhimmer_make_at="$found:$stamp" _zhimmer_make_dir=$PWD

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
  local -a reply
  _zhimmer_pick $limit ${(M)_zhimmer_make_targets_c:#${(b)PREFIX}*} || return
  _zhimmer_addwords zhimmer-make target "$reply[@]"
}
