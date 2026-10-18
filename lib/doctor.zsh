# Diagnostics from outside a completion widget: config, history ranking and
# its cost, and environment hazards.

# name|function pattern|what goes wrong. By function name: it survives every
# plugin manager.
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
  local k REPLY
  for k in ${(ok)ZHIMMER_DEFAULTS}; do
    _zhimmer_cfg $k
    printf '  %-16s %s\n' $k $REPLY
  done
  print "  LISTMAX          $LISTMAX"
  print "  styles set       ${ZHIMMER_TAMED:-(none)}"

  print -P '\n%B== history ==%b'
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

    # First keystroke searches everything; later ones narrow.
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
  local -a c
  local -i found
  local e
  for e in $ZHIMMER_CONFLICTS; do
    c=( ${(s:|:)e} )
    found=0
    [[ -n ${(M)${(k)functions}:#${~c[2]}} ]] && found=1
    _zhimmer_check "$c[1] absent" $found 0 "$c[3]"
  done

  # Other prompts only conflict when zhimmer's prompt is on.
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
