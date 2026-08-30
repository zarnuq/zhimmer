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
echo [zhimmer] glob test
grep -rn 'zhimmer(' .
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

# Forty commands on PATH, more than the ten a list may show, so "the first ten"
# is a different answer from "ten of them". The command source cut before it
# sorted, which made the answer whichever ten the hash held first.
mkdir -p $fh/zbin
for i in {1..40}; do
  printf '#!/bin/sh\n' > $fh/zbin/zzc-$(printf '%02d' $i)
  chmod +x $fh/zbin/zzc-$(printf '%02d' $i)
done

# A makefile, for the target source: read as text rather than asked of make,
# so what it can see is what is written in the first column.
cat > $fh/Makefile <<'MAKE'
CC := gcc
.PHONY: zbuild
zbuild: zdeps
	true
zdeps:
	true
%.o: %.c
	true
MAKE

# A repository with more branches than a list can hold, for the branch source:
# it has to wait for the subcommand to be over, cut to the limit like every
# other source, and read the refs once per command rather than once per key.
git init -q $fh/zrepo
git -C $fh/zrepo -c user.email=t@t -c user.name=t commit -q --allow-empty -m x
for i in {1..15}; do git -C $fh/zrepo branch zb-$(printf '%02d' $i); done
git -C $fh/zrepo branch zfeature-a
# Remote-tracking refs, written directly: a real remote would need a second
# repository and a fetch, and what the source reads is refs/remotes either way.
git -C $fh/zrepo update-ref refs/remotes/zorigin/main \
  "$(git -C $fh/zrepo rev-parse HEAD)"
git -C $fh/zrepo update-ref refs/remotes/zorigin/HEAD \
  "$(git -C $fh/zrepo rev-parse HEAD)"

# A repository with a known dirty state, for the prompt. Committed first so
# there is a HEAD to read, then dirtied one file per symbol the prompt can draw.
# The branch name carries a slash, which is the case a greedy ${head##*/} gets
# wrong -- and gets wrong silently, on exactly the branches that say the most.
mkdir -p $fh/zrepo
git -C $fh/zrepo init -q -b main 2>/dev/null
git -C $fh/zrepo config user.email t@t; git -C $fh/zrepo config user.name t
: > $fh/zrepo/tracked.txt; : > $fh/zrepo/doomed.txt
git -C $fh/zrepo add -A 2>/dev/null
git -C $fh/zrepo commit -qm init 2>/dev/null
git -C $fh/zrepo checkout -qb feat/menu 2>/dev/null
print change >> $fh/zrepo/tracked.txt      # modified   !
: > $fh/zrepo/fresh.txt                    # untracked  ?

mkdir -p $fh/.config/zsh
cat > $fh/.config/zsh/.zshrc <<RC
autoload -Uz compinit; compinit -u -d $fh/compdump
PROMPT='%% '; RPROMPT=''; unsetopt beep
HISTFILE=$fh/hist_fixture
alias zgs='git status -s'
zstyle ':zhimmer:*' sources history alias command file git-branch git-file make npm-script ssh-host
PATH=$fh/zbin:\$PATH
cd $fh
# A self-insert wrapper that was already there when zhimmer loaded. It
# uppercases what is typed, so the screen says whether zhimmer chained onto it
# or replaced it.
# Row colours are on by default, so the case that checks they can be turned
# off has to say so before the plugin reads the style at load.
if [[ -n \$ZHIMMER_TEST_NO_ROW_COLORS ]]; then
  zstyle ':zhimmer:*' row-colors no
fi
# The prompt is off by default, so the cases that want it say so.
if [[ -n \$ZHIMMER_TEST_PROMPT ]]; then
  zstyle ':zhimmer:*' prompt yes
fi
if [[ -n \$ZHIMMER_TEST_CHAIN ]]; then
  _ztest_upper() { LBUFFER+=\${KEYS:u} }
  zle -N self-insert _ztest_upper
fi
source $root/zhimmer.plugin.zsh
RC

extra_env=''
start() {  # start [cols] [rows]   -- $extra_env goes into the shell's environment
  s=zhimmer-test-$$-$RANDOM
  tmux new-session -d -s $s -x ${1:-100} -y ${2:-20} \
    "env HOME=$fh TERM=xterm-256color $extra_env zsh -i"
  sleep 2
}
stop() { tmux kill-session -t $s 2>/dev/null }

