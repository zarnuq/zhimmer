# Tab's matches, drawn by zhimmer instead of by complist's default columns.
#
# The matches still come from the completion system -- every completer, matcher,
# suffix and quoting rule intact. Only the call that adds them is intercepted
# and re-issued with zhimmer's display strings: one row per line, padded to the
# full width, under the same header and rule the history and file groups use.
# What Tab inserts is untouched; a shadowed `compadd` changes how it looks, not
# what it is.
#
# The alternative -- generating the matches ourselves -- means reimplementing
# compsys, which is where comparable tools go to die.

_zhimmer_compadd() {
  # Three things are read out of the call, and nothing is removed from it: the
  # display strings a completer supplies, its description, and its group name.
  # The real compadd below is passed "$@" verbatim, so a misread here costs a
  # row its label and never changes what Tab inserts.
  #
  # The probe is the exception -- it must not carry the options that write
  # somewhere. -D filters the caller's array in place, -A and -O store into
  # one; _describe passes -D and keeps its descriptions in that array, so
  # probing with it ran the filter twice and left git completion with nothing.
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
      # Last, not first: a call carries the outer tag before the inner one
      # (-J argument-rest -J globbed-files), and the inner one is the one that
      # says what these matches actually are.
      -[JV])    group=$argv[i+1];        probe+=( "$argv[i]" "$argv[i+1]" ); (( i += 2 )) ;;
      -[JV]*)   group=${argv[i]#-[JV]};  probe+=( "$argv[i]" );              (( i++ )) ;;
      # Quoted: `-p '' -s '' -W ''` is what _path_files sends, and an unquoted
      # empty element vanishes from the array, shifting every option after it
      # onto the wrong value and turning the rest of the call into matches.
      *)        probe+=( "$argv[i]" ); (( i++ )) ;;
    esac
  done

  # What this call would add. -O collects without adding, so the call below is
  # still the one that decides what Tab inserts.
  local -a ws=()
  builtin compadd -O ws "${(@)probe}" 2>/dev/null
  (( $#ws )) || { builtin compadd "$@"; return }

  # A completer that supplies display strings has something to say -- a flag's
  # meaning, a branch's last commit -- so those stay, padded rather than
  # replaced. compadd takes the *first* of a repeated option, so zhimmer's own
  # -d and -X have to go in front to win, which means carrying that text over
  # rather than dropping it.
  local -a base=( ${dname:+"${(@P)dname}"} )
  (( $#base == $#ws )) || base=( "${(@)ws}" )
  local -a disp=()
  local c REPLY
  for c in $base; do _zhimmer_row "$c"; disp+=( "$REPLY" ); done

  # zsh's own group names read as labels once group-name is set -- files,
  # options, commands -- and a description, when there is one, says more.
  local name=${desc:-${ZHIMMER_GROUP_LABELS[$group]:-${group//-/ }}}
  # A completer's -X is prompt-escaped text ("%Bcompleting %bfile"), and zsh's
  # own catch-all tag is spelled -default-; strip the escapes, and the dashes.
  name=${${name//\%[BbSsUuf]/}//[<>]/}
  name=${${name#-}%-}
  _zhimmer_header "${name:-matches}"

  builtin compadd -l -d disp -X "$REPLY" "$@"
}

# Installed only for the duration of one completion: zhimmer's own sources call
# compadd too, and they are already drawing their own rows.
_zhimmer_style_matches() {
  _zhimmer_bool style-completion || return 1
  functions[compadd]='_zhimmer_compadd "$@"'
}

_zhimmer_unstyle_matches() {
  unfunction compadd 2>/dev/null
  return 0
}

# Long completion listings, and what a listing is for. Two separate things go
# wrong once a list outgrows the screen. Past LISTMAX zsh replaces it with a
# question -- "do you wish to see all 149 possibilities?" -- so the same key
# that draws a list here draws a yes/no prompt there. LISTMAX=0 asks only when
# the list would scroll off the top, and a list-prompt makes that case scroll
# rather than ask.
#
# But that scroll is a pager: it pages past the matches, one keypress at a
# time, with nothing selected and nothing to accept -- the wrong gesture for
# `ls /etc/<Tab>`, where the point is to pick one of the 150 names rather than
# read past them. `menu select` hands the matches to menu selection instead, so
# the arrows walk the list, it scrolls under them, and the row the cursor is on
# is marked -- the same menu Down opens, reached from Tab.
#
# Plain `select`, not `select=long`: a short list fits on screen, but fitting is
# not the same as having nothing to choose from. With selection only on the long
# ones, Tab stepped through a short list by inserting each match with nothing on
# screen saying which row that was. The list-prompt stays for the widgets that
# only ever list (^D), where there is nothing to select into.
#
# A style the user has already set always wins, so the whole zstyle table is
# read once and asked what it defines. `zstyle -L <context> <style>` would
# answer for one context pattern only, and a value set on ':completion:*:*:*:*:*'
# -- which several frameworks ship -- has to count too.
_zhimmer_tame_lists() {
  _zhimmer_bool tame-lists || return
  LISTMAX=0

  local -A defined; local l; local -a w
  for l in ${(f)"$(zstyle -L)"}; do
    w=( ${(z)l} )
    [[ $w[2] == -* ]] && w=( $w[1] $w[3,-1] )   # zstyle -e '<context>' <style> ...
    [[ $w[2] == *completion* ]] && defined[$w[3]]=1
  done

  # Each entry is a style and its values written as a command line, because they
  # are not all one value each: menu takes two and they have to stay separate
  # words -- _main_complete matches its array element by element, so
  # 'select interactive' as a single value is neither of them -- while
  # list-prompt is one value with spaces inside it. (z) splits the line the way
  # the shell would, and (Q) takes the quoting back off.
  #
  # Which means every value interpolated in has to be quoted with (q) on the
  # way, spaces or not: the colour is 'ma=48;2;69;71;90;1', and a bare ; is
  # where the shell would end a command, so unquoted it split into six values
  # and the selected row lost its colour.
  # Deliberately not `menu select interactive`. Interactive mode is what makes
  # typing at an open menu narrow it, and zhimmer's own drop-down does that
  # natively -- but complist draws a hardcoded `interactive: []` row for the
  # whole time the mode is on, and drops out of the mode on every movement key.
  # Asking for it here bought that row on Tab's menu and nothing else.
  local -a want=(
    # Group the matches by tag, so the headers zhimmer draws over them read
    # "files", "options", "branches" rather than zsh's internal -default-.
    "group-name ''"
    "list-prompt ${(q)ZHIMMER_LIST_PROMPT}"
    # The same count and position under a menu that has scrolled. Without it
    # zsh falls back to its own wording, which says "Scrolling active" where
    # the line above says how many matches there are.
    "select-prompt ${(q)ZHIMMER_SELECT_PROMPT}"
    "menu select"
    # The selected row, in the place compsys reads: inside a completion,
    # ZLS_COLORS is rebuilt from this style for the duration, so setting the
    # parameter directly would not survive to reach Tab's menu. It is the same
    # colour zhimmer's own menu paints its bar with -- see ZHIMMER_SELECT_BG.
    "list-colors ma=${(q)ZHIMMER_SELECT}"
  )

  # What zhimmer actually set, for zhimmer-doctor to report: the useful question
  # is which of these the user's own config had already answered.
  typeset -ga ZHIMMER_TAMED=()
  local -a args; local entry
  for entry in $want; do
    args=( "${(@Q)${(z)entry}}" )
    (( ${+defined[$args[1]]} )) && continue
    zstyle ':completion:*' "${(@)args}"
    ZHIMMER_TAMED+=( $args[1] )
  done
}
