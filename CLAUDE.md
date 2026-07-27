# dior CLI — project instructions

## What this is
A personal zsh CLI (`dior`) that wraps the [Dior's Builds](https://github.com/HarkiratMangat/Diors-Builds)
Discord bot's dev/deploy/observability workflow. Sourced by `~/.zshrc`; lives here, tracked in git.
Split out of `~/.zshrc` on 2026-07-27 11:10 EDT. See `README.md` for the user-facing surface and
`dior.zsh`'s header for the architecture, load order, and visual design rules.

## ⚠️ This project inherits Dior's Builds' conventions — deliberately
Harkirat's working agreement, git workflow, naming rules, and verification discipline apply here
**unchanged**. Do not invent separate conventions for this repo.

- **Working agreement / how Harkirat works:**
  `~/.claude/projects/-Applications-Diors-Builds/memory/user_working_agreement.md` — read it first.
- **Memory store:** the SAME canonical path,
  `~/.claude/projects/-Applications-Diors-Builds/memory/`. Do not create a separate store for this
  repo — a second store would fragment feedback that is about Harkirat, not about a codebase.
- **Session-start prompt + NON-NEGOTIABLES:** `/Applications/Claude Code/Diors-Builds/docs/SESSION-START.md`
  (including the hard gate: a `/rename` string + model/effort recommendation as the first output
  of every session).
- **Deferred work:** anything dior-CLI-specific that isn't being done now goes in
  `/Applications/Claude Code/Diors-Builds/docs/db-deferred-list.md`, same as the bot's own items.

### Git workflow (identical to Diors-Builds)
Branch → commit → **test** → push → PR → merge. Never push, merge, or deploy without asking first;
approval never carries over. Branch commits are free and need no approval.

- **Commit subjects and PR titles follow Conventional Commits v1.0.0**: `<type>(<scope>): <description>`,
  colon + one space, imperative, lowercase, no trailing period, `!` before the colon for breaking.
  Only the 11 standard types. Branch names are `<type>/<kebab-description>`.
- **Never rename a branch with an open PR** — GitHub auto-closes it and it cannot be reopened.
- **Commit identity is global now** (`dior <21996007+HarkiratMangat@users.noreply.github.com>`).
  Just `git commit` — never pass `-c user.email=...`, and never use Harkirat's real address. See
  memory `feedback_git_commit_identity`.
- Full lifecycle: `/Applications/Claude Code/Diors-Builds/docs/superpowers/specs/2026-07-24-git-branch-pr-workflow-design.md`

### Timestamps
Every date written in docs, memory, or code comments needs `YYYY-MM-DD HH:MM TZ` — not a bare date.

## Testing this repo — there is no test runner, so verify by EXECUTION
Shell config fails silently and at a distance, so "it looks right" is not evidence. What actually works:

- **`zsh -n <file>`** on every changed file — syntax check, catches unbalanced quotes in the guide
  heredocs, which is the most common breakage here.
- **`zsh -c 'source ~/.zshrc; ...'`** for behavior. Colors are gated on `[[ -t 1 ]]`, so without a
  tty the `DIOR_C_*` codes are empty — which makes this the RIGHT tool for before/after output
  diffing (no escape-byte noise), and the wrong one for checking how something looks.
- **`script -q /dev/null zsh -c '...'`** when you need a real pty to see the actual colors.
  ⚠️ It fails with `tcgetattr: Operation not supported on socket` depending on what stdin is —
  if output comes back as that error, fall back to plain `zsh -c` rather than trusting an empty result.
- **`zsh -i -c '...'`** is the only way to verify tab-completion, since `compdef` needs an
  interactive shell. Check `${_comps[dior]}` resolves to `_dior`.
- **Never test destructive paths against the real thing.** Point `DIOR_BOT_DIR` at a stub directory
  containing fake `scripts/vmstatus.sh`, `scripts/vmpeaks.sh` and `scripts/devCommands.js` that just
  echo — otherwise `bot check` SSHes to the live GCP VM. Before exercising `bot dev kill`, run
  `pgrep -fl "env-file=.env.dev.*index.js"` to confirm you won't kill a dev bot Harkirat is using.
- **Prove refactors with an output diff.** Capture every menu, guide, and error path before and
  after, and diff them. That is what proved the `~/.zshrc` extraction was behavior-neutral.

## Structural invariants — don't break these
- **`core.zsh` must load first.** Guide text is built at SOURCE time (the `${DIOR_C_*}` codes expand
  when `_dior_register` is called, not when the guide prints), so the colors and `_dior_register`
  must already exist. `dior.zsh` enforces the order.
- **The `~/.zshrc` source line must stay below `compinit`.** Tab-completion calls `compdef`, which
  silently does nothing without it — the failure mode is "completion just doesn't work", with no error.
- **Adding a command means three places, all in one change:** the `_dior_<group>_<name>` function, a
  `_dior_register` call, and a `DIOR_MENU_ORDER` entry (plus `DIOR_SUBOPTS` if it takes options).
  Miss `DIOR_MENU_ORDER` and it silently won't appear in the menu or tab-complete.
- **zsh array subscripts:** always assign via a variable/positional (`arr[$var]=y`), never a literal
  quoted string (`arr["bot x"]=y`) — zsh stores the quote characters in the key and every later
  lookup silently misses. `_dior_register` exists so nothing else has to remember this.
- **`local` outside a function doesn't scope** — it leaks a permanent global into every terminal.
  Wrap guide-building scratch variables in an anonymous function: `() { local X=...; ... }`.
- **`printf "%-Ns"` padding counts the substituted argument's visible characters, not ANSI bytes in
  the surrounding format string** — so color codes belong in the FORMAT, never inside a padded value.
  A column whose value is identical on every row needs no padding at all.

## The option grammar — the one rule the whole UI rests on
> bare word = **MODE** (mutually exclusive, pick one) · `--flag` = **combinable** (stacks freely)

The shape tells you whether options combine. Any new option must pick a shape that matches how it
actually behaves — that is what keeps the surface learnable instead of arbitrary. Commands whose
every mode is consequential (`bot vm`, `update`) have no default action and print their guide when
invoked bare.