line1()  { tmux capture-pane -p -t $s | rg -v '^\s*$' | head -1 }
screen() { tmux capture-pane -p -t $s | rg -v '^\s*$' }
# The row the menu is on, read back from the colour complist paints it in (ma=
# in lib/theme.zsh). The menu no longer writes the row it is passing over into
# the line, so the highlight is the only thing on screen that says where the
# cursor is.
selected() {
  tmux capture-pane -p -e -t $s | rg -F '48;2;69;71;90' |
    sed -e $'s/\e\\[[0-9;]*m//g' -e 's/^ *//' -e 's/ *$//'
}
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
# The exit-status colour, read back from the escape the terminal actually got.
# The indicator is a colour on one character, so there is nothing in the plain
# text capture that distinguishes success from failure.
promptcol() { tmux capture-pane -p -e -t $s | rg -o '38;2;[0-9;]+m ?>' | tail -1 }

check()   { _assert line1  want "$@" }
refute()  { _assert line1  not  "$@" }
checksel(){ _assert selected want "$@" }
checks()  { _assert screen want "$@" }
refutes() { _assert screen not  "$@" }
checkcol(){ _assert promptcol want "$@" }

# Row accents live nowhere in the plain-text capture: the display strings are
# plain by design, and ZLS_COLORS is what puts the escape on screen. So these
# read the escapes back rather than the text.
screenesc() { tmux capture-pane -p -e -t $s }
checkesc()  { _assert screenesc want "$@" }

refuteesc() { _assert screenesc not  "$@" }

print "== zhimmer screen tests =="

start
send "sudo openv"
check "ghost completes the top candidate" 'sudo openvpn ~/VPNs/no'
# Backspace must refresh the ghost. Which widget it reaches depends on the
# keymap, so this covers the vi-backward-delete-char case.
send BSpace BSpace BSpace
check "ghost refreshes on backspace, no stale tail" 'sudo openvpn ~/VPNs/no'
# The menu does not write rows into the line as it walks them, so the line
# still holds what was typed. The ghost past it follows the *selection* rather
# than staying on the top candidate -- otherwise the bar would mark one row
# while the greyed tail promised another, and Right and Enter would put
# different lines on screen.
send Down
checksel "Down opens the menu on its first row" 'sudo openvpn ~/VPNs/no'
check    "and the ghost is showing that same row"  'sudo openvpn ~/VPNs/no'
send Down
checksel "Down again moves to the second row" 'sudo openvpn ~/VPNs/universal.ovpn'
check    "and the ghost moves with it"        'sudo openvpn ~/VPNs/universal.ovpn'
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

# The ghost is the top row of whatever is on screen, and every group offers its
# first row as it is drawn. It used to come from the history source alone, so a
# list drawn by any other source sat there with nothing in front of the cursor.
start
send "cat zbet"
check "a file source puts a ghost up when history has no match" 'cat zbeta1.txt'
stop

# And when both have something to say, history wins: a whole remembered line is
# worth more than a command name completed out of $PATH. Without the rank this
# would be decided by whichever source the `sources` style happens to name
# first, which is not a decision the user meant to make when ordering the list.
start
# Asserted on the line being edited, not the screen: the drop-down is showing
# these same strings as rows, so a whole-screen match would pass with no ghost
# in front of the cursor at all. A ghost of `git` from $commands leaves the line
# reading `git`, which does not contain the history line.
send "gi"
check "history outranks the command source for the ghost" 'git status --short --branch'
stop

# A word of the ghost at a time, the way zsh-autosuggestions takes one on
# forward-word. Taking a word cannot be seen on the line -- buffer plus ghost
# reads the same either way -- so the line is run and what the shell actually
# got is what the assertion looks at.
start
send "cat zh"
send M-f
check "a partial accept leaves the line looking unchanged" 'cat zhimmer-target-file.txt --verbose'
send Enter
refutes "but only the accepted word ran" '--verbose'
checks  "and the word that was taken did" 'cat zhimmer-target-file.txt'
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
# of them selected. The matches go to menu selection instead, so the arrows and
# Tab walk it and Enter takes the row -- the menu Down opens, reached from Tab.
start
send "ls ./zmany/"
send Tab
refutes "a long listing does not turn into a yes/no question" 'do you wish to see'
refutes "nor into a pager with nothing to select" 'Tab for more'
checks   "it is a menu, with the count and position under it" 'matches -- at'
checksel "whose first row is the one the cursor is on" 'f1'
# Tab's menu is plain zsh menu selection: it writes each match into the line as
# it walks. `interactive` is what would stop that, and it is deliberately not
# asked for -- complist draws a hardcoded `interactive: []` row for as long as
# the mode is on. zhimmer's own drop-down is the one that marks without writing.
check    "and it writes the row it is on into the line" 'ls ./zmany/f1'
send Down Down
checksel "the arrows walk it, one match at a time" 'f100'
send Enter
check    "Enter takes the row it ended on" 'ls ./zmany/f100'
stop

