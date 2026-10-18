# package.json scripts, for `npm run` and friends. Parsed as lines, assuming
# one script per line as every tool writes it; being wrong costs a missing row.
typeset -g _zhimmer_npm_at=
typeset -ga _zhimmer_npm_scripts_c=()

# The first quoted string on each line of the "scripts" block is the key; the
# value is never looked at.
_zhimmer_npm_scripts() {  # <package.json text>  -> reply
  typeset -ga reply=()
  local l k
  local -i inblock=0
  for l in ${(f)1}; do
    if (( ! inblock )); then
      [[ $l == *\"scripts\"*:*\{* ]] && inblock=1
      continue
    fi
    [[ $l == *\}* ]] && break
    [[ $l == *\"*\"*:* ]] || continue
    k=${l#*\"}
    k=${k%%\"*}
    [[ -n $k ]] && reply+=( $k )
  done
  (( $#reply ))
}

_zhimmer_npm_load() {
  local REPLY
  _zhimmer_mtime package.json
  [[ $_zhimmer_npm_at == "$REPLY:$PWD" ]] && return
  _zhimmer_npm_at="$REPLY:$PWD"

  local -a reply
  if [[ -r package.json ]] && _zhimmer_npm_scripts "$(<package.json)"; then
    _zhimmer_npm_scripts_c=( $reply )
  else
    _zhimmer_npm_scripts_c=()
  fi
}

_zhimmer_source_npm-script() {
  (( CURRENT > 2 )) || return
  [[ $words[1] == (npm|pnpm|yarn|bun) && $words[2] == (run|run-script) ]] || return
  local -i limit=$1
  _zhimmer_npm_load
  _zhimmer_addpicked zhimmer-npm-script script $limit _zhimmer_npm_scripts_c
}
