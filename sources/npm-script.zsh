# The scripts in package.json, for `npm run` and the managers that copy it.
#
# Parsed as lines rather than as JSON: there is no JSON parser in zsh, jq is not
# everywhere, and shelling out to node to ask is a fork of the heaviest kind on
# a keystroke. What is relied on is that the file is pretty-printed one script
# per line, which is what every tool that writes package.json produces -- npm
# itself, yarn, pnpm and every editor's formatter.
#
# The cost of being wrong is a missing row in a menu, not a broken command, so
# this trades a parser nobody can maintain for one that fits on a screen.
zmodload -F zsh/stat b:zstat 2>/dev/null

typeset -g _zhimmer_npm_at= _zhimmer_npm_dir=
typeset -ga _zhimmer_npm_scripts_c=()

# The keys of the "scripts" object. The first quoted string on a line is the
# key -- `"build": "tsc -p ."` -- so the value, which is where the commas and
# braces that would confuse a split live, is never looked at.
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
  local -a st
  local stamp=
  [[ -r package.json ]] && zstat -A st +mtime package.json 2>/dev/null && stamp=$st[1]
  [[ $_zhimmer_npm_at == "$stamp" && $_zhimmer_npm_dir == $PWD ]] && return
  _zhimmer_npm_at=$stamp _zhimmer_npm_dir=$PWD

  local -a reply
  if [[ -r package.json ]] && _zhimmer_npm_scripts "$(<package.json)"; then
    _zhimmer_npm_scripts_c=( $reply )
  else
    _zhimmer_npm_scripts_c=()
  fi
}

_zhimmer_source_npm-script() {
  # `npm run <name>`, and the same shape in the others. Not at the subcommand
  # itself: at `npm run` there is no script argument yet.
  (( CURRENT > 2 )) || return
  [[ $words[1] == (npm|pnpm|yarn|bun) && $words[2] == (run|run-script) ]] || return
  local -i limit=$1
  _zhimmer_npm_load
  local -a reply
  _zhimmer_pick $limit ${(M)_zhimmer_npm_scripts_c:#${(b)PREFIX}*} || return
  _zhimmer_addwords zhimmer-npm-script script "$reply[@]"
}