# The prompt has to survive it. The pager filled the screen from the top down,
# taking the line being edited with it; a menu keeps the line above and scrolls
# underneath it.
start
send "ls ./zmany/"
send Tab
checks  "the line being edited is still on screen under a long menu" '% ls ./zmany/'
stop

# Typing at Tab's open menu takes the row it is on and types after it, which is
# what `menu-complete` has always done. Narrowing is zhimmer's own drop-down's
# job, and it picks the typing up from here -- see "the drop-down" below, where
# the same keystrokes narrow instead.
start
send "ls ./zmany/"
send Tab
send "f149"
check "typing at Tab's menu takes the row and types after it" 'ls ./zmany/f1'
stop

# Backspace is bound inside the menu as well as outside it: zhimmer rebinds the
# widget to refresh the drop-down, which stopped complist recognising the key
# and made it leave the menu, accepting a row on the way out.
start
send "ls ./zmany/"
send Tab
send BSpace
checks "backspace hands the area back to zhimmer's own list" ' file '
stop

# A short list fits on screen, which is not the same as having nothing to choose
# from: it gets selection too, so the row Tab is on is marked rather than
# guessed at from the line.
start
send "ls ./zb"
send Tab
checksel "a list that fits is selectable too" 'zbeta1.txt'
send Tab
checksel "Tab walks it rather than accepting the first row" 'zbeta2.txt'
send BTab
checksel "and Shift+Tab walks back up it" 'zbeta1.txt'
send Enter
check    "Enter takes the row" 'ls ./zbeta1.txt'
stop

# Shift+Tab steps back up through the matches Tab is stepping down through,
# where menu selection never starts and stepping is all there is -- which is
# what a user who sets their own `menu` style gets, since zhimmer leaves a style
# that is already set alone.
# It cannot decide that from LASTWIDGET -- with fzf's completion loaded Tab is
# `fzf-completion`, with zhimmer's wrapper running underneath it -- so it goes
# by the line the last completion left behind.
start
send "zstyle ':completion:*' menu yes"
send Enter
send C-l          # the command has to go: line1 reads the top of the screen
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

# Deciding not to draw is not the same as leaving the screen alone. Deleting a
# line back to empty left the list for the word that used to be there standing
# under an empty prompt -- rows describing a buffer that no longer existed.
start
send "ca"
checks "a list is drawn for what was typed" ' history '
send BSpace
send BSpace
refutes "and taken back down when the line is emptied" ' history '
send "ca"
checks "and comes back when there is a word again" ' history '
stop

# The same thing by a route no wrapper covers. ^U is vi-kill-line under viins,
# which zsh selects whenever EDITOR looks like vi, and naming every widget that
# can shorten a line is what the redraw guard exists to stop having to do.
extra_env='EDITOR=nvim'
start
send "ca"
checks "a list is drawn under the vi keymap too" ' history '
send C-u
refutes "and ^U takes it down, though no wrapper names vi-kill-line" ' history '
stop
extra_env=''

# Nothing typed is not a query. An empty word matched every alias and every
# executable on $PATH, and put a ghost of whichever sorted first on the line --
# at stock settings, since two spaces clear min-chars without being a word.
start
send "  "
refutes "an empty word draws no alias group" ' alias '
refutes "and no command group either" ' command '
stop

# A query is text, not a pattern. History holds commands with [, * and ~ in
# them, and $history is searched with a pattern -- so the query has to be
# quoted into one, or `echo [` looks for a character class that never closes.
start
send "echo [zh"
checks "a bracket typed at the prompt matches itself, not a character class" 'echo [zhimmer] glob test'
stop

# A match is a key in the ranking's hashes, and it was also read back as one
# inside $(( )), where the key is parsed as arithmetic -- so a history line
# holding a stray ( or [ was an invalid subscript that took the whole list down
# with it, not just its own row.
start
send "grep -r"
checks "a match with an unbalanced bracket in it still ranks" "grep -rn 'zhimmer(' ."
stop

