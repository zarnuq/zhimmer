# Hosts from ~/.ssh/config and known_hosts, parsed as text and re-read only
# when an mtime moves.
typeset -g _zhimmer_ssh_at=
typeset -ga _zhimmer_ssh_hosts=()

# `Host` names, minus patterns (`*`, `prod-?`) and negations.
_zhimmer_ssh_config_hosts() {  # <~/.ssh/config text>  -> reply
  typeset -ga reply=()
  local l h
  local -a f
  for l in ${(f)1}; do
    # (z), not a pattern: that would need EXTENDED_GLOB, never set here.
    f=( ${(z)l} )
    (( $#f > 1 )) || continue
    [[ ${(L)f[1]} == host ]] || continue
    for h in ${f[2,-1]}; do
      [[ $h == *[*?!]* ]] && continue
      reply+=( ${(Q)h} )
    done
  done
  (( $#reply ))
}

# First field, comma-separated. Hashed (|1|) lines are skipped; `@marker`
# shifts the names right; `[host]:2222` is a non-default port.
_zhimmer_known_hosts() {  # <~/.ssh/known_hosts text>  -> reply
  typeset -ga reply=()
  local l h
  local -a f
  for l in ${(f)1}; do
    [[ -z $l || $l == \#* ]] && continue
    f=( ${(z)l} )
    [[ $f[1] == @* ]] && shift f
    (( $#f )) || continue
    [[ $f[1] == \|* ]] && continue         # hashed
    for h in ${(s:,:)f[1]}; do
      [[ $h == \[*\]:* ]] && h=${${h#\[}%%\]:*}
      [[ -n $h ]] && reply+=( $h )
    done
  done
  (( $#reply ))
}

_zhimmer_ssh_load() {
  local f stamp= REPLY
  for f in $HOME/.ssh/config $HOME/.ssh/known_hosts; do
    _zhimmer_mtime $f && stamp+=$REPLY:
  done
  [[ $_zhimmer_ssh_at == $stamp ]] && (( $#_zhimmer_ssh_hosts )) && return
  _zhimmer_ssh_at=$stamp

  local -a all=()
  local -a reply
  [[ -r $HOME/.ssh/config ]] &&
    _zhimmer_ssh_config_hosts "$(<$HOME/.ssh/config)" && all+=( $reply )
  [[ -r $HOME/.ssh/known_hosts ]] &&
    _zhimmer_known_hosts "$(<$HOME/.ssh/known_hosts)" && all+=( $reply )
  _zhimmer_ssh_hosts=( ${(u)all} )
}

_zhimmer_source_ssh-host() {
  (( CURRENT > 1 )) || return
  [[ $words[1] == (ssh|scp|sftp|rsync|mosh|ssh-copy-id) ]] || return
  local -i limit=$1
  # `host:` already chose one; the rest is a path.
  [[ $PREFIX == *:* ]] && return
  _zhimmer_ssh_load
  _zhimmer_addpicked zhimmer-ssh-host host $limit _zhimmer_ssh_hosts
}
