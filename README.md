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
| `→` | accept the ghost at end of line; moves the cursor anywhere else |
| `Tab` | accept the highlighted row; outside the menu, zsh's normal completion |
| `Enter` | run |
| `Esc` | inside the menu, back out and restore the line |
| `Shift+Tab` | toggle zhimmer on/off |

`Esc` is deliberately not bound outside the menu: it is zsh-vi-mode's
normal-mode switch and it prefixes every arrow-key escape sequence.

## Configuration

```zsh
zstyle ':zhimmer:*' sources         history alias command file git-branch zoxide
zstyle ':zhimmer:*' max-suggestions 10
zstyle ':zhimmer:*' min-chars       2
zstyle ':zhimmer:*' ghost-text      yes
zstyle ':zhimmer:*' ghost-color     'fg=#6c7086'
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

Sources are tried in the order listed, each becoming its own labelled group.
Adding one means dropping a `_zhimmer_source_<name>` function into `sources/`
and naming it in the style.

## Diagnostics

```zsh
zhimmer-doctor 'git '
```

Prints resolved configuration, matcher status and timing, the candidates for a
query, and warnings for the environment problems that actually break this
plugin — history that only flushes at shell exit, a missing `compinit`, a
conflicting ghost-text plugin.

## Replaces

**zsh-autosuggestions** — zhimmer draws ghost text from the same `POSTDISPLAY`
mechanism, so running both means two plugins fighting over it.

It does *not* replace zsh's completion system. `Tab` outside the menu still
completes subcommands, flags and paths exactly as before.

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
