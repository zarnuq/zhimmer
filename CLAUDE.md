# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

zhimmer is an as-you-type dropdown menu for zsh: a ranked list drops under the
prompt as you type, `↓` opens it into a navigable menu, `Enter` takes a row. It
also draws zsh-autosuggestions-style ghost text and restyles Tab's completion
listing. Pure zsh — nothing compiled, no daemon, no dependencies beyond the
commands a source is *about* (`git`, `zoxide`).

## Commands

```zsh
zsh test/unit.zsh     # pure logic; ~15ms; run this on every change
zsh test/screen.zsh   # ZLE layer through tmux; ~30 minutes
```

Neither suite takes a filter argument — both are linear scripts. To iterate on
one screen-test scenario, copy its `start` / `send` / `check` / `stop` block into
a scratch file; the harness functions are defined at the top of `test/screen.zsh`.

There is no build, no lint, and no install step. To exercise a change by hand:

```zsh
source ./zhimmer.plugin.zsh   # in an interactive shell, after compinit
zhimmer-doctor 'git '         # resolved config, candidates, timings, conflicts
```

The plugin guards against double-loading with `_zhimmer_loaded`, so re-sourcing
after an edit is a no-op — start a fresh interactive shell instead.

`zhimmer-doctor` is the first thing to reach for on a behaviour report: it prints
every setting from the same `ZHIMMER_DEFAULTS` table the code reads, how much
history the ranking can see, and warnings for the plugins that cannot share
zhimmer's mechanisms.

## Architecture

`zhimmer.plugin.zsh` sources `lib/*.zsh` and `sources/*.zsh` in one glob (order
does not matter — nothing runs at source time beyond defining functions and
setting defaults, which is also what lets `test/unit.zsh` source the libraries
without a line editor). It then registers the widgets and binds the keys.

One ZLE widget gathers candidates: `zhimmer-show`, a `zle -C ... list-choices`
running `.zhimmer-complete` in `lib/complete.zsh`. **It adds nothing through
`compadd`.** What the completion widget is for is the *context* — `$words`,
`$PREFIX`, `$CURRENT` — which is how every source decides whether it applies.
The rows are drawn by `lib/zlemenu.zsh` instead.

The row budget clamps to `$LINES - 5` and is shared across all groups: the list
is drawn under the prompt, so an over-long one pushes the prompt off the top,
and six sources at ten rows each is sixty.

`sources/*.zsh` each define one `_zhimmer_source_<name>` function, called with
`<limit>`, that decides whether it applies and calls `_zhimmer_addgroup` (whole
command lines) or `_zhimmer_addwords` (word-level matches). Both end in
`_zhimmer_emit`, which is the single place that knows how a row reaches the
screen. Adding a source means dropping a file in and naming it in the `sources`
zstyle — nothing else registers it.

**A source names two different strings and it matters which goes where.** The
first argument is the group (`zhimmer-git-branch`), which `ZHIMMER_ROW_COLORS`
is keyed by; the second is the header label (`branch`), which `ZHIMMER_COLORS`
is keyed by. For six of the eleven sources those are different words, and a
lookup by the wrong one returns an empty string rather than an error — so it
fails silently. `test/unit.zsh` reads the pairs back out of `sources/*.zsh` and
asserts both tables cover them.

`lib/ghost.zsh` decides *which* candidate becomes the ghost — every group
offers its first row as it is drawn and `ZHIMMER_GHOST_RANK` picks (history
wins) — and takes one into the buffer. The drawing itself is `zlemenu.zsh`'s,
since the ghost is the first line of the same `POSTDISPLAY` the rows go into.

`lib/prompt.zsh` is an optional prompt, **off unless `zstyle ':zhimmer:*'
prompt yes`**, split by cost: the directory, branch and exit status are drawn
synchronously in 0.07 ms with zero forks, while the working-tree symbols come
from one background `git status --porcelain=v1 --branch` delivered through a
`zle -F` handler that calls `zle reset-prompt`. It saves and restores whatever
`PROMPT` it found, so it can sit next to Pure or starship.