# The ranking reads $history, the shell's own, rather than the file it would be
# flushed to -- so a command run in this session is matchable at the next
# keystroke, with no INC_APPEND_HISTORY and no re-read.
start
send "echo zhimmer-session-marker"
send Enter
send C-l          # the command has to go: the list is read off the whole screen
send "echo zhimmer-ses"
checks "a command run in this session is suggested straight away" 'echo zhimmer-session-marker'
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

# The list is not bound by the screen. The drawn window is -- only the rows
# that fit are laid out -- but the window scrolls, so a candidate past the
# bottom of the terminal is still reachable by walking down to it. Clamping the
# list itself to $LINES is what stops a menu holding more than fits.
start 80 14
send "ls ./zmany/f1"
send Down
checks   "the first rows are drawn under their header" ' file '
send Down Down Down Down Down Down Down Down Down
checksel "walking past the bottom reaches a row that did not fit" './zmany/f107'
refutes  "and the window has scrolled the header off the top" ' file '
# Wrapping, which is also what lets Up open the menu from nothing.
send Down
checksel "and one more wraps back to the first row" './zmany/f1'
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

# A list shows the first ten matches, not ten of them. The command source cut
# the hash down to the limit and sorted what was left, so `zzc-` offered
# whichever ten $commands happened to hold first -- a different ten per shell,
# and almost never the ten a sorted list promises.
start
send "zzc-"
checks "the command list starts at the first match, not an arbitrary one" 'zzc-01'
refutes "and stops at the limit rather than sampling past it" 'zzc-40'
stop

# `ls ./z*` is a glob, and zsh globs it. The file source expanded the word to
# match on and then stripped the expansion back off each match to rebuild the
# row -- which only works when the word is a literal. With a glob in it the two
# are different strings, and the rows read `./z*./zalpha`.
start
send "ls ./z*"
checks  "a glob in the word lists what it matches" './zbeta1.txt'
refutes "rather than the word with a path stuck on the end" './z*./'
stop

# The same word with a ~ in front of it: both halves at once, which is where
# expanding the whole word and stripping it back off went wrong twice.
start
send "ls ~/z*"
checks  "a ~ path with a glob in it lists too" '~/zbeta1.txt'
refutes "and keeps the ~ rather than the path it stands for" "$fh/zbeta1.txt"
stop

# zsh expands a command alias in every command position, not only at the start
# of a line. Testing for "nothing but whitespace before it" left the alias
# sitting there unexpanded after every pipe and every `;`.
start
send "ls | zgs"
send Space
check "an alias expands after a pipe, the way zsh expands it" 'ls | git status -s'
stop

# ...and only in command position. A `|` earlier in the line does not make
# everything after it a command, so this one is an argument and stays as typed.
start
send "echo a| b zgs"
send Space
check  "an alias in argument position is left alone" 'echo a| b zgs'
refute "and is not expanded there" 'git status -s'
stop

# The branch source waits for the subcommand to be over. On `git branch` the
# word being completed is the subcommand itself, and matching there asked for
# branches to replace the word `branch`.
start
send "cd zrepo"
send Enter
send C-l
send "git branch"
refutes "no branch list while the subcommand itself is being typed" 'zfeature-a'
send " zfea"
checks  "branches come once there is an argument to complete" 'zfeature-a'
stop

# `git push origin main` -- the first argument is a remote, not a branch. The
# source used to offer branches in both places, which is the one position where
# being wrong costs something: `git push main` names a remote that is not there
# and the error comes back from the far end.
start
send "cd zrepo"
send Enter
send C-l
send "git push zor"
checks  "a remote is offered where a remote goes" 'zorigin'
refutes "and branches are not" 'zb-01'
stop

# Targets read out of the Makefile, not out of `make -pn`: building make's
# database runs the makefile's own shell assignments, which is a fork and a
# side effect for something asked on every keystroke.
start
send "make zbu"
checks  "a make target is offered" 'zbuild'
refutes "and a pattern rule is not a target" '%.o'
stop

# Every other source cuts to the limit; this one did not, and a repository with
# a few hundred branches put all of them in a menu that has no row budget of its
# own to stop them.
start
send "cd zrepo"
send Enter
send C-l
send "git checkout zb-"
# Indented rows only. A bare count of the branch name over the whole screen
# also catches the line being edited, which now carries a ghost of the top
# branch -- so a correctly cut list of ten read as eleven. Rows are indented by
# two (_zhimmer_row); the prompt line is not.
integer branches=$(screen | rg -c '^\s+zb-[0-9]')
if (( branches <= 10 )); then
  print "  ok    the branch list is cut to the limit like every other source"
