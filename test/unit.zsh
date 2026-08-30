#!/usr/bin/env zsh
# Unit tests: the parts that are a function of their arguments, with no
# terminal involved.
#
# test/screen.zsh drives a real ZLE through tmux and takes half an hour. That
# is the right tool for a question about drawing or keys, and the wrong one for
# a ranking bug: `_zhimmer_hist_rank` reading a history line with a stray `[` in
# it shipped as an `invalid subscript` at the prompt, and the whole of what was
# wrong fits in the four lines it takes to assert here. This file runs in
# milliseconds, so it can be run on every save.
#
# The plugin file itself is deliberately not sourced -- it registers ZLE
# widgets, and there is no line editor here. The libraries define functions and
# set defaults at source time and nothing else, which is what makes this
# possible at all.
#
# usage: zsh test/unit.zsh

emulate -L zsh
local root=${0:A:h:h}
integer fails=0 checks=0 finished=0

# A zsh arithmetic error is fatal, not catchable: the `invalid subscript` this
# file exists to catch kills the shell where it happens rather than failing an
# assertion. Without this the run would end mid-way looking like a short pass.
TRAPEXIT() {
  # A $( ) forks, and the fork exits -- which runs this trap inside it and
  # prints the banner into whatever the substitution was capturing. The first
  # test to use one came back with the abort message inside its temp path.
  (( ZSH_SUBSHELL )) && return
  (( finished )) && return
  print "\n  ABORTED -- the suite exited before finishing; see the error above"
}

source $root/lib/theme.zsh
source $root/lib/complete.zsh
source $root/lib/ghost.zsh
source $root/lib/expand.zsh
source $root/lib/prompt.zsh
source $root/lib/zlemenu.zsh
source $root/sources/history.zsh
source $root/sources/alias.zsh
source $root/sources/command.zsh

is() {  # is <label> <got> <want>
  (( checks++ ))
  if [[ $2 == "$3" ]]; then
    print "  ok    $1"
  else
    print "  FAIL  $1"
    print "        got:  ${(qqq)2}"
    print "        want: ${(qqq)3}"
    (( fails++ ))
  fi
}

holds() {  # holds <label> <command>...   -- the command must succeed
  (( checks++ ))
  if "${@[2,-1]}"; then print "  ok    $1"; else print "  FAIL  $1"; (( fails++ )); fi
}

matches() {  # matches <label> <string> <pattern>
  (( checks++ ))
  if [[ $2 == ${~3} ]]; then
    print "  ok    $1"
  else
    print "  FAIL  $1"
    print "        ${(qqq)2} does not match ${(qqq)3}"
    (( fails++ ))
  fi
}

fails_() {  # fails_ <label> <command>...  -- the command must not succeed
  (( checks++ ))
  if "${@[2,-1]}"; then print "  FAIL  $1"; (( fails++ )); else print "  ok    $1"; fi
}

# ---------------------------------------------------------------- history ---
#
# A private history, so this reads a fixture rather than whatever the machine
# running the tests happens to have done today. Oldest first.
print '\n== history ranking =='
fc -p /dev/null 500 500
for c in \
  'git commit -m x' 'git status' 'git push' 'git status' \
  'lar[' 'echo (unclosed' 'foo one' $'foo\nbar' 'git status'
do print -s -- $c; done

local -a reply

# Three `git status` against one of everything else, and the newest entry as
# well: no weighting of count against recency can put anything else first.
_zhimmer_hist_q=; _zhimmer_hist_rank 'git ' 5
is "the most frequent recent match ranks first" "$reply[1]" 'git status'

_zhimmer_hist_q=; _zhimmer_hist_rank 'git ' 2
is "the limit is respected" $#reply 2

# What is already typed is not a suggestion.
_zhimmer_hist_q=; _zhimmer_hist_rank 'git status' 5
is "the query itself is not offered back" "${reply[(r)git status]}" ''

# A row with a newline in it cannot be drawn, so it is skipped rather than
# offered and mangled. `foo one` is the only other match, so an empty-handed
# skip and a working one look different here.
_zhimmer_hist_q=; _zhimmer_hist_rank 'foo' 5
is "a multi-line entry is skipped, not drawn" "${(j:|:)reply}" 'foo one'

# The regression this file was written for. A match is a key in the ranking's
# hashes and was read back as one inside $(( )), where the subscript is parsed
# as arithmetic -- so a stray ( or [ in a history line was an invalid subscript
# that took the whole list down, not just its own row.
_zhimmer_hist_q=; _zhimmer_hist_rank 'lar' 5
is "a match with an unbalanced bracket still ranks" "$reply[1]" 'lar['
_zhimmer_hist_q=; _zhimmer_hist_rank 'echo (' 5
is "a match with an unbalanced paren still ranks" "$reply[1]" 'echo (unclosed'

