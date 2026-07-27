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
    DIOR_C_ARG=$'\e[33m'       # yellow      -- <required> argument placeholders
    DIOR_C_OPT=$'\e[94m'       # bright blue -- [optional] anything: modes, flags, args
    DIOR_C_WARN=$'\e[1;33m'    # bold yellow -- every ⚠️ line, always
    DIOR_C_DIM=$'\e[2m'        # dim         -- '->' separators, every parenthetical aside
else
    DIOR_C_RESET="" DIOR_C_TITLE="" DIOR_C_FOOT="" DIOR_C_HEAD="" DIOR_C_CMD="" DIOR_C_ARG="" DIOR_C_OPT="" DIOR_C_WARN="" DIOR_C_DIM=""
fi

typeset -gA DIOR_HELP_SUMMARY   # key: "group name" (e.g. "bot commit") -> one-line menu blurb
typeset -gA DIOR_HELP_DETAIL    # key: "group name" -> full `dior help group name` guide text

# The single source of truth for DISPLAY order (menu, tab-completion, "did you
# mean" lists) -- deliberately NOT alphabetical. Grouped by workflow: local dev
# -> save work -> change the remote -> observe the remote -> housekeeping.
#
# Consolidated 2026-07-27 11:10 EDT from 15 entries to 5. Before this, the menu
# mixed two different kinds of thing under one list: `update brew` was modeled
# as a top-level COMMAND while `bot dev nowatch` was a SUB-OPTION, despite being
# the same kind of thing (one of several mutually-exclusive modes of one
# command). Now sub-options are sub-options everywhere -- they live in
# DIOR_SUBOPTS below, and this array only ever lists real commands.
typeset -ga DIOR_MENU_ORDER
DIOR_MENU_ORDER=(
    "bot dev"
    "bot commit"
    "bot vm" "bot check"
    "update"
)
typeset -gA DIOR_MENU_BREAK_AFTER
DIOR_MENU_BREAK_AFTER=(
    "bot dev" 1
    "bot commit" 1
)

# Every command's valid sub-options, in the order they should be offered.
# ONE source feeding both tab-completion and the "did you mean" suggester, so
# adding an option to a command can't drift out of sync with either.
#
# The grammar these encode is uniform across every command that has options:
#   bare            -> the command's default (or its guide, where every mode is
#                      consequential -- see `bot vm` and `update`)
#   MODE (bare word)-> mutually exclusive; you can only ever pick one
#   --flag          -> independently combinable with a mode and with each other
# The SHAPE tells you whether options combine. That's the whole rule.
typeset -gA DIOR_SUBOPTS
DIOR_SUBOPTS=(
    "bot dev"   "watch nowatch kill --list --clear"
    "bot vm"    "deploy restart"
    "bot check" "status baseline --peaks --logs --all"
    "update"    "brew uv pipx pip3 npm all"
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

# Shared "you typed an option that doesn't exist" reporter. Pulls the valid list
# straight from DIOR_SUBOPTS so it can never list a stale set of options.
_dior_bad_opt() {
    local key="$1" bad="$2"
    if [ -n "$bad" ]; then
        echo "${DIOR_C_WARN}⚠️  '$bad' isn't a valid option for 'dior $key'${DIOR_C_RESET}"
    fi
    echo "   Valid options: ${DIOR_C_OPT}${DIOR_SUBOPTS[$key]}${DIOR_C_RESET}"
    echo "   Full guide:    ${DIOR_C_CMD}dior help $key${DIOR_C_RESET}"
}

# ==============================================================================
# ⚡️ THE EXECUTION ENGINE
# ==============================================================================
# This defines a custom Zsh function named 'dior'. A function acts like a mini-program
# that can accept arguments (unlike a standard alias). It resolves "$1 $2" (e.g.
# 'bot' and 'vm') to a _dior_<group>_<name> function and calls it -- no case
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
    elif [ -z "$2" ] && typeset -f "_dior_${1}" >/dev/null 2>&1; then
        # A single-word command (currently just `dior update`) invoked bare.
        # Deliberately gated on an EMPTY $2: without that, `dior update nope`
        # would fall through to _dior_update and be silently accepted instead of
        # being reported as the typo it is. Verified 2026-07-27 11:10 EDT that a
        # _dior_<group> fallback was previously unreachable at all, because the
        # old dispatcher required a non-empty $2 before trying anything.
        "_dior_${1}" "$@"
    else
        # Unrecognized command -- try to catch the likely mistake (missing
        # group, typo'd subcommand) before bouncing to the full menu.
        if ! _dior_suggest "$1" "$2"; then
            dior help
        fi
    fi
}
