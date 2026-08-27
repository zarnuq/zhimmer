# zhimmer

An as-you-type dropdown menu for zsh. Type, and a ranked list of suggestions
drops down under the prompt; `↓` opens it, `↑`/`↓` move, `Tab` accepts.

No daemon, no network, no AI, no telemetry.

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

Matching against shell history is done by `zhimmer-match`, a small Rust binary.
zsh's own array filtering is fine at a few thousand history entries but degrades
badly beyond that:

| history entries | zhimmer-match | zsh `${(M)${(v)history}:#…}` |
|---|---|---|
| 8,589 | 3.4 ms | 3.5 ms |
| 171,780 | 12.8 ms | 77.6 ms |
| 515,340 | 27.7 ms | 221 ms |

With `SAVEHIST=1000000` that difference decides whether the shell stays usable.
Everything else — aliases, `$commands` — already lives in zsh's memory, where
filtering in place beats paying a fork.

Two ZLE widgets share one generator:

- `zhimmer-show` (`list-choices`) draws the list without touching the buffer, so
  it can run on every keystroke without blocking.
- `zhimmer-menu` (`menu-select`) hands off to the `menuselect` keymap for arrow
  navigation.

## Requirements

zsh 5.8+, and `cargo` to build the matcher.

## Install

With zplug:

```zsh
zplug "<you>/zhimmer", hook-build:"cargo build --release --manifest-path zhimmer-match/Cargo.toml", defer:2
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
| `→` `Ctrl+F` | accept the ghost at end of line; move the cursor anywhere else |
| `Ctrl+E` `End` | accept the ghost; plain end-of-line when there is none |
| `Tab` | accept the highlighted row inside the menu; outside it, zsh's normal completion |
| `Enter` | run |
| `Esc` | inside the menu, back out and restore the line |
| `Shift+Tab` | step back up through Tab's matches |
| `Ctrl+Space` | toggle zhimmer on/off (`toggle-key`) |

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
completion standing. Which of those it is gets decided from the line the last
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
the same setting also sets `menu select=long`, which hands exactly that case —
the list that does not fit — to menu selection instead. The arrows walk it, it
scrolls under them, `Tab` takes the row the cursor is on and `Esc` backs out:
the menu `↓` opens, reached from `Tab`, with the line being edited still above
it rather than pushed off the top. The count and position underneath come from
the same `MENUPROMPT`, which the completion system replaces only when a
`select-prompt` style is set.

A list that fits is left alone — menu selection never starts, and `Tab` and
`Shift+Tab` still step through those matches one at a time. The `list-prompt`
stays for the widgets that only ever list, like `Ctrl+D`, where there is
nothing to select into.

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

Prints resolved configuration, matcher status and timing, the candidates for a
query, and warnings for the environment problems that actually break this
plugin — history that only flushes at shell exit, a missing `compinit`, a
conflicting ghost-text plugin.

The settings it lists come from the same table the code reads, so they cannot
drift from what is in force, and `styles set` names the completion styles
zhimmer actually set — the ones missing from that line are the ones your own
configuration had already answered.

## Replaces

**zsh-autosuggestions** — zhimmer draws ghost text from the same `POSTDISPLAY`
mechanism, so running both means two plugins fighting over it.

The accept keys are the same ones: `→`, `Ctrl+F`, `Ctrl+E`, `End`.

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
cargo test --manifest-path zhimmer-match/Cargo.toml   # matcher: parsing, ranking, dedup, limits
zsh test/screen.zsh                                   # ZLE layer: ghost, navigation, Tab, layout
```

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