`lib/zlemenu.zsh` **is** the menu: zhimmer draws it into `POSTDISPLAY` with
`region_highlight` for colour. It replaced complist for one thing complist
cannot do — filter an open menu without flickering. complist resets interactive
mode on every movement key and draws a hardcoded `interactive: []` row while the
mode is on, so keeping the mode alive costs a macro that adds and removes a
screen row per keypress. Here there is no mode: typing narrows because typing
already recomputes, and the arrows only move an index.

It also owns `_zhimmer_zghost` — the greyed tail — **tracked separately from
`POSTDISPLAY`**, because `POSTDISPLAY` holds the ghost *and* every row. See the
invariant below.

`lib/tabstyle.zsh` shadows `compadd` for the duration of one completion so Tab's
matches get zhimmer's rows and headers, and sets the completion zstyles
(`menu select`, `list-prompt`, `select-prompt`, `group-name`, `list-colors`)
that make long listings selectable. Matches still come from compsys — only their
appearance is intercepted. **`interactive` is deliberately absent**: it is what
makes typing at an open menu narrow it, and it is also what makes complist draw
`interactive: []` and drop the mode on every arrow. zhimmer's own drop-down
filters natively, so Tab is left as conventional `menu-complete` — it inserts
each match as it walks, and typing at it accepts the highlighted row.

## Invariants that are easy to break

Nearly every comment in this codebase records a specific failure that motivated
the line above it. **Read the comment before changing the code it explains.** The
ones that bite hardest:

- **No forks on a keystroke.** Helpers answer in `REPLY`/`reply`, never on
  stdout, because `$( )` forks and a fork per row costs more than the entire
  matcher. Sources that must fork (`git-branch`, `git-file`, `zoxide`) cache
  against `$HISTCMD` (and `$PWD`); file-backed sources (`make`, `npm-script`,
  `ssh-host`) cache against mtime via `zsh/stat`.
- **History matching stays in the parameter.** `${history[(R)pat]}` searches in
  place; expanding `$history` into an array to filter afterwards costs 4x the
  search and is what made an earlier attempt too slow to ship. Successive
  keystrokes narrow the previous match set rather than searching again.
- **Quote user text with `(b)` before using it as a pattern.** A `[` or `*`
  typed at the prompt is a character to match. An unquoted `[` in a hash
  subscript does not just make a character class — it makes the subscript read
  out values instead of keys.
- **Never interpolate a hash key inside `$(( ))`.** `pos[$c]` in arithmetic
  parses the key as an expression, and a history line with a stray `(` is a
  fatal, uncatchable error at the prompt. Read into a scalar first.
- **The ghost is `_zhimmer_zghost`, never `$POSTDISPLAY`.** `POSTDISPLAY` holds
  the ghost *and* every row of the menu. The accept keys (Right, Ctrl+E, End,
  Ctrl+Right) used to read the whole of it, so Ctrl+E on an open menu put the
  header rule and all its rows into `BUFFER` — which looked on screen exactly
  like the menu still being open, one Enter away from running the lot.
- **Wrap widgets by name, never bind by key.** Which widget backspace reaches
  depends on the keymap: with `EDITOR=nvim` zsh selects viins, where it is
  `vi-backward-delete-char` and `^U` is `vi-kill-line`. Only wrap widgets whose
  `$widgets[...]` entry is `builtin`, and copy the widget aside with `zle -A`
  rather than calling `zle .$w` — the dot-prefixed builtin behind a completion
  widget is zsh's own dumb completion, with none of compsys behind it.
- **The redraw guard is the safety net, not the widget list.**
  `_zhimmer_ghost_guard` on `line-pre-redraw` drops the ghost and stale rows
  whenever `BUFFER` diverges from what they were computed against.
  `ZHIMMER_REFRESH_WIDGETS` is a convenience that refreshes instead of dropping;
  a name missing from it is a degradation, not a bug.
- **A mode must be cleared at `line-init`, not only `line-finish`.** `Ctrl+C`
  never reaches `line-finish`, so a `Ctrl+R` search abandoned that way stayed
  on and the *next* line was still matching substrings and offering nothing but
  history. `_zhimmer_line_reset` is registered on both hooks.
