#!/usr/bin/env zsh
# Screen-level tests for the ZLE layer.
#
# Renders through tmux and reads back capture-pane. Reading zpty's raw byte
# stream instead does not work: it interleaves every intermediate redraw, so
# text that has already been cleared is still present in the bytes and a
# stale-ghost bug reads exactly like a fixed one. capture-pane returns the
# resolved screen.
#
# Isolation fakes HOME rather than setting ZDOTDIR, because /etc/zsh/zshenv may
# set ZDOTDIR unconditionally (Gentoo does).
#
# Each scenario gets a fresh shell. Sharing one leaks state between tests --
# leaving menuselect requires Escape, which with EDITOR=nvim also drops the
# shell into vi normal mode, where later keystrokes are motions and not text.
#
# usage: zsh test/screen.zsh

emulate -L zsh
local root=${0:A:h:h}
local fh=$(mktemp -d)
integer fails=0
local s=''

cat > $fh/hist_fixture <<'HIST'
ls -la
sudo openvpn ~/VPNs/us12329.nordvpn.com.udp.ovpn
sudo openvpn ~/VPNs/universal.ovpn
sudo openvpn ~/VPNs/no
cat zhimmer-target-file.txt --verbose
git status --short --branch
git status --short --branch
HIST

# A real file, so Tab has something to complete whose history entry extends
# past it -- the combination the Tab bug needed. The second one appears in no
# history entry, so Tab there has no ghost to take and must complete instead.
: > $fh/zhimmer-target-file.txt
: > $fh/zhimmer-plain-file.txt

mkdir -p $fh/.config/zsh
cat > $fh/.config/zsh/.zshrc <<RC
autoload -Uz compinit; compinit -u -d $fh/compdump
PROMPT='%% '; RPROMPT=''; unsetopt beep
HISTFILE=$fh/hist_fixture
cd $fh
source $root/zhimmer.plugin.zsh
RC

start() {  # start [cols] [rows]
  s=zhimmer-test-$$-$RANDOM
  tmux new-session -d -s $s -x ${1:-100} -y ${2:-20} "env HOME=$fh TERM=xterm-256color zsh -i"
  sleep 2
}
stop() { tmux kill-session -t $s 2>/dev/null }

line1() { tmux capture-pane -p -t $s | rg -v '^\s*$' | head -1 }
send()  { tmux send-keys -t $s "$@"; sleep 1.2 }

check() {  # check <label> <expected substring>
  local label=$1 want=$2 got=$(line1)
  if [[ $got == *$want* ]]; then
    print "  ok    $label"
  else
    print "  FAIL  $label"
    print "        want: *$want*"
    print "        got:  $got"
    (( fails++ ))
  fi
}

refute() {  # refute <label> <substring that must be absent>
  local label=$1 bad=$2 got=$(line1)
  if [[ $got == *$bad* ]]; then
    print "  FAIL  $label"
    print "        must not contain: $bad"
    print "        got:  $got"
    (( fails++ ))
  else
    print "  ok    $label"
  fi
}

print "== zhimmer screen tests =="

start
send "sudo openv"
check "ghost completes the top candidate" 'sudo openvpn ~/VPNs/no'
# Backspace must refresh the ghost. Which widget it reaches depends on the
# keymap, so this covers the vi-backward-delete-char case.
send BSpace BSpace BSpace
check "ghost refreshes on backspace, no stale tail" 'sudo openvpn ~/VPNs/no'
# menuselect inserts the match into the buffer; a leftover ghost repeats its tail.
send Down
check "Down does not duplicate the suggestion" 'sudo openvpn ~/VPNs/no'
send Down
check "Down again moves to the second row" 'sudo openvpn ~/VPNs/universal.ovpn'
stop

# Tab takes the ghost into the buffer. The ghost lives in POSTDISPLAY, so what
# is on screen is not what runs: before this, Tab left the suggestion drawn and
# Enter executed only the typed prefix -- "git clone https://..." shown,
# "git clone htt" run.
start
send "cat zhimmer-tar"
check  "ghost shows the history tail before Tab" 'cat zhimmer-target-file.txt --verbose'
send Tab
check  "Tab accepts the ghost" 'cat zhimmer-target-file.txt --verbose'
# Typing clears the ghost, so a tail that survives a keystroke is really in the
# buffer -- the difference the bug turned on.
send " x"
check  "the accepted text is in the buffer, not just on screen" 'cat zhimmer-target-file.txt --verbose x'
stop

# Tab with no ghost must still be zsh's completion.
start
send "cat zhimmer-pl"
refute "no history entry, so no ghost" 'zhimmer-plain-file.txt'
send Tab
check  "Tab still completes a filename when there is no ghost" 'cat zhimmer-plain-file.txt'
stop

# Whatever is left showing when the line is accepted has to be what runs. The
# ghost is display-only, so it must be gone by then rather than printed as part
# of the command that ran.
start
send "cat zhimmer-tar"
send Enter
refute "an accepted line does not keep the ghost it did not run" '--verbose'
stop

# Layout. A row wider than the terminal wraps onto a second line and pulls the
# list out of step with the menu, so long entries must be truncated instead.
start 46 16
send "sudo openv"
screen() { tmux capture-pane -p -t $s | rg -v '^\s*$' }
if screen | rg -q '…'; then
  print "  ok    long rows truncate at narrow width"
else
  print "  FAIL  long rows are not truncated"
  (( fails++ ))
fi
integer overlong=$(screen | awk 'length > 46' | wc -l)
if (( overlong == 0 )); then
  print "  ok    no row exceeds the terminal width"
else
  print "  FAIL  $overlong row(s) wider than the terminal"
  (( fails++ ))
fi
stop

# Groups share one row budget; applying the cap per source instead overflows the
# screen and scrolls the earliest headers away.
# A single-word query, so the command source (which only fires on word 1) also
# contributes and there really are two groups.
start 90 20
send "gi"
if [[ $(tmux capture-pane -p -t $s) == *' history '* && $(tmux capture-pane -p -t $s) == *' command '* ]]; then
  print "  ok    multiple group headers stay on screen"
else
  print "  FAIL  a group header scrolled off"
  print "        got: $(tmux capture-pane -p -t $s | rg -v '^\s*$' | head -3)"
  (( fails++ ))
fi
stop

rm -rf $fh
print ""
if (( fails )); then
  print "$fails test(s) failed"
  exit 1
fi
print "all screen tests passed"
