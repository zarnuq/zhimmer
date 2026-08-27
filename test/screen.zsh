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
# past it -- the combination the Tab bug needed.
: > $fh/zhimmer-target-file.txt

# For the Tab-and-the-drop-down cases: one directory that completes uniquely,
# two files that do not, and a directory too big to list in one screen.
mkdir -p $fh/zalpha $fh/zmany
: > $fh/zalpha/inner.txt
: > $fh/zbeta1.txt
: > $fh/zbeta2.txt
integer i; for i in {1..150}; do : > $fh/zmany/f$i; done

mkdir -p $fh/.config/zsh
cat > $fh/.config/zsh/.zshrc <<RC
autoload -Uz compinit; compinit -u -d $fh/compdump
PROMPT='%% '; RPROMPT=''; unsetopt beep
HISTFILE=$fh/hist_fixture
alias zgs='git status -s'
zstyle ':zhimmer:*' sources history alias command file
cd $fh
source $root/zhimmer.plugin.zsh
RC

start() {  # start [cols] [rows]
  s=zhimmer-test-$$-$RANDOM
  tmux new-session -d -s $s -x ${1:-100} -y ${2:-20} "env HOME=$fh TERM=xterm-256color zsh -i"
  sleep 2
}
stop() { tmux kill-session -t $s 2>/dev/null }

line1()  { tmux capture-pane -p -t $s | rg -v '^\s*$' | head -1 }
screen() { tmux capture-pane -p -t $s | rg -v '^\s*$' }
send()  { tmux send-keys -t $s "$@"; sleep 1.2 }

# One assertion body, told what to look at and whether the substring should be
# there. Four near-identical copies drifted apart once already -- two matched
# with a zsh glob, two literally -- so the same needle behaved differently
# depending on which helper it was handed to.
_assert() {  # _assert <capture-fn> <want|not> <label> <substring>
  local cap=$1 mode=$2 label=$3 want=$4
  integer hit=0
  $cap | rg -qF -- "$want" && hit=1
  if [[ ( $mode == want && $hit == 1 ) || ( $mode == not && $hit == 0 ) ]]; then
    print "  ok    $label"
    return
  fi
  print "  FAIL  $label"
  if [[ $mode == want ]]; then
    print "        want: $want"
  else
    print "        must not contain: $want"
  fi
  print "        got:  $($cap | tail -6)"
  (( fails++ ))
}

# check/refute look at the line being edited; checks/refutes at the whole screen,
# which is where the drop-down is.
check()   { _assert line1  want "$@" }
refute()  { _assert line1  not  "$@" }
checks()  { _assert screen want "$@" }
refutes() { _assert screen not  "$@" }

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

# Ctrl+E (and End) take the ghost, the way zsh-autosuggestions binds them.
# Tab is not an accept key -- it stays zsh's completion, tested below.
start
send "cat zhimmer-tar"
send C-e
check  "Ctrl+E accepts the ghost" 'cat zhimmer-target-file.txt --verbose'
# Typing clears the ghost, so a tail that survives a keystroke is really in the
# buffer rather than merely drawn past the cursor.
send " x"
check  "the accepted text is in the buffer, not just on screen" 'cat zhimmer-target-file.txt --verbose x'
stop

# With no ghost to take, the same key must still be end-of-line. Left moves off
# the end, which drops the ghost; Ctrl+E then has only its original job to do.
start
send "cat zhimmer-tar"
send Left Left
send C-e
send "Z"
check  "Ctrl+E is still end-of-line when there is no ghost" 'cat zhimmer-tarZ'
stop

# Tab is zsh's own completion, which rewrites the buffer knowing nothing about
# zhimmer. The ghost was computed for the shorter text, so it must be dropped
# rather than redrawn after the longer one: the line read
# "...target-file.txtget-file.txt --verbose".
start
send "cat zhimmer-tar"
check  "ghost shows the history tail before Tab" 'cat zhimmer-target-file.txt --verbose'
send Tab
refute "Tab drops the ghost computed for the shorter word" 'txtget-file'
check  "Tab completed the filename, and the ghost is recomputed for it" 'cat zhimmer-target-file.txt --verbose'
stop

# Whatever is left showing when the line is accepted has to be what runs. The
# ghost is display-only -- it lives in POSTDISPLAY, not BUFFER -- so it must be
# gone by then rather than printed as part of the command that ran.
start
send "cat zhimmer-tar"
send Enter
refute "an accepted line does not keep the ghost it did not run" '--verbose'
stop

# Tab is zsh's completion, so it rewrites the line with no idea zhimmer drew a
# list from the word it just replaced: completing `./zal` to `./zalpha/` left
# the file list still showing the matches for `./zal`.
start
send "ls ./zal"
checks  "the file list shows the directory before Tab" './zalpha'
send Tab
checks  "Tab refreshes the list to describe the completed word" './zalpha/inner.txt'
stop

