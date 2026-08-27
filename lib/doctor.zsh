# Non-interactive diagnostics. The sources themselves call compadd, which only
# exists inside a completion widget, so this reports on everything around them:
# configuration, what the history ranking answers and how fast, and the
# environment hazards that actually break this plugin in practice.

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
  _zhimmer_check "zsh-autosuggestions absent" "${+functions[_zsh_autosuggest_start]}" "0" \
    "it also writes POSTDISPLAY; the two will fight over ghost text"

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