# Typing extends the query and the cache narrows what it already found, rather
# than searching again. The two paths have to agree, or a suggestion changes
# under the cursor for no reason the typist can see.
_zhimmer_hist_q=; _zhimmer_hist_rank 'g' 5
_zhimmer_hist_rank 'git ' 5           # warm: narrowed from the line above
local warm="${(j:|:)reply}"
_zhimmer_hist_q=; _zhimmer_hist_rank 'git ' 5
is "narrowing the cache agrees with a cold search" "$warm" "${(j:|:)reply}"

_zhimmer_hist_q=; _zhimmer_hist_rank '' 5
is "an empty query matches nothing" $#reply 0

_zhimmer_hist_q=; _zhimmer_hist_rank 'zzz-no-such-command' 5
is "an unmatched query comes back empty" $#reply 0

# ------------------------------------------------------- searching (Ctrl+R) ---
#
# The same match set with two things changed: the query matches anywhere in a
# line rather than only at its start, and the answer comes back in history
# order instead of frecency order. Everything else -- the limit, the skips, the
# narrowing cache -- is shared.
_zhimmer_hist_q=; _zhimmer_hist_rank 'commit' 5
is "a prefix search does not find a word in the middle" $#reply 0
_zhimmer_hist_q=; _zhimmer_hist_rank 'commit' 5 1
is "and a substring search does"                 "$reply[1]" 'git commit -m x'

# An empty prefix is not a query; an empty search is "the history, newest
# first", which is what Ctrl+R on an empty line has to answer.
_zhimmer_hist_q=; _zhimmer_hist_rank '' 5
is "an empty query matches nothing"              $#reply 0
_zhimmer_hist_q=; _zhimmer_hist_rank '' 5 1
is "but an empty search returns the whole history" "$reply[1]" 'foo one'

# Newest first, and each line once. `git status` was run three times and comes
# back as one row -- a history is mostly repeats, and four screens of the same
# line is not a search result. The multi-line entry is the newest of all and is
# still skipped, since a row with a newline in it cannot be drawn.
is "newest first, with duplicates collapsed" \
   "${(j:|:)reply}" 'foo one|echo (unclosed|lar[|git status|git push'

# Which is a different answer from the drop-down's, and has to be: frecency
# puts a line you type every day above the one you ran a minute ago, and in a
# search the second is the one you are looking for.
#
# Two pushes, not one. $history lags a push: the entry just added is held as
# the current line and does not appear in the parameter until another follows
# it. In a real shell that is right -- at the prompt, everything up to the
# previous command is there -- but in a test it silently means the line you
# just wrote is not the one being ranked.
print -s -- 'git worktree add ../wt'
print -s -- 'zzz flush'
_zhimmer_hist_q=; _zhimmer_hist_rank 'git' 5
is "the drop-down still ranks by frecency"        "$reply[1]" 'git status'
_zhimmer_hist_q=; _zhimmer_hist_rank 'git' 5 1
is "and a search by recency"                      "$reply[1]" 'git worktree add ../wt'

# A row with a newline in it cannot be drawn, in either mode.
_zhimmer_hist_q=; _zhimmer_hist_rank 'foo' 5 1
is "a multi-line entry is skipped in a search too" "${(j:|:)reply}" 'foo one'

# The pattern is built in a parameter now, so the (b) quoting has to survive
# being re-read with $~ -- otherwise a `[` typed into a search is a character
# class rather than the character it plainly is.
_zhimmer_hist_q=; _zhimmer_hist_rank 'ar[' 5 1
is "a bracket in a search is a character, not a class" "$reply[1]" 'lar['

# The cache narrows the previous match set instead of searching again, and the
# two modes must not narrow each other: lines *containing* `git` are not a
# subset of lines *starting with* it, so a mode change has to search afresh.
_zhimmer_hist_q=; _zhimmer_hist_rank 'git' 5        # cold, prefix
_zhimmer_hist_rank 'git c' 5 1                       # same prefix, other mode
local switched="${(j:|:)reply}"
_zhimmer_hist_q=; _zhimmer_hist_rank 'git c' 5 1     # cold, substring
is "switching mode re-searches rather than narrowing" \
   "$switched" "${(j:|:)reply}"

