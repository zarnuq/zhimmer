# Non-interactive diagnostics. The sources themselves call compadd, which only
# exists inside a completion widget, so this reports on everything around them:
# configuration, the matcher binary, and the environment hazards that actually
# break this plugin in practice.

zhimmer-doctor() {
  local q=${1:-git }
  local -a srcs
  zstyle -a ':zhimmer:*' sources srcs || srcs=( history alias command )

  print -P '%B== zhimmer ==%b'
  print "  dir            $ZHIMMER_DIR"
  print "  enabled        $_zhimmer_enabled"
  print "  sources        $srcs"
  print "  max-suggestions $(_zhimmer_cfg max-suggestions 10)"
  print "  min-chars      $(_zhimmer_cfg min-chars 2)"
  print "  ghost-text     $(_zhimmer_cfg ghost-text yes)"

  print -P '\n%B== matcher ==%b'
  if [[ -x $ZHIMMER_BIN ]]; then
    print "  binary         $ZHIMMER_BIN"
  else
    print "  binary         MISSING -- run: cargo build --release --manifest-path $ZHIMMER_DIR/zhimmer-match/Cargo.toml"
  fi
  if [[ -r $HISTFILE ]]; then
    print "  histfile       $HISTFILE ($(wc -l < $HISTFILE) lines)"
  else
    print "  histfile       UNREADABLE: ${HISTFILE:-unset}"
  fi

  if [[ -x $ZHIMMER_BIN && -r $HISTFILE ]]; then
    print -P "\n%B== candidates for ${(qqq)q} ==%b"
    local -a out
    out=( ${(f)"$($ZHIMMER_BIN --history $HISTFILE --limit $(_zhimmer_cfg max-suggestions 10) -- "$q")"} )
    local c; for c in $out; do print "  $c"; done
    (( $#out )) || print "  (none)"

    zmodload -i zsh/datetime
    local -F s=$EPOCHREALTIME
    repeat 20 { $ZHIMMER_BIN --history $HISTFILE --limit 10 -- "$q" >/dev/null }
    printf "\n  %-14s %.2fms per call (budget: 10ms)\n" "timing" $(( (EPOCHREALTIME - s) * 50 ))
  fi

  print -P '\n%B== environment ==%b'
  _zhimmer_check "zsh/complist loaded"   "${modules[zsh/complist]:-no}" "loaded"
  _zhimmer_check "compinit has run"      "${+functions[compdef]}"       "1"
  _zhimmer_check "history written live"  "${options[incappendhistory]:-off}" "on" \
    "history only flushes at shell exit, so the current session is invisible to the matcher -- add: setopt INC_APPEND_HISTORY"
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
