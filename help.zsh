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
# name ("bot" or "update"): just that group's commands -- this is what makes
# `dior help bot` / `dior bot --help` a scoped listing instead of the full wall
# of text.
_dior_print_menu() {
    local filter="$1"
    local key group lastgroup="" padded

    echo "${DIOR_C_TITLE}========================================================${DIOR_C_RESET}"
    if [ -z "$filter" ]; then
        echo "${DIOR_C_TITLE}👑 DIOR TERMINAL CLI HUB${DIOR_C_RESET}"
        echo "${DIOR_C_TITLE}========================================================${DIOR_C_RESET}"
        echo "Usage: dior <group> <command> [args]"
    elif [ "$filter" = "bot" ]; then
        echo "${DIOR_C_TITLE}🤖 BOT COMMANDS${DIOR_C_RESET}"
        echo "${DIOR_C_TITLE}========================================================${DIOR_C_RESET}"
    else
        echo "${DIOR_C_TITLE}🧹 MAINTENANCE COMMANDS${DIOR_C_RESET}"
        echo "${DIOR_C_TITLE}========================================================${DIOR_C_RESET}"
    fi
    echo ""

    # Walks DIOR_MENU_ORDER (hand-curated, workflow-grouped) rather than sorting
    # DIOR_HELP_SUMMARY's keys -- that's the fix for commands that belong
    # together (bot status / bot logs / bot peaks) landing next to each other
    # instead of wherever the alphabet put them. A group header prints once per
    # group (when unfiltered); DIOR_MENU_BREAK_AFTER adds a blank line after
    # specific keys to separate sub-clusters within a group. Padding is computed
    # on the PLAIN key first, then wrapped in color -- coloring inside a printf
    # width field throws off alignment, since the invisible escape bytes count
    # toward the field width.
    for key in "${DIOR_MENU_ORDER[@]}"; do
        group="${key%% *}"
        [ -n "$filter" ] && [ "$group" != "$filter" ] && continue
        if [ -z "$filter" ] && [ "$group" != "$lastgroup" ]; then
            [ -n "$lastgroup" ] && echo ""
            if [ "$group" = "bot" ]; then
                echo "${DIOR_C_HEAD}🤖 BOT COMMANDS:${DIOR_C_RESET}"
            else
                echo "${DIOR_C_HEAD}🧹 MAINTENANCE COMMANDS:${DIOR_C_RESET}"
            fi
            lastgroup="$group"
        fi
        padded=$(printf "%-15s" "$key")
        printf "  ${DIOR_C_CMD}%s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" "$padded" "$DIOR_HELP_SUMMARY[$key]"
        [ -n "${DIOR_MENU_BREAK_AFTER[$key]}" ] && echo ""
    done

    # Deliberately plain sentences, not a second "label -> desc" table -- this
    # is usage instruction, not a command reference, and forcing it into the
    # same column-aligned shape as the list above (at a totally different,
    # much wider column width, since these labels are much longer) is exactly
    # what looked broken here before. Command examples stay colored so they're
    # still easy to spot, just not pretending to be rows in the table above.
    echo ""
    if [ -z "$filter" ]; then
        echo "💡 NEED HELP?"
        echo "  Add ${DIOR_C_CMD}--help${DIOR_C_RESET} or ${DIOR_C_CMD}-h${DIOR_C_RESET} to any command for its full guide ${DIOR_C_DIM}(e.g. ${DIOR_C_RESET}${DIOR_C_CMD}dior bot dev --help${DIOR_C_RESET}${DIOR_C_DIM})${DIOR_C_RESET}."
        echo "  Or narrow this whole list with ${DIOR_C_CMD}dior help <group>${DIOR_C_RESET} ${DIOR_C_DIM}(e.g. ${DIOR_C_RESET}${DIOR_C_CMD}dior help bot${DIOR_C_RESET}${DIOR_C_DIM})${DIOR_C_RESET}."
    else
        echo "💡 Add ${DIOR_C_CMD}--help${DIOR_C_RESET}/${DIOR_C_CMD}-h${DIOR_C_RESET} to any command above for its full guide ${DIOR_C_DIM}(e.g. ${DIOR_C_RESET}${DIOR_C_CMD}dior $filter <name> --help${DIOR_C_RESET}${DIOR_C_DIM})${DIOR_C_RESET}."
    fi
    echo "${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"
}

