# ⏸️ This branch is parked — indefinitely paused, do not merge

**Parked 2026-07-27 12:30 EDT.** The interactive arrow-key command browser on this branch is
complete and working. It was cancelled anyway, on purpose. This file exists so checking the branch
out tells you everything without needing GitHub history.

`main` has moved on since. **This branch conflicts with `main`** — both changed `core.zsh`. See
"If you're reviving this" at the bottom before touching anything.

---

## What it does

Bare `dior` opens a browser; `dior help` stays exactly as it was — a plain printed reference, so it
can still be piped, screenshotted, and diffed.

| Key | |
|---|---|
| `↑` `↓` | move between commands |
| `Tab` | cycle the mode — including "none", which means the command's bare behavior |
| `←` `→` | move the cursor along that command's flags |
| `Space` | toggle the flag under the cursor |
| `+` `-` | step `--logs` by 5 (range 5–500) |
| `?` | that command's full guide |
| `Enter` | run it |
| `q` | quit |

The whole thing is built around one rule: **a preview line always shows the literal command that
will run**, so the browser teaches the CLI instead of replacing it. Everything else follows from
that — combinations the CLI would reject can't be selected, because a preview that doesn't run
would break the only promise the screen makes.

Also: `bot vm` and `update` refuse to run until you pick a mode, mirroring their deliberate lack of
a default; `Enter` goes through the normal dispatcher so the confirm gates still fire; it falls
back to the printed menu in a non-tty or a window under 24 rows.

## Why it was cancelled

Not because it didn't work. Because of `browse.zsh`'s constraint tables.

The browser needs to know which option combinations are invalid **before** you build a command.
The validators in `bot.zsh` only know **after** one is typed. There's no way to share one copy
without making those validators introspectable, which is a much bigger change than this feature
justified — so the rules at `bot.zsh:38` and `bot.zsh:55` exist in two places, and every future
option has to be added to both.

That's permanent drift risk, paid forever, for a screen that would be opened occasionally. Roughly
370 lines standing behind a keystroke. Harkirat called it, and the call was right.

## Three zsh traps found building this

All three are documented in `CLAUDE.md` on `main` — they are real zsh behavior and will bite again.

1. **`local a="$1" b="$a"` does not work.** zsh declares every name in a `local` statement *before*
   assigning any of them, so `$a` on the right is the freshly-emptied local, not `$1`. Bash
   evaluates left-to-right, so the bug reads as correct code and reviews clean. This was in three
   functions at once; the symptom was a command line rendering as `dior ` with the name missing.
2. **A valueless `local` re-run in one scope echoes `name=value` to stdout**, silently corrupting
   any function that returns its result that way. Declare locals once, at the top.
3. **Composite associative subscripts fail on write.** `arr[$a $b]=y` errors with `bad pattern`;
   reads tolerate it. Build the key into a variable first.

## What was verified, and what wasn't

Verified: 20 state-machine assertions; **all 43 reachable commands fed to the real dispatcher, 0
rejected** (the direct test of "the preview always runs"); 16 key sequences including both arrow
encodings and a lone Esc; non-tty fallback emits zero escape bytes; `dior help` byte-identical
across 260 lines; tab-completion still resolves to `_dior`. Nothing touched the live GCP VM or a
running dev bot — stubbed `DIOR_BOT_DIR`, `pgrep` returning empty so `kill` was unreachable.

**Not verified: the input loop itself** — the redraw arithmetic, cursor restore on every exit path,
and the `?`-guide round trip. Driving those needs a real pty with fed keystrokes, and `script -q
/dev/null` is unreliable on this machine. The parser and every state transition are covered; the
gluing between them is not. If you revive this, that's the first thing to test by hand.

## If you're reviving this

1. **Rebase onto `main` first.** This branched from `30789b4`, before the palette refresh (PR #2).
   Both changed `core.zsh`, so it will conflict.
2. `browse.zsh` predates `DIOR_C_HELP` and `DIOR_C_ERROR` and uses the old palette variables —
   update it to the current ones.
3. Re-run the verification above, then test the input loop in a real terminal.
4. Decide what to do about the duplicated constraint tables. That's the thing that killed it; if
   it isn't solved, it will kill it again.

Draft PR #3 was opened for this and closed the same day — a parked PR permanently showed a merge
conflict and added noise. The branch is the parking spot. **Don't delete it.**
