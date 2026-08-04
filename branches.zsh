# ==============================================================================
# 🌿 BRANCHES — local branch hygiene for Diors-Builds
# ==============================================================================
#
# Added 2026-08-03 23:54 EDT. GitHub's auto-delete-on-merge is enabled for
# Diors-Builds, but a plain `git fetch` does NOT prune remote-tracking refs,
# so long-merged branches keep listing locally as though they were live --
# CLAUDE.md documents 10 merged branches found rotting this way on
# 2026-07-27 21:50 EDT. This is the active, one-shot counterpart to the
# passive SessionStart hook that already warns about [gone] branches.

# ------------------------------------------------------------------------------
# dior branches [--list|--prune|--find <query>] [--dry-run]
# ------------------------------------------------------------------------------
_dior_branches() {
    shift 1
    local mode="list" query="" dry=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --list) mode="list" ;;
            --prune) mode="prune" ;;
            --find)
                mode="find"
                if [ -z "$2" ]; then
                    echo "${DIOR_C_ERROR}⚠️  --find needs a search term${DIOR_C_RESET}"
                    return 1
                fi
                query="$2"; shift ;;
            --dry-run) dry=1 ;;
            *) _dior_bad_opt "branches" "$1"; return 1 ;;
        esac
        shift
    done

    cd "$DIOR_BOT_DIR" || return 1

    case "$mode" in
        list)
            echo "${DIOR_C_HEAD}Fetching + pruning remote-tracking refs...${DIOR_C_RESET}"
            git fetch --prune --quiet
            echo ""
            echo "${DIOR_C_HEAD}Local branches${DIOR_C_RESET}"
            git branch -vv
            if command -v gh >/dev/null 2>&1; then
                echo ""
                echo "${DIOR_C_HEAD}Open PRs${DIOR_C_RESET}"
                gh pr list --state open
            fi
            ;;
        find)
            git branch -a | rg -i --color=always "$query"
            ;;
        prune)
            echo "${DIOR_C_HEAD}Fetching + pruning remote-tracking refs...${DIOR_C_RESET}"
            git fetch --prune --quiet
            local -a gone
            gone=(${(f)"$(git branch -vv | rg ': gone\]' | awk '{print $1}')"})
            if [ ${#gone} -eq 0 ]; then
                echo "${DIOR_C_OK}No local branches with a gone remote -- nothing to prune.${DIOR_C_RESET}"
                return
            fi
            echo "${DIOR_C_WARN}${#gone} local branch(es) whose remote is gone:${DIOR_C_RESET}"
            printf '  %s\n' "${gone[@]}"
            if [ $dry -eq 1 ]; then
                echo "${DIOR_C_DIM}Dry run -- nothing deleted.${DIOR_C_RESET}"
                return
            fi
            if ! _dior_confirm "Delete these ${#gone} local branch(es)?"; then
                echo "❌ Cancelled -- nothing deleted"
                return 1
            fi
            git branch -D "${gone[@]}"
            ;;
    esac
}
_dior_register "branches" "List, find, or prune local branches ${DIOR_C_OPT}[--list|--prune|--find <query>] [--dry-run]${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}🌿 BRANCH HYGIENE${DIOR_C_RESET} ${DIOR_C_DIM}— dior branches${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Diors-Builds auto-deletes a branch's remote on merge, but a plain \`git fetch\`
never prunes the local remote-tracking ref for it -- a merged branch keeps
listing locally as though it were still live. Every mode here fetches with
--prune first, so the [gone] markers this reads are always current.

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%s${DIOR_C_RESET} ${DIOR_C_OPT}%-16s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior branches" "" "Same as --list" \
    "dior branches" "--list" "Local branches (-vv) plus open PRs" \
    "dior branches" "--prune" "Find + delete local branches whose remote is gone ${DIOR_C_DIM}(confirms first)${DIOR_C_RESET}" \
    "dior branches" "--find <query>" "Grep local + remote branch names for <query>" \
    "dior branches" "--dry-run" "With --prune: list what would be deleted, delete nothing")

${DIOR_C_DIM}A merged branch should never outlive its PR -- 'gh pr merge --squash --delete-branch'
already removes it at merge time; this command is for the ones that slipped
through some other way (a manual merge, a branch abandoned without a PR).${DIOR_C_RESET}
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"