# zsh keeps one list across a run of Tabs, so tabbing through a directory has
# to leave it standing. Clearing the area on every press instead left it blank
# from the second Tab onwards.
start
send "ls ./z"
send Tab
send Tab
checks  "the match list is still there on the second Tab" 'zbeta2.txt'
refutes "and it is zsh's list, not zhimmer's rows for the old word" ' file '
stop

# When completion has several matches the listing area is zsh's. zhimmer's rows
# have to be out of the way rather than drawn over the top of it -- they hid
# zsh's own list entirely before.
start
send "ls ./zbeta"
send Tab
checks  "zsh's own list is what shows after an ambiguous Tab" 'zbeta2.txt'
refutes "zhimmer's list is not drawn over it" ' file '
stop

# Past LISTMAX zsh replaces a listing with "do you wish to see all N
# possibilities?" -- a yes/no question where every other Tab gives a list. A
# list-prompt answers that, but only with a pager: 150 names to page past, none
# of them selected. A long list goes to menu selection instead, so the arrows
# walk it and Tab takes the row -- the menu Down opens, reached from Tab.
start
send "ls ./zmany/"
send Tab
refutes "a long listing does not turn into a yes/no question" 'do you wish to see'
refutes "nor into a pager with nothing to select" 'Tab for more'
checks  "it is a menu, with the count and position under it" 'matches -- at'
check   "whose first row is selected into the line" 'ls ./zmany/f1'
send Down Down
check   "and the arrows walk it, one match at a time" 'ls ./zmany/f100'
stop

# The prompt has to survive it. The pager filled the screen from the top down,
# taking the line being edited with it; a menu keeps the line above and scrolls
# underneath it.
start
send "ls ./zmany/"
send Tab
checks  "the line being edited is still on screen under a long menu" '% ls ./zmany/f1'
stop

# Short lists are not menus: they fit, so Tab still steps through the matches
# and Shift+Tab still steps back (covered below), rather than opening something
# to select in.
start
send "ls ./zb"
send Tab
refutes "a list that fits does not start menu selection" 'matches -- at'
stop

# Shift+Tab steps back up through the matches Tab is stepping down through.
# It cannot decide that from LASTWIDGET -- with fzf's completion loaded Tab is
# `fzf-completion`, with zhimmer's wrapper running underneath it -- so it goes
# by the line the last completion left behind.
start
send "ls ./zb"
send Tab
send Tab
check "Tab cycles into the matches" 'zbeta2.txt'
send BTab
check "Shift+Tab steps back through them, one match at a time" 'zbeta1.txt'
stop

start
send "sudo openv"
check   "the menu is up before the toggle" 'sudo openvpn'
# Shift+Tab must not be able to reach the switch: it is pressed far too often
# now, and a silently disabled zhimmer looks exactly like a broken one.
send BTab
checks  "Shift+Tab with nothing to step back into leaves zhimmer alone" ' history '
send C-Space
refutes "the switch has its own key" ' history '
checks  "and off says so, rather than just going quiet" 'zhimmer off'
send C-Space
checks  "turning it back on redraws the list without waiting for a keystroke" ' history '
stop

# An alias row says what the alias stands for, not just its name -- which is the
# whole point of the group. The rows travel to compadd separately from the
# matches they describe, so this is what catches them being dropped.
start
send "zg"
checks "the alias group shows what the alias expands to" 'zgs  →  git status -s'
stop

# `~` does not expand inside a parameter's value, so globbing $PREFIX directly
# matched nothing: every path under home came up blank while the same path
# spelled out matched fine.
start
send "ls ~/zal"
checks "a ~ path lists like any other" '~/zalpha'
stop

# Down opens whatever list is on screen. Asking the history matcher instead, as
# it used to, left every file-only list unreachable: Down did plain history
# navigation and the menu never opened.
start
send "ls ./zb"
send Down
checks "Down opens a menu drawn from a source other than history" 'zbeta1.txt'
stop

# The menu is not bound by the screen the way the plain listing is: it holds
# more than fits and scrolls, which is the only way to reach candidates past
# the bottom of the terminal.
start 80 14
send "ls ./zmany/f1"
send Down
checks "the menu holds more matches than the screen has rows" 'matches'
send Down Down Down Down Down Down Down Down Down Down Down Down
refutes "moving past the bottom scrolls rather than stopping at the top" 'at Top'
stop

# Tab's matches are drawn by zhimmer, not by complist's columns: same header
# and rule as the history and file groups, one row per line. The matches still
# come from the completion system -- only the display is rewritten.
start
send "ls ./zb"
send Tab
checks  "Tab's list carries a zhimmer group header" ' files '
checks  "and the matches themselves are still zsh's" 'zbeta1.txt'
stop

# Layout. A row wider than the terminal wraps onto a second line and pulls the
# list out of step with the menu, so long entries must be truncated instead.
start 46 16
send "sudo openv"
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
