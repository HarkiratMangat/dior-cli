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

## Help

`dior` or `dior help` for the menu, `dior help bot` to narrow it, and `--help`/`-h` on any command
for its full guide (`dior bot check --help`). Tab-completion covers groups, commands, and every
sub-option. Unrecognized input routes to a suggester rather than silently dumping the menu —
`dior help dev` tells you that you meant `dior bot dev`.

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
| `bot.zsh` | `bot dev` / `bot commit` / `bot vm` / `bot check` |
| `update.zsh` | the package-manager commands |
| `scripts/` | dev utilities that aren't part of the CLI — see below |

## Colors

The whole palette lives in one `[[ -t 1 ]]` block at the top of `core.zsh`, as
`DIOR_C_*` variables. They use **256-color indices** (`\e[38;5;Nm`) rather than the 16 system
colors, deliberately: the system colors are theme-defined, so `\e[94m` rendered as an unreadably
dark blue on one profile. 256-color indices are fixed RGB and look the same everywhere.

`scripts/colorpick.zsh` auditions colors without touching anything — it only prints:

```sh
zsh scripts/colorpick.zsh                # every color, 1-255, in the real menu format
zsh scripts/colorpick.zsh 100-160        # a range, to narrow down
zsh scripts/colorpick.zsh --16 --grey    # system colors / the 24-step grey ramp
zsh scripts/colorpick.zsh --mix mode=183 arg=49 error=196b
```

`--mix` assigns a color per element (`title dividers usage cmd arg mode flag arrow desc help
warning error comment`) and prints before/after as full mock screens. Values take an optional
`b` (bold) or `d` (dim) suffix; `current` leaves an element alone.

When changing colors, the check is that **colors move and wording doesn't**: render every menu and
guide through plain `zsh -c` (no tty, so the color vars are empty and you get pure text) before and
after, and diff. Also confirm every variable is defined in *both* branches of the `[[ -t 1 ]]` test
— one missing from the `else` branch leaks escape codes into pipes.

Adding a command means writing one `_dior_<group>_<name>` function, one `_dior_register` call, and
one `DIOR_MENU_ORDER` entry. Menu, guides, suggester and tab-completion all derive from those —
there's no fourth place to keep in sync.

## Notes

Stop a running dev bot with `Ctrl-\` (SIGQUIT) or `dior bot dev kill` from a second tab.

`bot commit`, `bot vm deploy` and `bot vm restart` all confirm before acting — added after
`dior bot commit -help` (single dash, so not recognized as a help flag) was read as the commit
title and committed for real.
