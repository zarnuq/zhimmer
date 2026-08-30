# Non-interactive diagnostics. The sources themselves call compadd, which only
# exists inside a completion widget, so this reports on everything around them:
# configuration, what the history ranking answers and how fast, and the
# environment hazards that actually break this plugin in practice.

# Plugins that cannot share the mechanism zhimmer works through. Each entry is
# a name, a pattern matched against the function table, and what goes wrong --
# split on `|`, so a table of them is one line each rather than a paragraph of
# ifs. Detection is by function name because that is what survives being loaded
# by any of the framework managers, none of which agree on anything else.
typeset -ga ZHIMMER_CONFLICTS=(
  'zsh-autosuggestions|_zsh_autosuggest_start|it also writes POSTDISPLAY; the two fight over ghost text'
  'fzf-tab|fzf-tab-complete|it also shadows compadd to draw Tab, so only one of the two styles a list -- set style-completion no to yield'
  'zsh-autocomplete|.autocomplete.__init__|it draws its own as-you-type menu from the same keys; run one or the other'
  'zsh-abbr|abbr|it expands on Space as well -- turn off expand-alias if the two disagree about a word'
)

zhimmer-doctor() {
  local q=${1:-git }
  local -a srcs
  zstyle -a ':zhimmer:*' sources srcs || srcs=( history alias command )

  print -P '%B== zhimmer ==%b'
  print "  dir              $ZHIMMER_DIR"
  print "  enabled          $_zhimmer_enabled"
  print "  sources          $srcs"
  # Straight from the table the code reads, so this cannot drift from it.
  local k REPLY
  for k in ${(ok)ZHIMMER_DEFAULTS}; do
    _zhimmer_cfg $k
    printf '  %-16s %s\n' $k $REPLY
  done
  print "  LISTMAX          $LISTMAX"
  # Which of the completion styles zhimmer set, and so which ones the user's own
  # configuration had already answered for itself.
  print "  styles set       ${ZHIMMER_TAMED:-(none)}"

  print -P '\n%B== history ==%b'
  # What the ranking can see: $history is the shell's own, so this is the whole
  # of it as long as HISTSIZE is not the smaller of the two numbers.
  print "  entries          ${#history} in memory (HISTSIZE ${HISTSIZE:-unset}, SAVEHIST ${SAVEHIST:-unset})"
  (( ${HISTSIZE:-0} < ${SAVEHIST:-0} )) &&
    print "  WARN             HISTSIZE is below SAVEHIST, so the ranking sees less than the file keeps -- raise HISTSIZE to match"

  if (( ${#history} )); then
    print -P "\n%B== candidates for ${(qqq)q} ==%b"
    local -a reply
    _zhimmer_cfg max-suggestions
    local -i lim=$REPLY
    _zhimmer_hist_q=
    _zhimmer_hist_rank "$q" $lim
    local c; for c in $reply; do print "  $c"; done
    (( $#reply )) || print "  (none)"

    # Both halves of the cost, because they are what the two are for: the first
    # keystroke of a word searches the whole history, and every keystroke after
    # it narrows what that search already found.
    zmodload -i zsh/datetime
    local -F s=$EPOCHREALTIME
    repeat 20 { _zhimmer_hist_q=; _zhimmer_hist_rank "$q" $lim }
    local -F cold=$(( (EPOCHREALTIME - s) * 50 ))
    s=$EPOCHREALTIME
    repeat 20 { _zhimmer_hist_rank "$q" $lim }
    printf "\n  %-16s %.2fms first keystroke, %.2fms narrowing (budget: 10ms)\n" \
      "timing" $cold $(( (EPOCHREALTIME - s) * 50 ))
  fi

  print -P '\n%B== environment ==%b'
  _zhimmer_check "zsh/complist loaded"   "${modules[zsh/complist]:-no}" "loaded"
  _zhimmer_check "compinit has run"      "${+functions[compdef]}"       "1"
  # Straight from the table, so a conflict is added in one line and reported
  # in the same words as every other check.
  local -a c
  local -i found
  local e
  for e in $ZHIMMER_CONFLICTS; do
    c=( ${(s:|:)e} )
    found=0
    [[ -n ${(M)${(k)functions}:#${~c[2]}} ]] && found=1
    _zhimmer_check "$c[1] absent" $found 0 "$c[3]"
  done

  # Only when the prompt is switched on. Pure and starship are not conflicts
  # for a completion menu -- most people running zhimmer are running one of
  # them -- so this is asked about the one setting that makes them one, rather
  # than added to the table above and warned about unconditionally.
  if (( _zhimmer_prompt_on )); then
    local -A pconf=(
      'pure'     'prompt_pure_precmd'
      'starship' 'starship_precmd'
      'p10k'     'p10k'
      'spaceship' 'spaceship_precmd'
    )
    local pk
    for pk in ${(ok)pconf}; do
      (( ${+functions[${pconf[$pk]}]} )) &&
        print "  WARN  $pk is loaded and zhimmer's prompt is on -- the last one to set PROMPT wins\n        turn one off: zstyle ':zhimmer:*' prompt no, or zhimmer-prompt-off"
    done
  fi

  local sf
  for sf in $srcs; do
    (( ${+functions[_zhimmer_source_$sf]} )) || print "  WARN  source '$sf' is configured but has no _zhimmer_source_$sf function"
  done
}

_zhimmer_check() {  # label actual expected [remedy]
  local label=$1 actual=$2 want=$3 remedy=$4
  if [[ $actual == $want ]]; then
    print "  ok    $label"
  else
    print "  WARN  $label (is: $actual)"
    [[ -n $remedy ]] && print "        $remedy"
  fi
}
