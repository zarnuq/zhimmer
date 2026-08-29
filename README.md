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

The menu is drawn by zsh's own `zsh/complist`, fed through `compadd`. That is
deliberate: scrolling, terminal resize, multiplexers and redraw are already
solved there, and reimplementing them is where comparable tools accumulate bugs.

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

Two ZLE widgets share one generator:

- `zhimmer-show` (`list-choices`) draws the list without touching the buffer, so
  it can run on every keystroke without blocking.
- `zhimmer-menu` (`menu-select`) hands off to the `menuselect` keymap for arrow
  navigation.

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
| `Ctrl+Space` | toggle zhimmer on/off (`toggle-key`) |

Nothing is chosen until `Enter`: the menu marks the row it is on rather than
writing it into the line, so `Tab`, the arrows and typing all leave what you
typed alone until you take a row. Set `type-to-filter` to `no` for the older
arrangement, where the menu inserts as it moves and `Tab` accepts.

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
top. The count and position underneath come from the same `MENUPROMPT`, which
the completion system replaces only when a `select-prompt` style is set.

Plain `select`, not `select=long`. A short list fits on screen, but fitting is
not the same as having nothing to choose from: with selection only on the long
ones, `Tab` stepped through a short list by inserting each match with nothing on
screen saying which row that was. The `list-prompt` stays for the widgets that
only ever list, like `Ctrl+D`, where there is nothing to select into.

### Typing at an open menu

`type-to-filter` (on by default) is the other half of that. Without it the first
character typed at an open menu accepts whichever row the cursor happens to be
on and types after it — `ls /etc/<Tab>a` left `ls /etc/acpi/a`, a directory
nobody asked for. With it, typing narrows the list to what still matches,
backspace widens it again, and the row is taken only by `Enter`.

zsh calls this menu selection's *interactive mode*, and it is switched on in
two places, because zhimmer has two menus: through the `menu` style for Tab's,
and on `MENUMODE` for `↓`'s, which is a raw `zle -C` widget and so never goes
through the completion system.

complist drops out of interactive mode the moment a key moves the selection,
which would quietly turn the next character typed back into *accept this row,
then insert it*. So inside the menu every movement key is bound to a two-key
macro — move, then `vi-insert`, which is complist's own toggle back into the
mode. Backspace is bound there too: complist reads it as *take a character back
off what I am filtering on* only while the key is bound to the builtin, and
zhimmer rebinds it to refresh the ghost, which made backspace leave the menu
instead, accepting a row on the way out.

Set `type-to-filter` to `no` to get the plain menu back: the selection is
inserted as it moves, `Tab` accepts, and typing ends the menu.

### Colours and what is left alone

`list-colors` gets `ma=` from the same `ZHIMMER_SELECT` as zhimmer's own menu.
Inside the completion system `ZLS_COLORS` is rebuilt from that style for the
duration of the completion, so without it Tab's selected row falls back to
reverse video while `↓`'s is a solid bar.

Set `tame-lists` to `no` to leave all of it alone. A style already set by hand
— `menu`, `list-colors`, `list-prompt`, `group-name` — is never overridden, on
whatever context pattern it was written.

## Configuration

```zsh
zstyle ':zhimmer:*' sources         history alias command file git-branch zoxide
zstyle ':zhimmer:*' max-suggestions 10
zstyle ':zhimmer:*' menu-suggestions 50
zstyle ':zhimmer:*' min-chars       2
zstyle ':zhimmer:*' ghost-text      yes
zstyle ':zhimmer:*' ghost-color     'fg=#6c7086'
zstyle ':zhimmer:*' expand-alias    yes
zstyle ':zhimmer:*' tame-lists      yes
zstyle ':zhimmer:*' type-to-filter  yes
zstyle ':zhimmer:*' style-completion yes
zstyle ':zhimmer:*' toggle-key      '^@'
```

### Appearance

Group headers are coloured per source and carry a rule to the right edge; rows
are indented, padded to the full width so the selection reads as a solid bar,
and truncated with `…` rather than wrapping.

```zsh
ZHIMMER_COLORS[history]='#6c7086'      # per-source header colour
ZHIMMER_COLORS[alias]='#cba6f7'
ZHIMMER_RULE_COLOR='#313244'
ZHIMMER_SELECT='48;2;69;71;90;1'       # selected row (raw SGR, ZLS_COLORS ma=)
```

Defaults are Catppuccin Mocha, picked to match the prompt colours in the
author's `.zshrc`.

Colour lives on headers and the selection, not on row text: `compadd -X` honours
prompt escapes (including truecolor `%F{#rrggbb}`), but display strings are laid
out by width, so escapes inside them are not reliable.

`max-suggestions` is capped at what the terminal can actually show. complist does
not paginate a raw `zle -C` listing, so an over-long list scrolls the prompt off
the top and takes the earliest candidates with it; zhimmer clamps to
`$LINES - 5` instead.

The menu `↓` opens is under no such limit: menu selection scrolls, so it holds
`menu-suggestions` per source (50 by default) and you walk down into the rest,
with the prompt still above and `12/50 matches -- at 24%` below. A listing has
to fit; a menu only has to be reachable. Scrolling comes from the `MENUPROMPT`
and `MENUSCROLL` parameters rather than the `select-prompt` and `select-scroll`
styles, for the same reason as `ZLS_COLORS`: a raw `zle -C` widget never goes
through the completion system.

`↓` opens whatever list is on screen, whichever source drew it — a directory
with 400 entries gets the same bounded, scrolling menu as a five-entry one.

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
