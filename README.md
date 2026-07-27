# dior

A personal zsh CLI for the [Dior's Builds](https://github.com/HarkiratMangat/Diors-Builds) Discord
bot — local dev bot, git commits, GCP VM deploys, and VM observability behind one command.

```
dior bot dev     [watch|nowatch|kill] [--list|--clear]
dior bot commit  ['<Title>' ['<Body>']]
dior bot vm      <deploy|restart>
dior bot check   [status|baseline] [--peaks] [--logs [N]] [--all]
dior update      <brew|uv|pipx|pip3|npm|all>
```

## The grammar

Every command that takes options uses the same one:

| Shape | Meaning |
|---|---|
| bare word (`kill`, `deploy`, `status`) | a **mode** — mutually exclusive, pick one |
| `--flag` (`--peaks`, `--list`) | **combinable** — stacks with a mode and with other flags |
| no options at all | the command's safe default, or its guide where every mode is consequential |

The *shape tells you whether options combine*, so there's nothing arbitrary to memorize.
`dior bot vm` and `dior update` deliberately have no default action — every one of their modes
touches something real (the live prod bot; five package managers), so a bare invocation prints
the guide instead of picking for you.

## Browsing

Bare `dior` opens an interactive browser: arrow between commands, build up options, and run the
result without typing it.

| Key | |
|---|---|
| `↑` `↓` | move between commands |
| `Tab` | cycle the highlighted command's mode — including "none", which means its bare behavior |
| `←` `→` | move the cursor along that command's flags |
| `Space` | toggle the flag under the cursor |
| `+` `-` | step a flag's count by 5 (`--logs`, 5–500) |
| `?` | that command's full guide |
| `Enter` | run it |
| `q` | quit |

A preview line shows the literal command that will run, so the browser teaches the CLI rather than
replacing it. Options the CLI would reject can't be selected — picking `watch` greys out
`--list`/`--clear`, since the dev bot re-registers its slash commands on every boot. Commands with
no default on purpose (`bot vm`, `update`) won't run until you pick a mode, and the confirm gates on
`bot commit` / `bot vm` still fire, because `Enter` goes through the normal dispatcher.

It falls back to the printed menu when stdout isn't a terminal or the window is under 24 rows.

## Help

`dior help` for the printed menu, `dior help bot` to narrow it, and `--help`/`-h` on any command
for its full guide (`dior bot check --help`). Tab-completion covers groups, commands, and every
sub-option. Unrecognized input routes to a suggester rather than silently dumping the menu —
`dior help dev` tells you that you meant `dior bot dev`.

`dior help` stays a plain printed reference — bare `dior` is the interactive surface — so it can
still be piped, screenshotted, and diffed before/after a refactor.

## Install

```sh
git clone git@github.com:HarkiratMangat/dior-cli.git ~/.config/dior
```

Then add to `~/.zshrc`, **below** wherever `compinit` runs (tab-completion calls `compdef`, which
does nothing without it):

```sh
[ -f ~/.config/dior/dior.zsh ] && source ~/.config/dior/dior.zsh
```

The directory is location-independent — `dior.zsh` resolves its own path via `${0:A:h}`, including
paths containing spaces — so only that one line is tied to where you put it.

`DIOR_BOT_DIR` in `core.zsh` points at the bot repo and is the one thing you'd change on a new
machine.

## Layout

| File | Contains |
|---|---|
| `dior.zsh` | loader; architecture, load-order, and design-rule documentation |
| `core.zsh` | config, colors, help manifest, `DIOR_SUBOPTS`, shared helpers, the `dior()` dispatcher |
| `help.zsh` | menu rendering, guide lookup, the suggester, tab-completion |
| `browse.zsh` | the interactive browser bare `dior` launches |
| `bot.zsh` | `bot dev` / `bot commit` / `bot vm` / `bot check` |
| `update.zsh` | the package-manager commands |

Adding a command means writing one `_dior_<group>_<name>` function, one `_dior_register` call, and
one `DIOR_MENU_ORDER` entry. Menu, guides, suggester, tab-completion and the browser all derive
from those — there's no fourth place to keep in sync. The one exception: if a command rejects some
combination of its *own* options, that rule must also be mirrored into `browse.zsh`'s constraint
tables, since the browser has to know it before the command is built.

## Notes

Stop a running dev bot with `Ctrl-\` (SIGQUIT) or `dior bot dev kill` from a second tab.

`bot commit`, `bot vm deploy` and `bot vm restart` all confirm before acting — added after
`dior bot commit -help` (single dash, so not recognized as a help flag) was read as the commit
title and committed for real.
