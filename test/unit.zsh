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
  (( finished )) && return
  print "\n  ABORTED -- the suite exited before finishing; see the error above"
}

source $root/lib/theme.zsh
source $root/lib/complete.zsh
source $root/lib/ghost.zsh
source $root/lib/expand.zsh
source $root/sources/history.zsh

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
if (( fails )); then
  finished=1
  print "$fails of $checks unit checks FAILED"
  exit 1
fi
finished=1
print "all $checks unit tests passed"