else
  print "  FAIL  the branch list ignored the limit ($branches rows for a limit of 10)"
  (( fails++ ))
fi
stop

# self-insert is the busiest widget in the shell and other plugins wrap it too.
# zhimmer replaced it outright and called the builtin underneath, which dropped
# whatever was already there -- here, a wrapper that uppercases what is typed.
extra_env='ZHIMMER_TEST_CHAIN=1'
start
send "abc"
check "zhimmer chains onto an existing self-insert rather than replacing it" 'ABC'
stop
extra_env=''

print "\n-- the prompt --"
# Off by default: someone loading zhimmer for its menu keeps the prompt they
# came with, whether that is Pure, starship or zsh's own.
start
send "cd zrepo" Enter
refutes "the prompt stays out of the way unless asked for" 'feat/menu'
stop

extra_env='ZHIMMER_TEST_PROMPT=1'
start
send "cd zrepo" Enter
checks "the prompt draws the directory" 'zrepo'
checks "and the branch, slash and all, out of .git/HEAD" 'feat/menu'
# The symbols arrive from the background half, so this is also the assertion
# that the async path delivers at all.
checks "and the status symbols for a dirty tree" '!?'
stop

# Exit status is baked into the string at precmd rather than left to %(?..),
# because the async redraw happens long after $? stopped meaning the command.
start
send "cd zrepo" Enter
send "true" Enter
checkcol "the prompt marks success" '166;227;161'
send "false" Enter
checkcol "and marks a failure" '243;139;168'
# The redraw the background half provokes must not repaint a failure as a
# success: a reset-prompt that re-read $? would report on the redraw instead.
send "" Enter
send "false" Enter
sleep 2
checkcol "a failure survives the async redraw" '243;139;168'
stop

# A repository is not the only place a prompt gets drawn.
start
send "cd /tmp" Enter
checks "outside a repository there is no branch and no symbols" '/tmp'
refutes "and nothing left over from the last one" 'feat/menu'
stop

# Saving and restoring, not just setting: the fixture rc uses '%% ' as its
# prompt, so the restore is visible.
start
send "cd zrepo" Enter
send "zhimmer-prompt-off" Enter
# Cleared first. Turning the prompt off does not erase the lines it already
# drew, and a whole-screen assertion reads that scrollback as proof it is
# still on -- which is how this case passed a broken restore once.
send "clear" Enter
refutes "turning it off puts the original prompt back" 'feat/menu'
send "zhimmer-prompt-on" Enter
send "clear" Enter
checks "and turning it on brings it back" 'feat/menu'
stop
extra_env=''


print "\n-- row colours --"
start
send "git"
# The command word of a history row, in the command green.
checkesc "a history row colours its command word" '38;2;166;227;161mgit'
# Plain escapes in a display string would be counted as width by the layout and
# push the row over the edge; these come from ZLS_COLORS, after the measuring.
refutes  "and the row is not wrapped by the escapes" 'status --short --branch$'
stop

start
send "cat ./zb"
# Group scoping: without it a filename would be painted as though it were a
# command, which is the whole reason the rules carry a (group) prefix.
checkesc "a file row uses the file colour"       '38;2;250;179;135m./zbeta'
refuteesc "and not the command green"            '38;2;166;227;161m./zbeta'
stop

# The fixture history has `sudo openvpn ...` in it.
start
send "sudo "
checkesc "the command after a precommand is highlighted too" '38;2;166;227;161mopenvpn'
checkesc "and the precommand itself is underlined" $'\e[4m\e[38;2;166;227;161msudo'
stop

# Tab rebuilds ZLS_COLORS from the list-colors style and leaves it that way,
# which stripped the row rules from every listing after the first completion.
start
send "cat ./zh"
send Tab
send C-c
send "sudo "
checkesc "row colours survive a Tab completion" '38;2;166;227;161mopenvpn'
stop

extra_env='ZHIMMER_TEST_NO_ROW_COLORS=1'
start
send "git"
checks    "with row-colors off the rows are still drawn" 'git status --short --branch'
refuteesc "but carry no accent"                          '38;2;166;227;161mgit'
stop
extra_env=''