_dior_show_help() {
    local group="$1" name="$2" key="$1 $2"
    if [ -n "$name" ] && [ -n "${DIOR_HELP_DETAIL[$key]}" ]; then
        echo "${DIOR_HELP_DETAIL[$key]}"
        return
    fi
    if { [ "$group" = "bot" ] || [ "$group" = "update" ]; } && [ -z "$name" ]; then
        # Group given, no specific command -- show that group's own mini-menu
        # instead of either the full wall-of-everything or a vague nudge.
        _dior_print_menu "$group"
        return
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

    if [ "$group" = "bot" ] || [ "$group" = "update" ]; then
        # Right group, but the subcommand doesn't exist (missing or misspelled).
        # Walks DIOR_MENU_ORDER (not a raw key sort) so this list reads in the
        # same workflow order as the menu, not alphabetically.
        for k in "${DIOR_MENU_ORDER[@]}"; do
            [ "${k%% *}" = "$group" ] && matches+=("${k#* }")
        done
        if [ -n "$name" ]; then
            echo "${DIOR_C_WARN}⚠️  '$group $name' isn't a command.${DIOR_C_RESET} Valid '$group' subcommands: ${DIOR_C_CMD}${matches[*]}${DIOR_C_RESET}"
        else
            echo "${DIOR_C_WARN}⚠️  '$group' needs a subcommand.${DIOR_C_RESET} Valid '$group' subcommands: ${DIOR_C_CMD}${matches[*]}${DIOR_C_RESET}"
        fi
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
            echo "${DIOR_C_WARN}⚠️  '$group' isn't a command by itself${DIOR_C_RESET} — did you mean ${DIOR_C_CMD}'dior ${matches[1]}'${DIOR_C_RESET}?"
            return 0
        elif [ ${#matches} -gt 1 ]; then
            echo "${DIOR_C_WARN}⚠️  '$group' is ambiguous${DIOR_C_RESET} — it matches: ${DIOR_C_CMD}${matches[*]}${DIOR_C_RESET}"
            return 0
        fi
    fi

    echo "${DIOR_C_WARN}⚠️  '$group${name:+ }$name' isn't a recognized dior command.${DIOR_C_RESET}"
    return 1
}

# Tab-completion for `dior`. Derives its candidate lists FROM DIOR_MENU_ORDER
# (the same array driving the menu) rather than a separately hand-typed list --
# add a command to DIOR_MENU_ORDER and it tab-completes for free, same as it
# gets a menu entry for free. compinit (needed for compdef) is already set up
# earlier in this file, in the UV & PYTHON TOOLING SETUP section.
_dior() {
    local -a bot_cmds update_cmds
    local entry
    for entry in "${DIOR_MENU_ORDER[@]}"; do
        case "$entry" in
            "bot "*) bot_cmds+=("${entry#bot }") ;;
            "update "*) update_cmds+=("${entry#update }") ;;
        esac
    done

    if (( CURRENT == 2 )); then
        compadd bot update help
    elif [ "${words[2]}" = "help" ]; then
        if (( CURRENT == 3 )); then
            compadd bot update
        elif (( CURRENT == 4 )); then
            case "${words[3]}" in
                bot) compadd -a bot_cmds ;;
                update) compadd -a update_cmds ;;
            esac
        fi
    elif (( CURRENT == 3 )); then
        case "${words[2]}" in
            bot) compadd -a bot_cmds -- --help -h ;;
            update) compadd -a update_cmds -- --help -h ;;
        esac
    elif (( CURRENT == 4 )) && [ "${words[2]}" = "bot" ] && [ "${words[3]}" = "dev" ]; then
        compadd nowatch kill --help -h
    fi
}
compdef _dior dior
