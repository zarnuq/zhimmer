# zhimmer

An as-you-type dropdown menu for zsh. Type, and a ranked list of suggestions
drops down under the prompt; `↓` opens it, `↑`/`↓` and `Tab` move, typing
narrows it, `Enter` takes the row.

No daemon, no network, no AI, no telemetry, nothing compiled.

```
$ git ch
history
git checkout -b feat/menu
git checkout main
git cherry-pick abc123
```

## How it works

The menu is drawn by zhimmer, into `POSTDISPLAY`, with `region_highlight` for
the colour. It went through zsh's own `zsh/complist` for a while and does not
any more — see [the drop-down](#the-drop-down) for why, which comes down to one
thing complist cannot do: filter an open menu without flickering. complist is
still loaded, because it is what draws `Tab`'s listing.

History matching is zsh's own, and never forks. `${history[(R)pattern]}`
searches the parameter in place, newest match first, without expanding tens of
thousands of entries into an array to filter afterwards — that expansion alone
costs four times the search, and it is what made an earlier attempt at this too
slow to keep. Then, because typing only ever extends the query, each keystroke
narrows the previous keystroke's matches instead of searching again: the search
runs once per word, not once per character.

| history entries | first keystroke of a word | every keystroke after it |
|---|---|---|
| 900 | 0.66 ms | 0.18 ms |
| 10,000 | 2.2 ms | 0.84 ms |
| 96,000 | 14.4 ms | 1.4 ms |

A keystroke has about 10 ms before the lag is visible, so the ceiling is a
history in the tens of thousands; past ~50,000 entries the first keystroke of
each word starts to be felt, while typing on stays flat. Reading `$history`
rather than `HISTFILE` also means this session's own commands match the moment
they run, with no `INC_APPEND_HISTORY` needed — but it is `HISTSIZE`, not
`SAVEHIST`, that decides how much of the file is in memory to match against, so
`zhimmer-doctor` says which one is holding the number down.

Ranking is frecency — how often a command was run, weighted by how recently it
last was, the newest occurrence counting four times the oldest. Only the newest
few hundred occurrences of a prefix are counted: with that weighting the older
ones cannot change the order, and stopping there is what keeps the cost flat.

Everything else — aliases, `$commands` — already lives in zsh's memory too,
where filtering in place beats paying a fork.

The sources that cannot avoid one — `git-branch`, `git-file`, `zoxide` — pay it
once per command line rather than once per keystroke. All three answer questions
that only change when something is *run* — a branch created, a file edited, a
directory visited — so the answer is cached against `HISTCMD` and re-read on the
next prompt. Per keystroke `git-branch` and `zoxide` cost 1.4 ms and 4.4 ms,
which is more than ranking ten thousand history entries; per command line they
cost nothing worth measuring.

`make`, `npm-script` and `ssh-host` read files rather than run commands, and
re-read only when the file's mtime moves — a free check through `zsh/stat`,
which forks nothing. Each parses the file itself rather than asking a tool:
`make -pn` runs the makefile's own assignments to build its database, and there
is no JSON parser in zsh worth shelling out to node for. The reading and the
parsing are separate functions in every case, which is what lets the parsers be
tested against fixtures in `test/unit.zsh`.

One ZLE widget gathers the candidates — `zhimmer-show`, a `zle -C ...
list-choices` — and it adds nothing through `compadd`. What it is *for* is the
completion context: the completion system is what splits the line into `$words`
and hands a source its `$PREFIX` and `$CURRENT`, which is how each one decides
whether it applies at all. The rows it gathers are drawn separately, so the
widget never touches the buffer and can run on every keystroke.

## Requirements

zsh 5.8+. Nothing to compile and nothing to install alongside it: the only
external commands at runtime are the ones a source is *about* — `git` for the
branch and changed-file sources, `zoxide` for the zoxide one — and each checks
for its own before
drawing anything, then reads it once per command line rather than once per
keystroke.

Colours are truecolor (`#rrggbb` on headers, a raw SGR on the selection). On a
terminal without it, `zmodload zsh/nearcolor` before loading zhimmer maps them
to the nearest 256-colour approximation.

## Install

With zplug:

```zsh
zplug "zarnuq/zhimmer", defer:2
```

`defer:2` loads it after `compinit`. Declare it *before* `zsh-syntax-highlighting`,
which wraps whatever widgets exist when it loads.

Locally:

```zsh
zplug "/path/to/zhimmer", from:local, use:"zhimmer.plugin.zsh", defer:2
```

## Keys

| key | action |
|---|---|
| `↓` | open the menu — falls through to history when there is nothing to show |
| `↑` `↓` | move within the menu |
| `Tab` `Shift+Tab` | inside the menu, move down and up it; outside, zsh's normal completion |
| *typing* | inside the menu, narrow it to what still matches |
| `Enter` | inside the menu, take the highlighted row; outside, run the line |
| `Esc` | inside the menu, back out of it |
| `→` `Ctrl+F` | accept the ghost at end of line; move the cursor anywhere else |
| `Ctrl+E` `End` | accept the ghost; plain end-of-line when there is none |
| `Ctrl+→` `Alt+→` | accept **one word** of the ghost; plain forward-word when there is none |
| `Ctrl+R` | search the history by substring; pressed again, step to the next match (`search-key`) |
| `Ctrl+Space` | toggle zhimmer on/off (`toggle-key`) |

Nothing is chosen until `Enter`: the menu marks the row it is on rather than
writing it into the line, so the arrows and typing leave what you typed alone
until you take a row. There is no mode to be in — the arrows move an index and
wrap at both ends, which is also how `↑` opens the menu from nothing.

`Esc` is deliberately not bound outside the menu: it is zsh-vi-mode's
normal-mode switch and it prefixes every arrow-key escape sequence.

### Tab and the drop-down

Tab's matches are drawn by zhimmer too — the same header, rule and one-row-per-line
layout as the history and file groups, instead of complist's columns. The
matches themselves still come from the completion system, every completer and
matcher and quoting rule intact: `compadd` is shadowed for the duration of one
completion and the call re-issued with zhimmer's display strings in front of
the original arguments. compadd takes the *first* of a repeated option, so
going first is what makes it win — and why a completer's own display strings
are carried over and padded rather than dropped, since `git` has more to say
about its subcommands than a theme does.

The probe that reads the matches back (`compadd -O`) is the one place the call
is picked apart, and only to drop `-D`, `-A` and `-O` — the options that write
into an array. `_describe` passes `-D` and keeps its descriptions there, so
probing with it ran that filter a second time and left `git` completion with
nothing at all. Set `style-completion` to `no` to hand the drawing back to
complist.

`Tab`'s menu is plain zsh menu selection, not zhimmer's. It walks by inserting
each match into the line, and typing at it accepts the highlighted row rather
than narrowing — conventional `menu-complete` behaviour, and what you get
without `interactive`, which is deliberately not asked for. complist draws a
hardcoded `interactive: []` row for the whole time that mode is on and drops
out of the mode on every movement key, so asking for it bought that row and
little else once zhimmer's own drop-down filtered natively. Narrowing still
works the way it always did: keep typing, and zhimmer's list follows.

Both zhimmer and zsh's completion draw into the same area under the prompt, and
Tab belongs to completion. So Tab clears zhimmer's rows before completing —
they describe the word as it was — but never zsh's own: zsh keeps one list
across a run of Tabs, and clearing it on every press leaves the area blank from
the second Tab onwards, which is exactly when you are tabbing through a
directory and want to see it. Afterwards the area belongs to whatever
completion did with it. Only when there was exactly one match, and so nothing
to list, does zhimmer redraw its own list for the finished word.

Without that, completing `./Doc` to `./Documents/` left the file list still
showing the matches for `./Doc`, and an ambiguous completion was hidden
underneath rows describing the previous word.

`Shift+Tab` steps back up through those matches, so Tab and Shift+Tab move in
opposite directions through the same list, and does nothing when there is no
completion standing. Inside the menu that is the menu's own keymap; outside it
— where menu selection never started, which is what a `menu` style of your own
gets, since zhimmer leaves one that is already set alone — it is a widget, and
whether there is anything to step back into gets decided from the line the last
completion left behind, not from `LASTWIDGET`: with fzf's completion loaded Tab
is `fzf-completion`, and zhimmer's wrapper runs underneath it.

The on/off switch is `Ctrl+Space`, not `Shift+Tab`. Sharing that key was a bad
trade — the step-back is pressed constantly and the switch almost never, so the
switch got hit by accident, and a disabled zhimmer draws nothing at all, which
looks exactly like a broken one. Turning it off now says so; set `toggle-key`
to rebind it, or to an empty string to leave the switch unbound.

### The drop-down

zhimmer draws its own menu, into `POSTDISPLAY`, with `region_highlight` for the
colour. It used to be complist's, fed through `compadd`, which was worth trying:
scrolling, resize and redraw are already solved there. It went because of one
thing complist cannot do — **filter an open menu without flickering.**

complist's interactive mode is what filters, it resets that mode on every
movement key (`mode = 0` in each mover in `Src/Zle/complist.c`), and it draws a
hardcoded `interactive: []` row while the mode is on. Keeping the mode alive
across an arrow press therefore costs a `move, then vi-insert` macro that
removes and reinserts a screen row on every keypress, shifting the list under
the cursor. There is no way around it from outside: the `menu-complete` family
is the only command that preserves the mode, and in that mode it does not move
the selection at all.

Drawing it here removes the question instead of answering it. **There is no menu
mode to be in**: typing narrows the list because typing already recomputes it,
the arrows only move an index, and nothing toggles. No `interactive: []`, no
shifting, and the command line keeps its syntax highlighting because the display
is never handed to complist. It is also less to write — 491 bytes a keystroke
against complist's 2927.

The other half is that `region_highlight` colours by character *offset*, so an
escape is never counted as width — the constraint that keeps colour out of a
`compadd` display string. Rows are plain text and colour is applied over them.
Widths are read at draw time, so a terminal resize is picked up by the next
keystroke without anything being regenerated.

Nothing is written into the line until `Enter`: the bar marks a row, and the
ghost follows the selection so `→` and `Enter` never promise different lines.

The trade is cost. The rows are built in zsh where complist built them in C —
2.0–3.0 ms a keystroke at ten rows against complist's 1.3–1.7, and 5.3 ms
against 3.3 at thirty-five — but both sit inside the ~10 ms a keystroke has.

complist keeps two jobs either way: `Tab`'s completion menu, which belongs to
zsh's completion system, and long completion listings (`tame-lists`).

### Searching (Ctrl+R)

`Ctrl+R` moves the anchor. The drop-down normally matches what you have typed
at the *start* of a remembered line; in a search it matches anywhere in one, so
`commit` finds `git commit --amend`. Everything after the match is the same
code — the same frecency ranking, the same rows, the same keys — which is the
point: searching is one flag on the machinery that was already there, not a
second mechanism beside it.

That means no fork, no subshell and no external binary, which is what it
replaces: `bindkey -r '^R'` after fzf's own setup and this takes the key.

With zsh-vi-mode loaded, note that it binds `^R` to
`history-incremental-search-backward` inside its own init, which by default
runs at the first precmd — after every plugin has been sourced. zhimmer binds
its keys at load time *and* again from `zvm_after_init_commands` for that
reason; if `Ctrl+R` gives you `bck-i-search`, that second pass is what did not
happen.

```
$ commit
search
git commit -m "second"
git commit --amend
git commit -m "first"
```

The header says `search` rather than `history`, which is the only thing on
screen that distinguishes the two — including when there is nothing to show,
where it reads `search: no match` rather than leaving a bare line.

- **The order is your history's, newest first** — not the drop-down's frecency
  order. That is what the key has always meant, in fzf and in zsh's own
  `bck-i-search` alike: you are looking for a thing you ran, and *when* is how
  you remember it. Frecency belongs to the drop-down, where there is no
  question yet; applied to a search it hides this morning's command behind one
  from last year that you type every day.
- Duplicates collapse to their newest occurrence, and `search-suggestions`
  rows (100 by default) are kept, so the window scrolls under them. A history
  is mostly repeats and four screens of `ls` is not a search result. Lines
  differing only in trailing whitespace are different lines and both show.
- On an empty line it opens on the whole history. `min-chars` does not apply:
  it exists so a suggestion is not a guess two characters into a line, and a
  search *is* the question.
- A row is always selected while a search is open, so `Enter` always has one to
  take. `Ctrl+R` again steps to the next match, as it does in zsh's own
  incremental search.
- History is the only source asked. Offering the files in this directory beside
  the remembered lines containing what you typed is two searches sharing a
  screen.
- There is no ghost text, and nothing enforces that: a candidate that merely
  *contains* what you typed does not extend it, so the existing rule drops it.
  On an empty line it does show the selected row, since everything extends
  nothing.
- `Ctrl+C` abandons it. The mode is also cleared at `line-init`, not only at
  `line-finish` — `Ctrl+C` never reaches the latter, and a search left on
  leaked into the next line.

The cost is the anchor. A leading `*` cannot use the prefix to stop early:

| | 8,500 entries |
|---|---|
| prefix `git` | 1.1 ms |
| substring `git` | 2.2 ms |
| whole history (empty `Ctrl+R`) | 3.9 ms |

All three are one deliberate keypress, and typing on narrows the previous match
set rather than searching again — the same trick the prefix path uses. The mode
is part of what that cache is keyed on, because lines *containing* `git` and
lines *starting with* it are not subsets of each other.

### Long lists

`tame-lists` (on by default) decides what a completion listing does once it
outgrows the screen. Past `LISTMAX` zsh replaces it with *"do you wish to see
all 149 possibilities?"* — a yes/no question where every other Tab gives a list
— so `LISTMAX=0` and a `list-prompt` turn that question into a scroll.

A scroll is still only a pager, though: `ls /etc/<Tab>` gives 150 names to page
past, one keypress at a time, with nothing selected and nothing to accept. So
the same setting also sets `menu select`, which hands the matches to menu
selection instead. The arrows and `Tab` walk it, it scrolls under them, `Enter`
takes the row the cursor is on and `Esc` backs out: the menu `↓` opens, reached
from `Tab`, with the line being edited still above it rather than pushed off the
top. The count and position underneath come from `select-prompt`, set to match
`list-prompt` so a scrolled menu says the same thing a scrolled listing does.

Plain `select`, not `select=long`. A short list fits on screen, but fitting is
not the same as having nothing to choose from: with selection only on the long
ones, `Tab` stepped through a short list by inserting each match with nothing on
screen saying which row that was. The `list-prompt` stays for the widgets that
only ever list, like `Ctrl+D`, where there is nothing to select into.

### Typing at an open menu

Typing narrows the list to what still matches, backspace widens it again, and
the row is taken only by `Enter`. This needs no mode and no setting: a keystroke
already recomputes the list, and the menu is only an index into whatever that
produced. Moving the selection and narrowing it are the same two mechanisms they
are when the menu is closed.

That is the whole reason the drop-down is drawn here rather than by complist.
zsh calls the equivalent menu selection's *interactive mode*, and it costs a
`interactive: []` row on screen, a shifting list on every arrow, and a flattened
command line for as long as the menu is open.

### Colours and what is left alone

`list-colors` gets `ma=` so `Tab`'s selected row is the same bar zhimmer's own
menu paints, rather than falling back to reverse video. It goes on the style
and not on `ZLS_COLORS` because inside the completion system that parameter is
rebuilt from the style for the duration — one of the reasons the drop-down
stopped going through complist at all.

Set `tame-lists` to `no` to leave all of it alone. A style already set by hand
— `menu`, `list-colors`, `list-prompt`, `group-name` — is never overridden, on
whatever context pattern it was written.

## Configuration

```zsh
zstyle ':zhimmer:*' sources         history alias command file git-branch zoxide
zstyle ':zhimmer:*' max-suggestions 10
zstyle ':zhimmer:*' min-chars       2
zstyle ':zhimmer:*' ghost-text      yes
zstyle ':zhimmer:*' ghost-color     'fg=#6c7086'
zstyle ':zhimmer:*' expand-alias    yes
zstyle ':zhimmer:*' tame-lists      yes
zstyle ':zhimmer:*' row-colors      yes
zstyle ':zhimmer:*' style-completion yes
zstyle ':zhimmer:*' toggle-key      '^@'
zstyle ':zhimmer:*' search-key      '^R'
zstyle ':zhimmer:*' search-suggestions 100
```

### Appearance

Group headers are coloured per source and carry a rule to the right edge; rows
are indented, padded to the full width so the selection reads as a solid bar,
and truncated with `…` rather than wrapping.

```zsh
ZHIMMER_COLORS[history]='#6c7086'      # per-source header colour
ZHIMMER_COLORS[alias]='#cba6f7'
ZHIMMER_RULE_COLOR='#313244'
ZHIMMER_SELECT_BG='#45475a'            # the selected row's bar
```

Defaults are Catppuccin Mocha, picked to match the prompt colours in the
author's `.zshrc`.

Row text carries one accent: the first token — the command in a history line,
the name of an alias, the branch or host or target a source is about — in that
source's colour. Arguments stay plain, which keeps a row scannable and keeps
this from turning into a second, worse syntax highlighter.

```zsh
ZHIMMER_ROW_COLORS[history]='#a6e3a1'   # the command word, in command-green
ZHIMMER_ROW_COLORS[file]='#fab387'
zstyle ':zhimmer:*' row-colors no       # plain rows
```

That accent is painted with `region_highlight`, which works in character
offsets, never written into the row text. This is the constraint the whole
drop-down is shaped around: escapes put in a string that something else lays
out do render, but the layout measures the string it was given and counts the
escape bytes as width, so a padded row comes up short and a long one truncates
early. Colouring by offset cannot have that problem.

`sudo openvpn …` puts the command in second place, so a rule that only ever
paints the first token leaves the word you were looking for plain. The words
that take a command as their argument are known, and the token after one of
them is highlighted as the command instead — with the precommand itself
underlined, which is how zsh-syntax-highlighting marks it on the line above.

```zsh
ZHIMMER_ROW_PRECOMMANDS=( sudo doas su env command nohup … )
ZHIMMER_ROW_PRECOMMAND_COLOR='4;#a6e3a1'   # the `4;` is the underline
```

The accent is keyed by the source's **group** (`git-branch`), not by the label
its header is drawn under (`branch`) — those are different words for six of the
eleven sources, and looking a row up by its label returns nothing at all,
silently, since a missing key in a zsh hash is an empty string rather than an
error. `test/unit.zsh` reads the pairs back out of `sources/*.zsh` and checks
both tables cover them, which is the check that catches a source added without
a colour.

Group headers still take the colour they always did, and the selected row is
still a solid bar — the accent gives way to it rather than fighting it.

zsh-syntax-highlighting is untouched by any of this and still owns the command
line, including while the menu is open — which it did not when the menu was
complist's, since interactive mode took the line over and flattened its colours
until you left. Both write `region_highlight` now, so zhimmer tags every entry
it adds with `memo=zhimmer` and only ever removes its own.

`max-suggestions` is capped at what the terminal can actually show — `$LINES -
5`, shared across every group rather than applied per source, since six sources
at ten each is sixty rows and the prompt would go off the top. `↓` opens
whatever is on screen, whichever source drew it.

Sources are tried in the order listed, each becoming its own labelled group.
Adding one means dropping a `_zhimmer_source_<name>` function into `sources/`
and naming it in the style.

| source | offers | where |
|---|---|---|
| `history` | whole command lines, ranked by frecency | anywhere |
| `alias` | aliases, with what they expand to | command position |
| `command` | executables on `$PATH` | command position |
| `file` | files and directories, globs included | argument position |
| `git-branch` | local branches; remotes where a remote goes; `origin/main` for merge and rebase | after a git subcommand that takes one |
| `git-file` | the paths `git status` says have changed | `git add`, `restore`, `rm`, `diff`, `checkout`, `reset`, `stash` |
| `zoxide` | zoxide's directories, matched anywhere in the path | after `cd` and `z` |
| `make` | targets from the Makefile | after `make` |
| `npm-script` | scripts from `package.json` | after `npm run` and the same shape in pnpm, yarn and bun |
| `ssh-host` | hosts from `~/.ssh/config` and `known_hosts` | after `ssh`, `scp`, `sftp`, `rsync`, `mosh` |

`alias`, `command` and `history` need something typed: with an empty word the
first two match every alias and every executable on `$PATH`, and history has no
prefix to rank against. The sources with a command in front of them do not need
one — `git checkout `, `make `, `ssh ` have already said what the list is of, so
they offer it with the word still empty.

Two limits are worth knowing. `ssh-host` skips a hashed `known_hosts` — those
names cannot be read back at all, and a row of base64 is worse than no row.
`git-branch` names remotes from `refs/remotes`, so a remote you have added but
never fetched from has no refs to be named by and does not appear.

### Ghost text

The greyed preview past the cursor is the top row of whatever is on screen, and
every group offers its first row as it is drawn. History outranks the rest, so
a whole remembered line wins over a single completed word — typing `gi` shows
the `git push --force-with-lease` you actually ran, not `git` completed from
`$PATH`. Between the others the earliest group drawn keeps it, which is the
order the `sources` style lists them in.

```zsh
ZHIMMER_GHOST_RANK[history]=0    # lower wins; everything unlisted is 1
```

A candidate that is not an extension of what is typed simply draws no ghost, so
a source matching by any rule other than a prefix — zoxide finds `~/src/zhimmer`
from `z hmr` — contributes rows to the menu without ever putting text that does
not follow from the line in front of the cursor.

### Alias expansion

With `expand-alias yes` (the default), an alias is rewritten in place to the
command it stands for, so the real line fills the prompt instead of the
shorthand — typing `gs ` leaves `git status -s ` in front of the cursor, ready
to edit before it runs. It fires on `Space` and `Enter`. Command aliases expand
only in command position (zsh's own rule); global aliases expand anywhere; and
chains (`gcm` → `gc` → `git commit`) resolve one step at a time. Set the style
to `no` to turn it off.

## Prompt

Off by default. zhimmer is loaded for its menu, and taking over the prompt of
everyone who does that is not a trade they agreed to.

```zsh
zstyle ':zhimmer:*' prompt yes
```

```
 ~/zhimmer feat/menu !?⇡1
 >
```

Directory, branch, what the working tree looks like, and a `>` that turns red
when the last command failed. Two lines, no blank line above them.

It is split by what things cost. Everything knowable without a fork — the
directory, the branch, the exit status — is drawn immediately, in **0.07 ms**.
The one thing that is not, the working-tree status, is fetched in the
background and the prompt redraws when it arrives. So the prompt appears at the
same speed everywhere, and a slow repository delays a few symbols rather than
the shell.

That split is the whole design, because `git status` is not slow in the
abstract — it is 1.5 ms in a small repository and 67 ms in one with 94,000
tracked files, and a prompt that blocks on it is fine right up until the day it
is not.

The branch needs no git at all. `.git/HEAD` is a line of text naming the ref:

| how | cost |
|---|---|
| read `.git/HEAD` | **0.01 ms** |
| `git symbolic-ref --short HEAD` | 1.0 ms |
| `vcs_info` | 16.75 ms |

Almost every prompt in the wild pays one of the latter two for an answer sitting
in a file. A `.git` that is a *file* rather than a directory — a linked worktree
or a submodule — is followed to the directory it names, and a detached HEAD
reads as the short sha.

One `git status --porcelain=v1 --branch` answers everything else: every status
column and the distance from upstream, in a single fork. For comparison, Pure
spends five forks and about 89 ms per prompt on the same question, most of it
because `vcs_info` is asked for the branch separately.

### Symbols

Spaceship's, because they are the ones people already read.

| | |
|---|---|
| `?` | untracked | 
| `+` | staged |
| `!` | modified |
| `»` | renamed |
| `✘` | deleted |
| `=` | unmerged |
| `⇡3` `⇣2` | ahead of / behind upstream |

Divergence is both arrows rather than a `⇕` of its own, which says the same
thing and drops the two numbers to do it. A branch with no upstream shows no
arrows at all — that is not the same as being level with one.

```zsh
ZHIMMER_PROMPT_SYMBOLS[modified]='*'
ZHIMMER_PROMPT_ORDER=( unmerged deleted renamed modified staged untracked )
ZHIMMER_PROMPT_COLORS[branch]='#cba6f7'
ZHIMMER_PROMPT_SYMBOL=' >'
```

### Switching it off

```zsh
zhimmer-prompt-off      # puts back the prompt that was there when it was turned on
zhimmer-prompt-on
```

The prompt in force when it was switched on is saved and restored verbatim, so
this can be turned on and off next to Pure or starship without either of them
losing anything. `zhimmer-doctor` warns when one of them is loaded *and* this is
on, since the last one to set `PROMPT` wins.

Set `prompt-async` to `no` to compute the symbols in the foreground instead. The
prompt then blocks for as long as `git status` takes, which in a small
repository is not measurable and in a large one is the 67 ms above.

Two things are deliberately not here. Exec time, which Pure shows, is cheap to
add — it is arithmetic on `EPOCHSECONDS`, no fork — but nobody asked for it.
And the stash count, which cannot come from `git status` and would cost a second
fork for a character.

## Diagnostics

```zsh
zhimmer-doctor 'git '
```

Prints resolved configuration, how much history the ranking can see, the
candidates for a query with the time both halves of the search cost, and
warnings for the environment problems that actually break this plugin — a
missing `compinit`, and any of the plugins that cannot share the mechanisms
zhimmer works through: zsh-autosuggestions (`POSTDISPLAY`), fzf-tab (`compadd`),
zsh-autocomplete (the same keys), zsh-abbr (`Space`). Each says what it collides
with, so the fix is a choice rather than a guess.

The settings it lists come from the same table the code reads, so they cannot
drift from what is in force, and `styles set` names the completion styles
zhimmer actually set — the ones missing from that line are the ones your own
configuration had already answered.

## Replaces

**zsh-autosuggestions** — zhimmer draws ghost text from the same `POSTDISPLAY`
mechanism, so running both means two plugins fighting over it.

The accept keys are the same ones: `→`, `Ctrl+F`, `Ctrl+E`, `End` — and
`Ctrl+→`/`Alt+→` takes a single word of the suggestion, so `git push --force`
out of a ghost of `git push --force-with-lease origin feature` is one keypress
rather than a choice between all of it and none.

Where a word ends is not decided by zhimmer. The line is temporarily made whole,
suggestion and all, and your own `forward-word` widget is run on it — so
`WORDCHARS`, vi versus emacs, and any plugin that has taken that widget all
still decide, and the key answers the same way it would on text that is really
in the buffer.

It does *not* replace zsh's completion system. `Tab` outside the menu still
completes subcommands, flags and paths exactly as before, and is deliberately
not an accept key — completing a word is a different gesture from accepting a
whole remembered line.

That distinction is why the ghost has to be dropped rather than left drawn: it
lives in `POSTDISPLAY`, not in `BUFFER`, so a suggestion still on screen when
the line is accepted shows a command the shell never runs — `git clone https://…`
displayed, `git clone htt` executed. zhimmer clears it whenever the buffer stops
matching it, and again at `line-finish`.

## Tests

```zsh
zsh test/unit.zsh     # pure logic: ranking, rows, aliases, ghost precedence
zsh test/screen.zsh   # ZLE layer: ghost, navigation, Tab, menu, layout
```

The two are split by what they cost. `unit.zsh` sources the libraries without a
line editor and runs in about 15ms, so it can go on every save; `screen.zsh`
drives a real zsh through tmux and takes roughly half an hour. A ranking bug
belongs in the first — reading a history line with a stray `[` in it shipped as
an `invalid subscript` at the prompt, and the whole of what was wrong fits in
four lines of assertion.

A zsh arithmetic error is fatal rather than catchable, so `unit.zsh` prints
`ABORTED` and exits non-zero if it ends early; a short run of `ok` lines is not
a pass.

### Notes on testing

ZLE cannot be exercised without a terminal. Three things make it testable:

- **Render through tmux, not raw pty bytes.** `zpty` hands back every
  intermediate redraw interleaved, so text that has already been cleared is
  still present in the stream — a stale-ghost bug reads exactly like a fixed
  one. `tmux capture-pane -p` returns the resolved screen instead. This
  distinction cost a wrong conclusion once already.
- **Fake `HOME`, not `ZDOTDIR`.** `ZDOTDIR=… zsh -i` does not isolate a test
  shell if `/etc/zsh/zshenv` sets `ZDOTDIR` unconditionally (Gentoo does).
- **Never send Enter when driving the real config.** The buffer holds a real
  command from history and it will run. Use `C-c`.

If you do read raw pty output, `zpty -r` blocks — `zpty -r -t` does not.
