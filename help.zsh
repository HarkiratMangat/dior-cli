# ==============================================================================
# dior CLI — help.zsh
# ==============================================================================
# The help engine: menu rendering, guide lookup, the suggester, tab-completion.
#
# Loaded by ~/.config/dior/dior.zsh, which ~/.zshrc sources. Split out of
# ~/.zshrc on 2026-07-27 11:10 EDT (it had grown to 675 of that file's 723 lines, with no
# version control and no backup) — a pure relocation, no behavior change. See
# dior.zsh for the architecture overview and the load order these files rely on.

# ==============================================================================
# 📖 THE HELP ENGINE
# ==============================================================================

# Prints the command menu. With no argument: everything, grouped. With a group
# name ("bot"): just that group's commands -- this is what makes `dior help bot`
# / `dior bot --help` a scoped listing instead of the full wall of text.
#
# Note there is no "update" filter case anymore: `update` became a single
# command with sub-options rather than a group of six commands, so
# `dior help update` now resolves to its GUIDE (via _dior_show_help) and never
# reaches this function.
_dior_print_menu() {
    local filter="$1"
    local key group header lastheader="" padded

    # Column width computed from the actual keys being printed this call, not a
    # hardcoded number -- a fixed %-11s was sized for the original shorter
    # command set and silently went stale the moment `legal deploy` (12 chars)
    # shipped: it overflowed the width, so ITS arrow landed one column right of
    # every other row's, and nothing caught it because printf doesn't warn on
    # overflow. Recomputing this from ${#key} means a longer command name in the
    # future re-aligns the whole listing instead of quietly drifting again.
    local width=0
    for key in "${DIOR_MENU_ORDER[@]}"; do
        [ -n "$filter" ] && [ "${key%% *}" != "$filter" ] && continue
        (( ${#key} > width )) && width=${#key}
    done

    echo "${DIOR_C_TITLE}========================================================${DIOR_C_RESET}"
    if [ -z "$filter" ]; then
        echo "${DIOR_C_TITLE}👑 DIOR TERMINAL CLI HUB${DIOR_C_RESET}"
        echo "${DIOR_C_TITLE}========================================================${DIOR_C_RESET}"
        echo "Usage: dior <group> <command> ${DIOR_C_OPT}[mode] [--flags]${DIOR_C_RESET}"
    else
        # DIOR_GROUP_HEADER, not a hardcoded label -- this used to always print
        # "🤖 BOT COMMANDS" here regardless of which group was actually asked for,
        # so `dior help legal`/`dior help text` (once those groups were reachable
        # at all -- see _dior_show_help) showed the wrong title.
        echo "${DIOR_C_TITLE}${DIOR_GROUP_HEADER[$filter]:-${(U)filter} COMMANDS}${DIOR_C_RESET}"
        echo "${DIOR_C_TITLE}========================================================${DIOR_C_RESET}"
    fi
    echo ""

    # Walks DIOR_MENU_ORDER (hand-curated, workflow-grouped) rather than sorting
    # DIOR_HELP_SUMMARY's keys -- that's the fix for commands that belong
    # together landing next to each other instead of wherever the alphabet put
    # them. A header prints once per HEADER TEXT, not once per raw group word --
    # several single-word commands (doctor, repo, cd, notes, branches) share one
    # "WORKSPACE COMMANDS" umbrella in DIOR_GROUP_HEADER despite each being its
    # own distinct $group (a single-word command's "group" is just its own
    # name). Deduping on the group word instead of the resolved header text is
    # the exact bug that produced triplicate "MAINTENANCE COMMANDS" headers
    # before this function's first fix -- reproducing it here was almost a
    # repeat of that mistake, caught before it shipped rather than after.
    # DIOR_MENU_BREAK_AFTER adds a blank line after specific keys to separate
    # clusters WITHIN a group. Padding is computed on the PLAIN key first, then
    # wrapped in color -- coloring inside a printf width field throws off
    # alignment, since the invisible escape bytes count toward the field width.
    for key in "${DIOR_MENU_ORDER[@]}"; do
        group="${key%% *}"
        [ -n "$filter" ] && [ "$group" != "$filter" ] && continue
        header="${DIOR_GROUP_HEADER[$group]:-${(U)group} COMMANDS}"
        if [ -z "$filter" ] && [ "$header" != "$lastheader" ]; then
            [ -n "$lastheader" ] && echo ""
            echo "${DIOR_C_HEAD}${header}:${DIOR_C_RESET}"
            lastheader="$header"
        fi
        padded=$(printf "%-${width}s" "$key")
        printf "  ${DIOR_C_CMD}%s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" "$padded" "$DIOR_HELP_SUMMARY[$key]"
        [ -n "${DIOR_MENU_BREAK_AFTER[$key]}" ] && echo ""
    done

    # Deliberately plain sentences, not a second "label -> desc" table -- this
    # is usage instruction, not a command reference, and forcing it into the
    # same column-aligned shape as the list above (at a totally different,
    # much wider column width, since these labels are much longer) is exactly
    # what looked broken here before.
    echo ""
    if [ -z "$filter" ]; then
        echo "${DIOR_C_HELP}💡 NEED HELP?${DIOR_C_RESET}"
        echo "  ${DIOR_C_HELP}Add${DIOR_C_RESET} ${DIOR_C_CMD}--help${DIOR_C_RESET} ${DIOR_C_HELP}or${DIOR_C_RESET} ${DIOR_C_CMD}-h${DIOR_C_RESET} ${DIOR_C_HELP}to any command for its full guide${DIOR_C_RESET} ${DIOR_C_DIM}(e.g. ${DIOR_C_RESET}${DIOR_C_CMD}dior bot dev --help${DIOR_C_RESET}${DIOR_C_DIM})${DIOR_C_RESET}"
        echo "  ${DIOR_C_HELP}Or narrow this whole list with${DIOR_C_RESET} ${DIOR_C_CMD}dior help bot${DIOR_C_RESET}"
        echo ""
        echo "  ${DIOR_C_DIM}Options come in two shapes, and the shape tells you whether they combine:${DIOR_C_RESET}"
        echo "  ${DIOR_C_DIM}a bare word is a MODE (pick one), a ${DIOR_C_RESET}${DIOR_C_OPT}--flag${DIOR_C_RESET}${DIOR_C_DIM} stacks with anything else${DIOR_C_RESET}"
    else
        echo "${DIOR_C_HELP}💡 Add${DIOR_C_RESET} ${DIOR_C_CMD}--help${DIOR_C_RESET}/${DIOR_C_CMD}-h${DIOR_C_RESET} ${DIOR_C_HELP}to any command above for its full guide${DIOR_C_RESET} ${DIOR_C_DIM}(e.g. ${DIOR_C_RESET}${DIOR_C_CMD}dior $filter <name> --help${DIOR_C_RESET}${DIOR_C_DIM})${DIOR_C_RESET}"
    fi
    echo "${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"
}

_dior_show_help() {
    local group="$1" name="$2"
    # Key is built WITHOUT a trailing space when there's no $2 -- `dior help
    # update` must look up "update", not "update ". Single-word commands own a
    # guide now, so this is load-bearing rather than cosmetic.
    local key="$1${2:+ $2}"

    if [ -n "${DIOR_HELP_DETAIL[$key]}" ]; then
        echo "${DIOR_HELP_DETAIL[$key]}"
        return
    fi
    # Group given, no specific command -- show that group's own mini-menu instead
    # of either the full wall-of-everything or a vague nudge. Generalized from a
    # hardcoded 'bot'-only check (which meant `dior help legal`/`dior help text`
    # fell all the way through to "isn't a recognized dior command") to: does
    # DIOR_MENU_ORDER contain any REAL multi-word entry under this group? This
    # is what correctly excludes single-word commands like `update`, which own
    # their OWN guide (caught by the DIOR_HELP_DETAIL lookup above already) and
    # have no "mini-menu" of their own to show.
    if [ -z "$name" ]; then
        local k
        for k in "${DIOR_MENU_ORDER[@]}"; do
            if [ "${k%% *}" = "$group" ] && [ "$k" != "$group" ]; then
                _dior_print_menu "$group"
                return
            fi
        done
    fi
    # Anything else falls to _dior_suggest -- this is what catches 'dior help dev'
    # (forgot the 'bot' group) instead of silently dumping the full menu with no
    # explanation, which is the exact confusion this was built to fix.
    if _dior_suggest "$group" "$name"; then
        return
    fi
    _dior_print_menu
}

# Figures out what the user probably meant when a group/name pair didn't
# resolve to a real command -- either from `dior help <x> <y>` or from a
# straight `dior <x> <y>` that didn't match any _dior_<x>_<y> function.
# Returns 0 (and prints a specific, actionable line) when it found something
# worth suggesting; returns 1 (generic "not recognized") when it has nothing,
# so callers know whether to also fall back to the full menu.
_dior_suggest() {
    local group="$1" name="$2"
    local k matches=()

    # Case 1: a single-word COMMAND that takes sub-options (e.g. `dior update
    # nope`). Not a group -- so the useful answer is its option list, not a
    # list of commands.
    if [ -n "${DIOR_SUBOPTS[$group]}" ] && [ -z "${DIOR_SUBOPTS[$group $name]}" ]; then
        _dior_bad_opt "$group" "$name"
        return 0
    fi

    # Case 2: right group, but the subcommand doesn't exist (missing or
    # misspelled). Walks DIOR_MENU_ORDER (not a raw key sort) so this list reads
    # in the same workflow order as the menu, not alphabetically.
    if [ "$group" = "bot" ]; then
        for k in "${DIOR_MENU_ORDER[@]}"; do
            [ "${k%% *}" = "$group" ] && matches+=("${k#* }")
        done
        if [ -n "$name" ]; then
            echo "${DIOR_C_ERROR}⚠️  '$group $name' isn't a command${DIOR_C_RESET}"
        else
            echo "${DIOR_C_ERROR}⚠️  '$group' needs a subcommand${DIOR_C_RESET}"
        fi
        echo "   Valid '$group' subcommands: ${DIOR_C_CMD}${matches[*]}${DIOR_C_RESET}"
        return 0
    fi

    if [ -z "$name" ]; then
        # No recognized group at all -- "$group" might be a bare subcommand name
        # typed without its group, e.g. 'dev' instead of 'bot dev' (the exact
        # mistake that prompted this whole function).
        for k in "${DIOR_MENU_ORDER[@]}"; do
            [ "${k#* }" = "$group" ] && matches+=("$k")
        done
        if [ ${#matches} -eq 1 ]; then
            echo "${DIOR_C_ERROR}⚠️  '$group' isn't a command by itself${DIOR_C_RESET} — did you mean ${DIOR_C_CMD}'dior ${matches[1]}'${DIOR_C_RESET}?"
            return 0
        elif [ ${#matches} -gt 1 ]; then
            echo "${DIOR_C_ERROR}⚠️  '$group' is ambiguous${DIOR_C_RESET} — it matches: ${DIOR_C_CMD}${matches[*]}${DIOR_C_RESET}"
            return 0
        fi
    fi

    echo "${DIOR_C_ERROR}⚠️  '$group${name:+ }$name' isn't a recognized dior command${DIOR_C_RESET}"
    return 1
}

# Tab-completion for `dior`. Derives EVERY candidate list from the same two
# arrays that drive the menu and the suggester (DIOR_MENU_ORDER, DIOR_SUBOPTS)
# rather than a separately hand-typed list -- add a command or an option and it
# tab-completes for free. compinit (needed for compdef) is set up in ~/.zshrc,
# in the UV & PYTHON TOOLING SETUP section that runs before it sources dior.
#
# REWRITTEN 2026-08-03 22:23 EDT to be fully generic -- the previous version
# hardcoded a branch each for 'bot' and 'update' only, so 'legal' (shipped
# 2026-07-29 18:24 EDT) and 'text' (shipped 2026-08-03 21:24 EDT) never
# tab-completed at ALL, and
# position 2 itself only ever offered "bot update help", missing every group
# added since. Genuinely untestable by a quick glance since compdef needs an
# interactive shell (`zsh -i -c '...'`) to exercise at all -- that's almost
# certainly how this drifted unnoticed for a week.
_dior() {
    local -a top_level group_cmds
    local -A seen
    local entry group key

    # Every distinct group prefix in DIOR_MENU_ORDER (bot, legal, text, ...),
    # each exactly once, in the order it first appears.
    for entry in "${DIOR_MENU_ORDER[@]}"; do
        group="${entry%% *}"
        if [ -z "${seen[$group]}" ]; then
            top_level+=("$group")
            seen[$group]=1
        fi
    done

    if (( CURRENT == 2 )); then
        compadd "${top_level[@]}" help
        return
    fi

    if [ "${words[2]}" = "help" ]; then
        if (( CURRENT == 3 )); then
            compadd "${top_level[@]}"
        elif (( CURRENT == 4 )); then
            group_cmds=()
            for entry in "${DIOR_MENU_ORDER[@]}"; do
                [ "${entry%% *}" = "${words[3]}" ] && [ "$entry" != "${words[3]}" ] && group_cmds+=("${entry#* }")
            done
            (( ${#group_cmds} > 0 )) && compadd -a group_cmds
        fi
        return
    fi

    # Real multi-word groups (bot, legal, text, ...): every entry under this
    # group's prefix, subcommand word stripped off.
    for entry in "${DIOR_MENU_ORDER[@]}"; do
        [ "${entry%% *}" = "${words[2]}" ] && [ "$entry" != "${words[2]}" ] && group_cmds+=("${entry#* }")
    done

    if (( ${#group_cmds} > 0 )); then
        if (( CURRENT == 3 )); then
            compadd -a group_cmds -- --help -h
        elif (( CURRENT >= 4 )); then
            key="${words[2]} ${words[3]}"
            [ -n "${DIOR_SUBOPTS[$key]}" ] && compadd ${=DIOR_SUBOPTS[$key]} --help -h
        fi
    elif [ -n "${DIOR_SUBOPTS[${words[2]}]}" ]; then
        # Single-word command with its own sub-options (currently just `update`)
        # -- options live at position 3, one earlier than a real group's, since
        # there's no subcommand word to skip past.
        (( CURRENT == 3 )) && compadd ${=DIOR_SUBOPTS[${words[2]}]} --help -h
    fi
}
compdef _dior dior
