# Tab's matches, restyled. compsys still generates and inserts them; a shadowed
# `compadd` only re-issues each call with zhimmer's rows and header.

_zhimmer_compadd() {
  # Read the display strings (-d), description (-X/-x) and group (-J/-V);
  # the real compadd still gets "$@" verbatim. The probe drops -O/-A/-D, which
  # write somewhere: _describe's -D filtered twice and emptied git completion.
  local -a probe=()
  local dname= desc= group=
  local -i i=1
  while (( i <= $# )); do
    case $argv[i] in
      --)       probe+=( "${(@)argv[i,-1]}" ); break ;;
      -[OAD])   (( i += 2 )) ;;
      -[OAD]*)  (( i++ )) ;;
      -d)       : ${dname:=$argv[i+1]};        probe+=( "$argv[i]" "$argv[i+1]" ); (( i += 2 )) ;;
      -d*)      : ${dname:=${argv[i]#-d}};     probe+=( "$argv[i]" );              (( i++ )) ;;
      -[Xx])    : ${desc:=$argv[i+1]};         probe+=( "$argv[i]" "$argv[i+1]" ); (( i += 2 )) ;;
      -[Xx]*)   : ${desc:=${argv[i]#-[Xx]}};   probe+=( "$argv[i]" );              (( i++ )) ;;
      # Last wins: the inner tag (-J argument-rest -J globbed-files) says what
      # the matches are.
      -[JV])    group=$argv[i+1];        probe+=( "$argv[i]" "$argv[i+1]" ); (( i += 2 )) ;;
      -[JV]*)   group=${argv[i]#-[JV]};  probe+=( "$argv[i]" );              (( i++ )) ;;
      # Quoted: an empty `-p ''` would otherwise vanish and shift every option.
      *)        probe+=( "$argv[i]" ); (( i++ )) ;;
    esac
  done

  local -a ws=()
  builtin compadd -O ws "${(@)probe}" 2>/dev/null
  (( $#ws )) || { builtin compadd "$@"; return }

  # A completer's own display strings are kept, padded. compadd takes the
  # *first* of a repeated option, so ours go in front.
  local -a base=( ${dname:+"${(@P)dname}"} )
  (( $#base == $#ws )) || base=( "${(@)ws}" )
  local -a disp=()
  local c REPLY
  for c in $base; do _zhimmer_row "$c"; disp+=( "$REPLY" ); done

  # Strip a completer's prompt escapes and the dashes of `-default-`.
  local name=${desc:-${ZHIMMER_GROUP_LABELS[$group]:-${group//-/ }}}
  name=${${name//\%[BbSsUuf]/}//[<>]/}
  name=${${name#-}%-}
  _zhimmer_header "${name:-matches}"

  builtin compadd -l -d disp -X "$REPLY" "$@"
}

# For one completion only: zhimmer's own sources call compadd too.
_zhimmer_style_matches() {
  _zhimmer_bool style-completion || return 1
  functions[compadd]='_zhimmer_compadd "$@"'
}

_zhimmer_unstyle_matches() {
  unfunction compadd 2>/dev/null
  return 0
}

# Long listings: LISTMAX=0 asks "see all N?" only when the list would scroll,
# and `menu select` makes them selectable rather than a pager. Never overrides
# a style the user set, on any context pattern -- hence the whole `zstyle -L`.
#
# Deliberately not `menu select interactive`: complist draws an
# `interactive: []` row and drops the mode on every arrow.
_zhimmer_tame_lists() {
  _zhimmer_bool tame-lists || return
  LISTMAX=0

  local -A defined; local l; local -a w
  for l in ${(f)"$(zstyle -L)"}; do
    w=( ${(z)l} )
    [[ $w[2] == -* ]] && w=( $w[1] $w[3,-1] )   # zstyle -e '<context>' <style> ...
    [[ $w[2] == *completion* ]] && defined[$w[3]]=1
  done

  # Command-line form, split with (z) and unquoted with (Q): menu takes two
  # words, list-prompt one with spaces. Values are (q)-quoted, since the `;` in
  # the colour would otherwise end the command.
  local -a want=(
    "group-name ''"
    "list-prompt ${(q)ZHIMMER_LIST_PROMPT}"
    "select-prompt ${(q)ZHIMMER_SELECT_PROMPT}"
    "menu select"
    # Inside a completion ZLS_COLORS is rebuilt from this style.
    "list-colors ma=${(q)ZHIMMER_SELECT}"
  )

  typeset -ga ZHIMMER_TAMED=()      # what was set, for zhimmer-doctor
  local -a args; local entry
  for entry in $want; do
    args=( "${(@Q)${(z)entry}}" )
    (( ${+defined[$args[1]]} )) && continue
    zstyle ':completion:*' "${(@)args}"
    ZHIMMER_TAMED+=( $args[1] )
  done
}