# And within one mode it still narrows, agreeing with a cold search.
_zhimmer_hist_q=; _zhimmer_hist_rank 'com' 5 1
_zhimmer_hist_rank 'commit' 5 1
local swarm="${(j:|:)reply}"
_zhimmer_hist_q=; _zhimmer_hist_rank 'commit' 5 1
is "narrowing a search agrees with a cold one" "$swarm" "${(j:|:)reply}"

# -------------------------------------------------------------------- rows ---
#
# Rows are padded to a fixed width so the selection reads as a solid bar, and
# truncated so nothing wraps onto a second line and puts the layout out of step
# with the menu. Both are measured in columns: `~/文書` is fewer characters
# than it is columns, and counting characters let a CJK path run past the edge.
print '\n== row layout =='
local REPLY

COLUMNS=40
_zhimmer_row 'short'
is "a row is padded to the full width" ${(m)#REPLY} 39
is "and indented by two" "${REPLY[1,7]}" '  short'

_zhimmer_row "${(l:80::x:):-}"
is "a long row is cut to the width" ${(m)#REPLY} 39
matches "and ends in an ellipsis" "$REPLY" '*…*'

# Two double-width characters per glyph-looking unit, so a row that fits by
# character count does not fit by column count.
_zhimmer_row '~/文書/プロジェクト/notes.txt'
is "a CJK row is cut by columns, not characters" ${(m)#REPLY} 39
_zhimmer_row '🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀'
is "an emoji row is cut by columns too" ${(m)#REPLY} 39

# A cut that lands inside a double-width character keeps the whole character,
# so the ellipsis has to be budgeted for or the row comes back one column wide.
COLUMNS=13
_zhimmer_row '文文文文文文文文文文'
is "a cut inside a wide character does not overshoot" ${(m)#REPLY} 12

COLUMNS=3
_zhimmer_row 'x'
is "an absurdly narrow terminal clamps rather than going negative" ${(m)#REPLY} 10

# ----------------------------------------------------------------- headers ---
print '\n== group headers =='
COLUMNS=40
_zhimmer_header history
is "the rule fills what the name leaves" ${#${REPLY//[^─]/}} 29
matches "and the name is in it" "$REPLY" '*history*'

COLUMNS=5
_zhimmer_header history
is "a name wider than the terminal draws no rule" ${#${REPLY//[^─]/}} 0

# --------------------------------------------------------- command position ---
#
# Where a command alias may expand. Not just the start of the line: `make; gs`
# and `ls | gs` are command positions too.
print '\n== command position =='
holds  "the start of the line is a command position"  _zhimmer_command_pos ''
holds  "so is nothing but whitespace"                 _zhimmer_command_pos '   '
holds  "after a pipe"                                 _zhimmer_command_pos 'ls | '
holds  "after a semicolon"                            _zhimmer_command_pos 'make; '
holds  "after &&"                                     _zhimmer_command_pos 'foo && '
holds  "inside a subshell"                            _zhimmer_command_pos '( '
fails_ "an argument is not"                           _zhimmer_command_pos 'git '
# The test is on the last non-whitespace character, so a delimiter earlier in
# the line does not make everything after it look like a command.
fails_ "and neither is an argument after a pipe"      _zhimmer_command_pos 'echo a| b '

# --------------------------------------------------------- alias expansion ---
print '\n== alias expansion =='
zstyle -d ':zhimmer:*'
aliases=()
galiases=()
aliases[gs]='git status -s'
aliases[gc]='git commit'
aliases[gcm]='gc -m'
aliases[ls]='ls --color'
galiases[G]='| grep'
local bracket='a[1]'
aliases[$bracket]='echo bracket'

LBUFFER='gs'
holds "a command alias in command position expands" _zhimmer_expand_alias
is    "  to what it stands for" "$LBUFFER" 'git status -s'

LBUFFER='echo gs'
fails_ "an alias in argument position does not expand" _zhimmer_expand_alias
is     "  and the line is untouched" "$LBUFFER" 'echo gs'

LBUFFER='ls | gs'
holds "an alias after a pipe expands" _zhimmer_expand_alias
is    "  in place, keeping what came before" "$LBUFFER" 'ls | git status -s'

LBUFFER='ls G'
holds "a global alias expands in argument position" _zhimmer_expand_alias
is    "  where a command alias would not" "$LBUFFER" 'ls | grep'

LBUFFER='gcm'
holds "a chain resolves" _zhimmer_expand_alias
is    "  one alias at a time" "$LBUFFER" 'git commit -m'

# zsh's own rule: an alias is never re-expanded inside its own expansion.
LBUFFER='ls'
holds "a self-referential alias expands" _zhimmer_expand_alias
is    "  exactly once" "$LBUFFER" 'ls --color'

# The word is taken off the line by length, not as a pattern: `${LBUFFER%$word}`
# reads `a[1]` as a character class, matches nothing, strips nothing, and leaves
# the alias sitting in front of its own expansion.
LBUFFER='a[1]'
holds "an alias whose name looks like a glob expands" _zhimmer_expand_alias
is    "  without duplicating itself into the line" "$LBUFFER" 'echo bracket'

LBUFFER='nosuchalias'
fails_ "a word that is not an alias is left alone" _zhimmer_expand_alias

zstyle ':zhimmer:*' expand-alias no
LBUFFER='gs'
fails_ "and nothing expands with the style off" _zhimmer_expand_alias
is     "  leaving the line as typed" "$LBUFFER" 'gs'
zstyle -d ':zhimmer:*'

# ------------------------------------------------------------------ picking ---
print '\n== sort and cut =='
_zhimmer_pick 5 c a b
is "candidates come back sorted" "${(j:|:)reply}" 'a|b|c'
_zhimmer_pick 2 c a b
is "sorted before the cut, not after" "${(j:|:)reply}" 'a|b'
fails_ "an empty candidate list reports so" _zhimmer_pick 5

# -------------------------------------------------------------------- ghost ---
#
# Every group offers its top row as it is drawn and the rank decides between
# them, so which source the ghost comes from cannot depend on which one the
# `sources` style happens to name first.
print '\n== ghost precedence =='
_reset_ghost() { _zhimmer_top=; _zhimmer_top_rank=0 }

_reset_ghost
_zhimmer_offer_ghost command 'git'
_zhimmer_offer_ghost history 'git push --force-with-lease'
is "history outranks a command offered before it" "$_zhimmer_top" 'git push --force-with-lease'

_reset_ghost
_zhimmer_offer_ghost history 'git push --force-with-lease'
_zhimmer_offer_ghost command 'git'
is "and is not displaced by one offered after" "$_zhimmer_top" 'git push --force-with-lease'

_reset_ghost
_zhimmer_offer_ghost file './zalpha'
_zhimmer_offer_ghost command 'zcat'
is "between equals the first offered keeps it" "$_zhimmer_top" './zalpha'

_reset_ghost
_zhimmer_offer_ghost zoxide '/home/u/src'
is "a source with no rank of its own still offers" "$_zhimmer_top" '/home/u/src'
_zhimmer_offer_ghost history 'zoxide add .'
is "  and history still outranks it" "$_zhimmer_top" 'zoxide add .'

# ------------------------------------------------------------ source parsers ---
#
# Each source that has to read something keeps the reading and the parsing
# apart, so the parsing can be checked against a fixture here rather than
# against whatever the machine running the tests happens to have installed.
print '\n== source parsers =='
source $root/sources/ssh-host.zsh
source $root/sources/git-branch.zsh
source $root/sources/git-file.zsh
source $root/sources/make.zsh
source $root/sources/npm-script.zsh

_zhimmer_ssh_config_hosts 'Host web1 web2
  Host bastion
Host *.internal
Host prod-? !nope
# a comment
Host quoted-one'
is "ssh config: names from Host lines, indented ones included" "${(j:,:)reply}" 'web1,web2,bastion,quoted-one'

_zhimmer_known_hosts 'web1,192.168.1.5 ssh-rsa AAAA
|1|aGFzaGVk=|bm90aGluZw== ssh-rsa BBBB
@cert-authority ca.example.com ssh-rsa CCCC
[alt.example.com]:2222 ssh-ed25519 DDDD
# a comment'
# The exact list is the assertion: the hashed entry is absent from it, which
# is what matters -- a hashed known_hosts cannot be read back, and a row of
# base64 is worse than no row at all.
is "known_hosts: comma lists split, markers and ports handled, hashes dropped" "${(j:,:)reply}" 'web1,192.168.1.5,ca.example.com,alt.example.com'

_zhimmer_git_refs 'refs/heads/main
refs/heads/feature/x
refs/remotes/origin/main
refs/remotes/origin/HEAD
refs/remotes/upstream/main'
is "git refs: local heads"            "${(j:,:)_zhimmer_git_heads}"     'main,feature/x'
is "git refs: remote names, once each" "${(j:,:)_zhimmer_git_remotes}"   'origin,upstream'
# origin/HEAD is a symbolic ref to the branch beside it, not a branch of its
# own, and its absence from this list is the assertion.
is "git refs: remote-tracking branches, without the remote HEAD" "${(j:,:)_zhimmer_git_rbranches}" 'origin/main,upstream/main'

_zhimmer_git_status_paths ' M lib/theme.zsh
?? test/unit.zsh
R  old.txt -> new.txt
 D gone.txt'
is "git status: the path, not the status columns" "${(j:,:)reply}" 'lib/theme.zsh,test/unit.zsh,new.txt,gone.txt'

_zhimmer_make_targets 'CC := gcc
VPATH = src
.PHONY: all clean
all: build test
build:
	$(CC) -o x
%.o: %.c
	touch $@
test-unit: build
clean:'
is "make: targets, not assignments, recipes or pattern rules" "${(j:,:)reply}" 'all,build,test-unit,clean'

_zhimmer_npm_scripts '{
  "name": "x",
  "scripts": {
    "build": "tsc -p .",
    "test": "jest --a,b",
    "dev": "vite"
  },
  "devDependencies": { "vite": "^5" }
}'
# Two things at once: the comma inside the test command did not split a key
# out of a value, and the block ended at its own closing brace rather than
# running on into devDependencies.
is "npm: script names only, values and later objects left alone" "${(j:,:)reply}" 'build,test,dev'

fails_ "a package.json with no scripts reports so" _zhimmer_npm_scripts '{ "name": "x" }'
fails_ "and a makefile with no targets does too"   _zhimmer_make_targets 'CC := gcc'

# ------------------------------------------------------ an empty word is not ---
#
# A source that keys only off the word being typed needs a word. With none, the
# alias source matched every alias and the command source every executable on
# $PATH -- and the top of that went on the line as a ghost. Two spaces at a
# stock prompt was enough to do it.
#
# The sources call compadd, which exists only inside a completion widget, so
# what each would have drawn is recorded instead of drawn. The positive cases
# are here for that reason: without them a stub that never fires would make
# every "draws nothing" pass for the wrong reason.
print '\n== an empty word is not a query =='
_zhimmer_addwords() { typeset -g _zhimmer_drawn=$2 }
_zhimmer_addgroup() { typeset -g _zhimmer_drawn=$2 }

_probe() {  # _probe <source> <CURRENT> <PREFIX> <LBUFFER>
  typeset -g _zhimmer_drawn=
  CURRENT=$2 PREFIX=$3 LBUFFER=$4
  _zhimmer_source_$1 10
  return 0
}

_probe alias 1 '' ''
is "an empty word draws no aliases" "$_zhimmer_drawn" ''
_probe alias 1 '  ' '  '
is "and neither does a word of whitespace" "$_zhimmer_drawn" ''
_probe alias 1 g g
is "but a word that was typed does" "$_zhimmer_drawn" 'alias'

_probe command 1 '' ''
is "an empty word draws no commands" "$_zhimmer_drawn" ''
_probe command 1 ls ls
is "a typed one does" "$_zhimmer_drawn" 'command'

_probe history 1 '' '   '
is "a line of whitespace ranks no history" "$_zhimmer_drawn" ''
_probe history 1 '' 'git '
is "a real prefix does" "$_zhimmer_drawn" 'history'

# The same guard, at the level the ranking itself works, so zhimmer-doctor and
# any future caller get the same answer.
_zhimmer_hist_q=; _zhimmer_hist_rank '   ' 5
is "the ranking treats whitespace as no query at all" $#reply 0

# ----------------------------------------------- features that switch off ---
#
# Every yes/no setting has to actually gate something. A style nobody reads is
# worse than no style: it reads as a promise in the README.
print '\n== features switch off =='
zstyle -d ':zhimmer:*'
region_highlight=()
_zhimmer_top='git status --short'
BUFFER=git LBUFFER=git RBUFFER= POSTDISPLAY=

_zhimmer_zle_reset
_zhimmer_zle_show
is "ghost text is drawn by default" "$POSTDISPLAY" ' status --short'
# What the accept keys read. It is tracked apart from POSTDISPLAY, which also
# holds every row of the menu: reading the whole of that put the header rule
# and its rows into BUFFER, looking on screen exactly like the menu still being
# open and one Enter away from running.
is "and is tracked on its own, not read back out of POSTDISPLAY" \
   "$_zhimmer_zghost" ' status --short'

zstyle ':zhimmer:*' ghost-text no
_zhimmer_zle_show
is "and not at all with ghost-text no" "$POSTDISPLAY" ''
is "with nothing left for the accept keys to take" "$_zhimmer_zghost" ''
zstyle -d ':zhimmer:*'

# --------------------------------------------------------------- settings ---
print '\n== settings =='
zstyle -d ':zhimmer:*'
# That the table is here at all is half the point: it used to live in the
# plugin file, out of reach of anything sourcing the libraries on their own,
# and every setting then read as empty -- which a comparison against the table
# would have agreed with, since both sides were empty.
is "the defaults table is reachable from the libraries" $(( $#ZHIMMER_DEFAULTS > 0 )) 1
_zhimmer_cfg max-suggestions
is "an unset style falls back to the default table" "$REPLY" "${ZHIMMER_DEFAULTS[max-suggestions]}"
zstyle ':zhimmer:*' max-suggestions 3
_zhimmer_cfg max-suggestions
is "and a style that is set wins" "$REPLY" 3
zstyle -d ':zhimmer:*'

local w
for w in yes true 1 on; do
  zstyle ':zhimmer:*' ghost-text $w
  holds "'$w' reads as true" _zhimmer_bool ghost-text
done
for w in no false 0 off; do
  zstyle ':zhimmer:*' ghost-text $w
  fails_ "'$w' reads as false" _zhimmer_bool ghost-text
done
zstyle -d ':zhimmer:*'

print
print "== prompt: status symbols =="
# Porcelain v1 two-column codes, one fixture per symbol. The parser is a pure
# function of this text, which is the whole reason it is split from the fork.
_zhimmer_prompt_symbols '## main'
is   "a clean tree has no symbols" "$REPLY" ""
fails_ "and says so by returning non-zero" _zhimmer_prompt_symbols '## main'

_zhimmer_prompt_symbols '## main
?? new.txt'
is   "untracked" "$REPLY" "?"

_zhimmer_prompt_symbols '## main
 M lib/prompt.zsh'
is   "modified in the worktree" "$REPLY" "!"

_zhimmer_prompt_symbols '## main
M  lib/prompt.zsh'
is   "staged" "$REPLY" "+"

_zhimmer_prompt_symbols '## main
MM lib/prompt.zsh'
is   "staged and modified at once, both reported" "$REPLY" "!+"

_zhimmer_prompt_symbols '## main
 D gone.txt'
is   "deleted" "$REPLY" "✘"

_zhimmer_prompt_symbols '## main
R  old.txt -> new.txt'
is   "renamed" "$REPLY" "»"

_zhimmer_prompt_symbols '## main
UU conflicted.txt'
is   "unmerged" "$REPLY" "="

# An ignored line only appears with --ignored, but costs nothing to be right about.
_zhimmer_prompt_symbols '## main
!! build/out.o'
is   "ignored files are not dirt" "$REPLY" ""

print
print "== prompt: upstream distance =="
_zhimmer_prompt_symbols '## main...origin/main [ahead 3]'
is   "ahead carries its count" "$REPLY" "⇡3"

_zhimmer_prompt_symbols '## main...origin/main [behind 4]'
is   "behind carries its count" "$REPLY" "⇣4"

_zhimmer_prompt_symbols '## main...origin/main [ahead 2, behind 1]'
is   "diverged is both arrows, not one glyph" "$REPLY" "⇡2⇣1"

# No upstream is not the same as being level with one.
_zhimmer_prompt_symbols '## feat/new-thing'
is   "a branch with no upstream shows no arrows" "$REPLY" ""

_zhimmer_prompt_symbols '## main...origin/main [ahead 1]
 M a.txt
?? b.txt'
is   "symbols come before arrows, in table order" "$REPLY" "!?⇡1"

print
print "== prompt: reading HEAD without forking =="
_pdir=$(mktemp -d)
mkdir -p $_pdir/repo/.git $_pdir/sub
_pwd_was=$PWD

print 'ref: refs/heads/master' > $_pdir/repo/.git/HEAD
cd $_pdir/repo
_zhimmer_prompt_branch
is   "a branch name is read straight out of .git/HEAD" "$REPLY" "master"

# The one that a greedy ${head##*/} gets wrong, silently, on exactly the
# branches whose names carry the most information.
print 'ref: refs/heads/feat/menu' > $_pdir/repo/.git/HEAD
_zhimmer_prompt_branch
is   "a branch with a slash in it keeps both halves" "$REPLY" "feat/menu"

print '9f04a1c8e2b3d5f60718293a4b5c6d7e8f901234' > $_pdir/repo/.git/HEAD
_zhimmer_prompt_branch
is   "a detached HEAD reads as the short sha" "$REPLY" "9f04a1c"

# A worktree or submodule has .git as a *file* naming the real directory.
print 'ref: refs/heads/linked' > $_pdir/repo/.git/HEAD
print "gitdir: $_pdir/repo/.git" > $_pdir/sub/.git
cd $_pdir/sub
_zhimmer_prompt_branch
is   "a .git file is followed to the real gitdir" "$REPLY" "linked"

cd $_pdir
holds "and a directory outside any repository has no branch" \
  eval '_zhimmer_prompt_branch; [[ -z $REPLY ]]'
cd $_pwd_was
rm -rf $_pdir

print
print "== prompt: the switch =="
is   "the prompt is off unless asked for" "${ZHIMMER_DEFAULTS[prompt]}" "no"
_saved_prompt=$PROMPT
PROMPT='original% '
zhimmer-prompt-on
holds "turning it on records that it is on" eval '(( _zhimmer_prompt_on ))'
zhimmer-prompt-off
is   "turning it off puts the original prompt back verbatim" "$PROMPT" 'original% '
PROMPT=$_saved_prompt

print
print "== row colours =="
# Two notations for one palette. ZLS_COLORS speaks SGR escapes and is what
# colours Tab's selected row; region_highlight speaks its own words and is what
# colours zhimmer's own rows. The palette is written in hex once, and each of
# these converts it.
_zhimmer_sgr '#a6e3a1'; is "hex converts to a truecolor SGR" "$REPLY" "38;2;166;227;161"
_zhimmer_sgr '#000000'; is "and the dark end of it"          "$REPLY" "38;2;0;0;0"
_zhimmer_sgr '#ffffff'; is "and the light end"               "$REPLY" "38;2;255;255;255"
_zhimmer_sgr '48;2;69;71;90;1'; is "an SGR is passed through untouched" "48;2;69;71;90;1" "$REPLY"

_zhimmer_hl '#fab387'; is "hex converts to a highlight spec" "$REPLY" "fg=#fab387"
# `sudo openvpn ...` puts the command in second place, and the precommand is
# underlined to match how zsh-syntax-highlighting marks one on the line above.
# The SGR prefix the ZLS_COLORS spelling carries has to survive the conversion.
_zhimmer_hl '4;#a6e3a1'; is "and an SGR prefix becomes a word" "$REPLY" "fg=#a6e3a1,underline"
_zhimmer_hl '1;4;#a6e3a1'; is "more than one of them"         "$REPLY" "fg=#a6e3a1,bold,underline"
fails_ "a value with no hex in it is declined" _zhimmer_hl '48;2;1;2;3'

# The selection bar is one colour said twice -- hex for region_highlight, SGR
# for complist -- so the SGR is derived rather than written out again.
_zhimmer_sgr $ZHIMMER_SELECT_BG
is "the two spellings of the selection bar agree" "$ZHIMMER_SELECT" "48;${REPLY#38;};1"

# A source names two different strings: the group (`zhimmer-git-branch`, which
# row colours are keyed by) and the header label (`branch`, which header
# colours are keyed by). For six of the eleven sources those are not the same
# word, and a row looked up by its label came back with no colour at all --
# silently, because a missing hash key is an empty string rather than an error.
# This is the check that would have said so.
# Read out of the sources rather than listed here, so a source added without a
# colour is caught rather than described.
_pairs=(); _w=()
for _l in ${(f)"$(rg -oN '_zhimmer_add(group|words) [^ ]+ [^ ]+' $root/sources/*.zsh)"}; do
  _w=( ${(z)_l} )
  # git-branch builds both strings from a variable -- one call site, two groups
  # -- and a grep cannot resolve that, so it is the one named here.
  if [[ $_w[2] == *'$'* ]]; then
    _pairs+=( zhimmer-git-branch branch zhimmer-git-remote remote )
  else
    _pairs+=( $_w[2] $_w[3] )
  fi
done
integer _i
_groups=()
for (( _i = 1; _i <= $#_pairs; _i += 2 )); do
  _groups+=( $_pairs[_i] )
  holds "row colour for group $_pairs[_i]" \
        eval "[[ -n \${ZHIMMER_ROW_COLORS[${_pairs[_i]#zhimmer-}]} ]]"
  holds "header colour for label $_pairs[_i+1]" \
        eval "[[ -n \${ZHIMMER_COLORS[$_pairs[_i+1]]} ]]"
done
# The other direction: a colour nobody looks up is a colour that has been
# renamed out from under its source. Counted over *distinct* groups -- the
# history source has two call sites, one per header label, and they share one
# group and so one row colour.
_groups=( ${(u)_groups} )
is "every row colour belongs to a source" "$#ZHIMMER_ROW_COLORS" "$#_groups"

# The row accent itself: the first token, painted by offset. `sudo openvpn` has
# the word you were looking for in second place, so it gets two ranges -- the
# precommand underlined, then the command it runs.
region_highlight=()
_zhimmer_zle_token 0 'sudo openvpn ~/vpn.ovpn' zhimmer-history
is "a precommand row paints two ranges"  "$#region_highlight" "2"
matches "the precommand is underlined"   "$region_highlight[1]" "2 6 fg=#a6e3a1,underline*"
matches "and the command after it is not" "$region_highlight[2]" "7 14 fg=#a6e3a1,*"

region_highlight=()
_zhimmer_zle_token 0 'git status -s' zhimmer-history
is "an ordinary row paints one"          "$#region_highlight" "1"
matches "over its first token only"      "$region_highlight[1]" "2 5 fg=#a6e3a1,*"

# Keyed by group, not by label. `branch` is the label git-branch draws its
# header under and is not a key in ZHIMMER_ROW_COLORS at all.
region_highlight=()
_zhimmer_zle_token 0 'feat/menu' zhimmer-git-branch
is "a branch row is coloured under its group" "$#region_highlight" "1"
region_highlight=()
_zhimmer_zle_token 0 'feat/menu' branch
is "and a group with no colour paints nothing" "$#region_highlight" "0"

print "== zle menu: the scrolling window =="
# Which rows are on screen, given where the selection is. Pure, so the scroll
# behaviour is pinned here rather than by counting rows on a terminal.
win() {  # win <total> <sel> <height> <first> -> "first last"
  local -a reply
  _zhimmer_zle_window $1 $2 $3 $4
  print -r -- "$reply[1] $reply[2]"
}
is "a list that fits is shown whole"            "$(win 5 0 10 1)"   "1 5"
is "and is not scrolled by a selection"         "$(win 5 4 10 1)"   "1 5"
is "a long list starts at the top"              "$(win 50 1 10 1)"  "1 10"
# The window only moves when the selection would leave it -- otherwise the list
# scrolls under a cursor that has not reached the edge yet.
is "a selection inside the window does not scroll it" "$(win 50 5 10 1)"  "1 10"
is "one below the window scrolls by exactly one"      "$(win 50 11 10 1)" "2 11"
is "and one above it scrolls back"                    "$(win 50 3 10 20)" "3 12"
is "the last row sits at the bottom"                  "$(win 50 50 10 1)" "41 50"
is "the window cannot run past the end"               "$(win 50 0 10 45)" "41 50"
is "a height under one is still one row"              "$(win 50 1 0 1)"   "1 1"

print
print "== zle menu: selectable rows =="
# Headers are rows on screen but are never selectable, so movement steps over
# them -- otherwise Down would land on ' history' and Enter would take it.
_zhimmer_zle_reset
_zhimmer_zle_header history
_zhimmer_zle_match 'echo one' history 'echo one'
_zhimmer_zle_match 'echo two' history 'echo two'
_zhimmer_zle_header file
_zhimmer_zle_match './a' file 'cat ./a'
is   "rows and headers are all drawn"          "$#_zhimmer_zrow"      "5"
_zhimmer_zle_next 0 1;  is "the first match is found past the header"  "$REPLY" "2"
_zhimmer_zle_next 2 1;  is "and the next one after it"                 "$REPLY" "3"
_zhimmer_zle_next 3 1;  is "stepping over the second header"           "$REPLY" "5"
_zhimmer_zle_next 5 -1; is "backwards skips the header too"            "$REPLY" "3"
# The ends wrap, so a long history list rotates rather than stopping dead.
_zhimmer_zle_next 5 1;  is "past the last row it wraps to the first"   "$REPLY" "2"
_zhimmer_zle_next 2 -1; is "and back off the first row to the last"    "$REPLY" "5"
# Which is also how Up opens the menu: from nothing, one step back is the end.
_zhimmer_zle_next 0 1;  is "from nothing, Down takes the first row"    "$REPLY" "2"
_zhimmer_zle_next 0 -1; is "and Up takes the last"                     "$REPLY" "5"
# A list of nothing but headers has nothing to take, and must not spin.
_zhimmer_zle_reset; _zhimmer_zle_header history
fails_ "a list with no matches yields none"    _zhimmer_zle_next 0 1
fails_ "in either direction"                   _zhimmer_zle_next 0 -1
_zhimmer_zle_reset
_zhimmer_zle_header history
_zhimmer_zle_match 'echo one' history 'echo one'
_zhimmer_zle_match 'echo two' history 'echo two'
_zhimmer_zle_header file
_zhimmer_zle_match './a' file 'cat ./a'
is   "each row remembers the buffer it would leave" "$_zhimmer_zbuf[5]" "cat ./a"
_zhimmer_zle_reset
is   "reset clears the rows"                   "$#_zhimmer_zrow"      "0"

print
if (( fails )); then
  finished=1
  print "$fails of $checks unit checks FAILED"
  exit 1
fi
finished=1
print "all $checks unit tests passed"