print "\n-- the drop-down --"
start
send "ls ./zmany/f1"
checks "the rows are drawn"          './zmany/f10'
checks "under a group header"        ' file '
# Everything here is POSTDISPLAY and region_highlight, so complist never runs
# and there is no interactive mode to enter -- which is the whole point.
refutes "and complist never gets involved" 'interactive:'
stop

start
send "ls ./zmany/f1"
send Down
checksel "Down marks the first row"  './zmany/f1'
send Down
checksel "and moves to the second"   './zmany/f10'
send Up
checksel "Up moves back"             './zmany/f1'
# The list must not shift as the selection moves: nothing is inserted or
# removed above it, so the header cannot move. That shifting row is what the
# complist path costs to keep filtering alive.
send Down Down Down
refutes "still no interactive row after moving" 'interactive:'
stop

# Filtering needs no mode: typing already recomputes the list, so narrowing an
# open menu is the same code path as narrowing before one was opened.
start
send "ls ./zmany/f1"
send Down
send "4"
checks  "typing narrows the open menu"     './zmany/f14'
refutes "dropping what no longer matches"  './zmany/f10 '
refutes "and without entering any mode"    'interactive:'
stop

start
send "ls ./zmany/f10"
send Down
send Enter
check "Enter takes the highlighted row into the line" 'ls ./zmany/f10'
stop

# The accept keys read the tracked ghost, not the whole of POSTDISPLAY -- which
# also holds every row of the menu. Reading that put the header rule and all
# its rows into BUFFER, and because the rows were still on screen underneath it
# looked exactly like the menu being open, one Enter away from running.
start
send "sudo openv"
send C-e
check   "Ctrl+E takes the ghost and nothing else" 'sudo openvpn ~/VPNs/no'
refutes "no header rule ends up in the line"      '─────'
stop

start
send "ls ./zmany/f1"
send Down
send C-e
refute "and not with a row selected either" '────'
stop


print "\n-- searching (Ctrl+R) --"
# The same ranking with the anchor moved: `openvpn` is not the start of any
# remembered line, so only a substring search finds it.
start
send "openvpn"
refutes "a prefix search finds nothing mid-line" ' history '
send C-r
checks  "Ctrl+R turns it into a search"          ' search '
checks  "and finds the line by its middle"       'sudo openvpn ~/VPNs/no'
# A row is always selected in a search, so Enter always has one to take.
checksel "with a row already selected"           'sudo openvpn ~/VPNs/no'
send C-r
checksel "and Ctrl+R again steps to the next match" 'sudo openvpn ~/VPNs/universal.ovpn'
stop

# On an empty line a search is "everything, best first" -- min-chars is about
# not guessing two characters into a line, and a search is the question itself.
start
send C-r
checks   "Ctrl+R on an empty line opens on the whole history" ' search '
# In history order, newest first -- not the drop-down's frecency order. The
# newest line in the fixture wins even though `git status --short --branch` is
# the only one in it that was run twice.
checksel "newest first, not most-run first" "grep -rn"
stop

# Deep enough to scroll: a search is meant to be walked down, so it holds
# search-suggestions rows and the window moves under them rather than the list
# being clamped to the screen.
# Twelve rows of terminal is a window of eight, and the fixture deduplicates to
# eight rows under a header -- so the last of them cannot be on screen when the
# search opens, and walking to it is the proof that the window moves.
start 80 12
send C-r
send Down Down Down Down Down Down Down
checksel "walking down a search reaches a row that did not fit" 'ls -la'
refutes  "and the window scrolled its header off the top"       ' search '
stop

# With nothing to show the mode still has to be visible: it changes what Enter
# does, and without the header there is no sign it is on.
start
send C-r
send "zzqqxx"
checks "a search with no matches says so" 'search: no match'
stop

# Ctrl+C never reaches line-finish, so the mode is cleared at line-init too --
# without that the next line was still searching. `clear` first, because the
# rows the abandoned search drew are still in the scrollback.
start
send C-r
send "openvpn"
send C-c
send "clear"
send Enter
send "sudo openv"
checks  "an abandoned search does not leak into the next line" ' history '
refutes "which is no longer a search"                          ' search '
stop

# Enter takes the row, and the line is then an ordinary line again.
start
send C-r
send "universal"
send Enter
check "Enter takes the row a search is on" 'sudo openvpn ~/VPNs/universal.ovpn'
stop


rm -rf $fh
print ""
if (( fails )); then
  print "$fails test(s) failed"
  exit 1
fi
print "all screen tests passed"
