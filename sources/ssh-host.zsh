# Hosts, for the commands that take one.
#
# Two files, read as text and parsed here rather than shelled out to: there is
# no `ssh --list-hosts`, and the alternatives all fork. ~/.ssh/config is short;
# known_hosts is not -- a few thousand lines is ordinary -- so neither is read
# again while its mtime is unchanged, which for these two files means once per
# shell in practice.
#
# zsh/stat is what makes that check free. Without it the stamp stays empty, the
# cache never invalidates, and the hosts are read exactly once -- which is the
# same answer for anyone not editing their ssh config mid-session.
zmodload -F zsh/stat b:zstat 2>/dev/null

typeset -g _zhimmer_ssh_at=
typeset -ga _zhimmer_ssh_hosts=()

# Host lines name one or more aliases. A pattern is not a host you can connect
# to, so `Host *` and `Host prod-?` are dropped rather than offered as text to
# type; so is a negation, which only ever narrows a pattern above it.
_zhimmer_ssh_config_hosts() {  # <~/.ssh/config text>  -> reply
  typeset -ga reply=()
  local l h
  local -a f
  for l in ${(f)1}; do
    # (z) splits the line the way the shell would, which takes the leading
    # indentation and any quoting with it. Doing it by pattern would want
    # EXTENDED_GLOB, and this plugin never sets it -- what a `#` means in a
    # pattern here is whatever the user's own options say.
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

# known_hosts holds the name (or several, comma-separated) in the first field.
# A hashed file says |1| and cannot be read back at all, which is a setting
# people turn on deliberately -- those lines are skipped rather than shown as
# hashes. `@cert-authority` and `@revoked` markers push the names one field to
# the right, and a non-default port is written `[host]:2222`.
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
  local -a st
  local f stamp=
  for f in $HOME/.ssh/config $HOME/.ssh/known_hosts; do
    zstat -A st +mtime $f 2>/dev/null && stamp+=$st[1]:
  done
  [[ $_zhimmer_ssh_at == $stamp ]] && (( $#_zhimmer_ssh_hosts )) && return
  _zhimmer_ssh_at=$stamp

  local -a all=()
  local -a reply
  [[ -r $HOME/.ssh/config ]] &&
    _zhimmer_ssh_config_hosts "$(<$HOME/.ssh/config)" && all+=( $reply )
  [[ -r $HOME/.ssh/known_hosts ]] &&
    _zhimmer_known_hosts "$(<$HOME/.ssh/known_hosts)" && all+=( $reply )
  # The same host is usually in both files, and twice in a list is once too
  # many when the list is ten rows.
  _zhimmer_ssh_hosts=( ${(u)all} )
}

_zhimmer_source_ssh-host() {
  (( CURRENT > 1 )) || return
  [[ $words[1] == (ssh|scp|sftp|rsync|mosh|ssh-copy-id) ]] || return
  local -i limit=$2
  # scp and rsync take paths as well as hosts, and a path is not a host until
  # there is no `:` in the word: `scp file host:` is past choosing one.
  [[ $PREFIX == *:* ]] && return
  _zhimmer_ssh_load
  local -a reply
  _zhimmer_pick $limit ${(M)_zhimmer_ssh_hosts:#${(b)PREFIX}*} || return
  _zhimmer_addwords zhimmer-ssh-host host "$reply[@]"
}
