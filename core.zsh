# ==============================================================================
# dior CLI — core.zsh
# ==============================================================================
# Config, colors, the help manifest, shared helpers, and the dior() dispatcher.
#
# Loaded by ~/.config/dior/dior.zsh, which ~/.zshrc sources. Split out of
# ~/.zshrc on 2026-07-27 11:10 EDT (it had grown to 675 of that file's 723 lines, with no
# version control and no backup) — a pure relocation, no behavior change. See
# dior.zsh for the architecture overview and the load order these files rely on.

# Global (not `local`) because every _dior_* function below needs it, not just
# the dispatcher. Fixed repo path -- never re-derive this from pwd/$0.
DIOR_BOT_DIR="/Applications/Claude Code/Diors-Builds"

# Color codes for the help/menu system, computed once when this file is sourced.
# Not re-checked per dior-invocation -- .zshrc only ever loads in an interactive
# terminal, so this is always accurate at startup. If a single command's output
# later gets piped/redirected, the codes still print; for a personal interactive
# tool that's an acceptable tradeoff against the complexity of re-deriving this
# on every call just to handle that rare case.
if [[ -t 1 ]]; then
    DIOR_C_RESET=$'\e[0m'
    DIOR_C_TITLE=$'\e[1;36m'   # bold cyan   -- opening divider + guide titles
    DIOR_C_FOOT=$'\e[2;36m'    # dim cyan    -- CLOSING divider only
    DIOR_C_HEAD=$'\e[1;35m'    # bold magenta -- section headers (USAGE:, etc.)
    DIOR_C_CMD=$'\e[32m'       # green       -- command names, bullet markers
    DIOR_C_ARG=$'\e[33m'       # yellow      -- <required>/[optional] argument placeholders
    DIOR_C_WARN=$'\e[1;33m'    # bold yellow -- every ⚠️ line, always
    DIOR_C_DIM=$'\e[2m'        # dim         -- '->' separators, every parenthetical aside
else
    DIOR_C_RESET="" DIOR_C_TITLE="" DIOR_C_FOOT="" DIOR_C_HEAD="" DIOR_C_CMD="" DIOR_C_ARG="" DIOR_C_WARN="" DIOR_C_DIM=""
fi

typeset -gA DIOR_HELP_SUMMARY   # key: "group name" (e.g. "bot commit") -> one-line menu blurb
typeset -gA DIOR_HELP_DETAIL    # key: "group name" -> full `dior help group name` guide text

# The single source of truth for DISPLAY order (menu, tab-completion, "did you
# mean" lists) -- deliberately NOT alphabetical. Grouped by workflow instead of
# spelling: local dev -> pre-flight/ship -> observe -> housekeeping. Alphabetical
# sort had put 'bot baseline' at the top and 'bot status' at the bottom despite
# both being the same kind of thing -- this fixes that. DIOR_MENU_BREAK_AFTER
# marks which entries get a blank line after them, visually separating the
# clusters. Every _dior_register'd key MUST appear here exactly once, or it
# silently won't show in the menu or tab-complete (parity checked by hand via
# `rg` after edits -- see the verification steps run alongside this change).
typeset -ga DIOR_MENU_ORDER
DIOR_MENU_ORDER=(
    "bot dev" "bot commit"
    "bot baseline" "bot deploy" "bot restart"
    "bot status" "bot logs" "bot peaks"
    "bot commands"
    "update brew" "update uv" "update pipx" "update pip3" "update npm" "update all"
)
typeset -gA DIOR_MENU_BREAK_AFTER
DIOR_MENU_BREAK_AFTER=(
    "bot commit" 1
    "bot restart" 1
    "bot peaks" 1
)

# Registers one command's help text under both maps in a single call.
# NOTE: always assign array keys via a variable/positional-param ($1, not a literal
# "bot commit" string) -- zsh stores literal quoted-string subscripts including the
# quote characters themselves, silently breaking every later lookup. Verified live
# 2026-07-26: `arr["bot x"]=y` produces a key that doesn't match `${arr[bot x]}`;
# `arr[$var]=y` with var="bot x" works correctly. This function exists specifically
# so nothing outside it has to remember that gotcha.
_dior_register() {
    DIOR_HELP_SUMMARY[$1]="$2"
    DIOR_HELP_DETAIL[$1]="$3"
}

# Shared yes/no gate for anything that shouldn't run from a typo alone (commit,
# deploy, restart). Added 2026-07-27 07:38 EDT after 'dior bot commit -help' (single dash,
# not '--help'/'-h') got silently read as the commit TITLE and committed for
# real -- a flag typo has no reason to be extra-dangerous just because this tool
# didn't ask first. Only bare 'y'/'yes' (any case) proceeds; anything else,
# including just hitting Enter, cancels.
_dior_confirm() {
    local reply
    printf "${DIOR_C_WARN}%s${DIOR_C_RESET} [y/N]: " "$1"
    read -r reply
    case "$reply" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

# ==============================================================================
# ⚡️ THE EXECUTION ENGINE
# ==============================================================================
# This defines a custom Zsh function named 'dior'. A function acts like a mini-program
# that can accept arguments (unlike a standard alias). It resolves "$1 $2" (e.g.
# 'bot' and 'deploy') to a _dior_<group>_<name> function and calls it -- no case
# list to keep updated by hand when a new command gets added.
dior() {
    # Bare `dior`, no args at all -- just show the menu, no need to feel wanted.
    if [ -z "$1" ]; then
        dior help
        return
    fi

    # Accept --help/-h as a trailing flag anywhere (e.g. `dior bot dev --help`,
    # `dior bot --help`, `dior --help`) -- normalizes to the same path as
    # `dior help bot dev`. Checks the LAST arg specifically (zsh's ${@[-1]}),
    # not a fixed position, so it works regardless of how many args precede it.
    if [ "${@[-1]}" = "--help" ] || [ "${@[-1]}" = "-h" ]; then
        dior help "${@[1,-2]}"
        return
    fi

    if [ "$1" = "help" ]; then
        if [ -z "$2" ]; then
            _dior_print_menu
        else
            _dior_show_help "$2" "$3"
        fi
        return
    fi

    local fn="_dior_${1}_${2}"
    if [ -n "$2" ] && typeset -f "$fn" >/dev/null 2>&1; then
        "$fn" "$@"
    else
        # Unrecognized command -- try to catch the likely mistake (missing
        # group, typo'd subcommand) before bouncing to the full menu.
        if ! _dior_suggest "$1" "$2"; then
            dior help
        fi
    fi
}