- **`_zhimmer_search` is not cleared by `_zhimmer_zle_clear`.** That runs on
  every keystroke, which would end the search on the first character typed into
  it. It is cleared where a search actually ends: taking a row, and line
  init/finish.
- **The history cache is keyed on the anchor as well as the query.** Lines
  containing `git com` are a subset of lines containing `git`, and lines
  starting with one are a subset of lines starting with the other — but the two
  sets are not subsets of each other, so narrowing across a mode change answers
  from the wrong list.
- **The ghost must never survive line acceptance.** It lives in `POSTDISPLAY`,
  not `BUFFER`, so a suggestion still on screen at accept time shows a command
  the shell never runs. Cleared at `line-finish` as well as in the guard.
- **Tab owns the listing area, but only takes it back from zhimmer.** Clear
  zhimmer's own rows before completing; never clear zsh's, because zsh keeps one
  list across a run of Tabs and clearing on every press blanks the screen from
  the second Tab onward. Redraw zhimmer's list only when
  `_lastcomp[nmatches] == 1`.
- **Never bind the `move` + `vi-insert` macros in `menuselect` again.**
  `vi-insert` *toggles* interactive mode, so with the mode off — which is now
  the case, since `interactive` is deliberately not asked for — they would
  switch Tab's menu *into* it on the first arrow and bring the status row back.
  Only Esc and backspace belong there now.
- **Never override a zstyle the user has already set.** `_zhimmer_tame_lists`
  reads the whole `zstyle -L` table and skips anything already defined, on
  whatever context pattern it was written.
- **Settings live in one table.** `ZHIMMER_DEFAULTS` in `lib/complete.zsh` is
  read by `_zhimmer_cfg`, `_zhimmer_bool` and `zhimmer-doctor`; do not spell a
  default at a call site. It lives beside those functions rather than in the
  plugin file so the libraries can be sourced and tested on their own.
- **Row colour never goes into row text.** Escapes written into a string that
  something else lays out do render, but the layout measures the string it was
  handed and counts the escape bytes as width — the row pads short and
  truncates early. `region_highlight` works in offsets and cannot have that
  problem, which is the reason the menu is drawn here rather than by complist.
- **Everything in `POSTDISPLAY` is plain text.** Colour goes on
  with `region_highlight`, which works in character *offsets*, so escapes are
  never counted as width. Do not reuse `_zhimmer_header` there — it emits prompt
  escapes for `compadd -X`, and `POSTDISPLAY` is not prompt-expanded, so they
  land as literal characters the offsets then paint over. That bug shipped once
  during development and looked like a corrupted header.
- **`region_highlight` offsets are characters; `_zhimmer_row` pads by columns.**
  Not the same for wide characters: use `${#s}` for paint ranges and `${(m)#s}`
  only for layout.
- **Measure rows in columns, not characters.** `${(m)#s}` — a CJK or emoji row
  counted by character under-pads the selection bar and wraps onto a second
  line, which desynchronises the layout from the menu.
- **The prompt's exit status is baked into the string, never `%(?..)`.** The
  async half calls `zle reset-prompt` long after the command finished, and `$?`
  at that point describes the redraw — so a conditional prompt escape reports
  success on a line that failed. `_zhimmer_prompt_precmd` reads `$?` on its
  first line, before anything else can replace it.
- **Never take the branch with `${head##*/}`.** `refs/heads/feat/menu` returns
  `menu` — the wrong branch, silently, on exactly the names that carry the most.
  Strip the literal prefix instead. And `.git` is a *file* holding `gitdir: …`
  in a linked worktree or submodule, not always a directory.
- **The async child parses, and prints one short line.** That is what makes a
  single `read` on the handler side correct: a few bytes go out in one write,
  atomic under PIPE_BUF. Shipping raw `git status` back would arrive in chunks
  and need a reassembly buffer. The generation counter rides along so a result
  landing after a `cd` is recognised as stale and dropped.
- **Escape `%` in anything interpolated into `PROMPT`.** A branch named
  `feat/100%done` is otherwise read as a format specifier.
- **Bind now *and* after zsh-vi-mode's init — not one or the other.** zvm binds
  some of the same keys itself (`zvm_bindkey viins '^R'
  history-incremental-search-backward`, in `zvm_init`) and by default defers
  that init to the first precmd, after every plugin has loaded. So binding only
  at load time loses exactly the keys zvm also wants — Down and Ctrl+Space
  survived, Ctrl+R did not, which reads as one broken key rather than as a
  load-order problem. Binding only from `zvm_after_init_commands` loses
  everything under `ZVM_INIT_MODE=sourcing`, where those commands have already
  run. `_zhimmer_bindkeys` is idempotent, so it is called both ways.
- **Detect zsh-vi-mode on `ZVM_VERSION`.** It is `typeset -gr` at zvm's source
  time. `ZVM_INIT_MODE` and a `zvm_before_init` function are things the *user*
  may define, not things zvm defines — a detection built on those was false
  against a stock zsh-vi-mode and had never once been true.
- **`Esc` is bound inside the menu and deliberately nowhere else**: it is
  vi-mode's normal-mode switch and it prefixes every arrow-key escape sequence.

## Testing notes

`test/unit.zsh` covers anything that is a function of its arguments — ranking,
row layout, alias expansion, ghost precedence, the file parsers. Every parser is
split from its I/O (`_zhimmer_make_targets` vs `_zhimmer_make_load`) precisely so
it can be tested against a fixture. Prefer this file: a ranking bug fits in four
lines of assertion here and takes half an hour to reproduce in `screen.zsh`.

**`$history` lags a push.** `print -s foo` holds `foo` as the current line; it
does not appear in the parameter until another entry follows it. At a real
prompt that is right — everything up to the previous command is there — but in
a test it silently means the line you just wrote is not the one being ranked.
Push a throwaway entry after the one you care about.

A zsh arithmetic error is fatal rather than catchable, so `unit.zsh` traps exit
and prints `ABORTED` if it ends early. **A short run of `ok` lines is not a
pass** — check for the final count. That `TRAPEXIT` guards on `ZSH_SUBSHELL`,
because a `$( )` forks and the fork's exit runs the trap *inside* it, printing
the abort banner into whatever the substitution was capturing — the first test
to use one came back with the banner inside its temp directory path.

`test/screen.zsh` drives a real zsh through tmux. Three constraints, each of
which has already cost a wrong conclusion:

- Render through `tmux capture-pane -p`, not raw `zpty` bytes — zpty hands back
  every intermediate redraw interleaved, so cleared text is still in the stream
  and a stale-ghost bug reads exactly like a fixed one.
- Fake `HOME`, not `ZDOTDIR` — `/etc/zsh/zshenv` may set `ZDOTDIR`
  unconditionally (Gentoo does).
- Needles handed to `matches` are **zsh patterns**, so metacharacters bite:
  `(` groups rather than matching a literal paren, and a bare `|` is not
  alternation outside parentheses. Both silently fail against a value that
  plainly contains the text. Assert on a metacharacter-free substring, or
  escape it.
- Assert against the *current* prompt, not the whole pane. Turning a feature
  off does not erase the lines it already drew, and a whole-screen `refutes`
  reads that scrollback as proof it is still on. Send `clear` first.
- Never send Enter when driving a real config; the buffer holds a real command
  from history and it will run. Use `C-c`.

Each scenario gets a fresh shell: leaving `menuselect` requires Escape, which
with `EDITOR=nvim` also drops the shell into vi normal mode, where later
keystrokes are motions rather than text.

## Also

`README.md` is the design document, not just usage — it carries the reasoning
and the benchmark numbers behind the choices above, and is worth keeping in step
when behaviour changes.

`zhimmer-match/` is an empty, untracked `target/` tree left over from a Rust
helper dropped in commit `979f92a` ("switch to fully zsh"). It is not part of the
build and there is no `.gitignore`.
