# ==============================================================================
# 🏷️  RELEASE — changelog drafting (git-cliff) and version bumping
# ==============================================================================
#
# Added 2026-08-03 23:49 EDT.

# ------------------------------------------------------------------------------
# dior changelog — draft the next release's notes from commit history
# ------------------------------------------------------------------------------
# Deliberately a DRAFT tool, not an automated write to docs/CHANGELOG.md. That
# file is hand-curated with real constraints git-cliff can't reproduce: a
# commit's hash is backfilled ONE RELEASE LATER (never at the release that
# introduces it), it stays in sync with CHANGELOG-SUMMARY.md and DEVLOG.md,
# and docs-audit.mjs enforces structural rules (no repeated top-level heading,
# the archive conservation rule) that a raw generator has no way to honor.
# This exists to save the "list everything that happened since the last tag"
# typing, not to replace the judgement the real system already enforces --
# see cliff.toml's own header comment for the same point from the config side.
_dior_changelog() {
    shift 1
    local outfile="" dry=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --out)
                if [ -z "$2" ]; then
                    echo "${DIOR_C_ERROR}⚠️  --out needs a file path${DIOR_C_RESET}"
                    return 1
                fi
                outfile="$2"; shift ;;
            --dry-run) dry=1 ;;
            *) _dior_bad_opt "changelog" "$1"; return 1 ;;
        esac
        shift
    done

    if ! command -v git-cliff >/dev/null 2>&1; then
        echo "${DIOR_C_ERROR}⚠️  git-cliff isn't installed (brew install git-cliff)${DIOR_C_RESET}"
        return 1
    fi
    if [ ! -f "$DIOR_BOT_DIR/cliff.toml" ]; then
        echo "${DIOR_C_ERROR}⚠️  No cliff.toml found in $DIOR_BOT_DIR${DIOR_C_RESET}"
        return 1
    fi

    if [ $dry -eq 1 ]; then
        echo "${DIOR_C_DIM}Would draft a changelog from commits since the last tag${DIOR_C_RESET} ${DIOR_C_DIM}(dry run, nothing written)${DIOR_C_RESET}"
        return
    fi

    cd "$DIOR_BOT_DIR" || return 1
    if [ -n "$outfile" ]; then
        git-cliff --unreleased -o "$outfile" && echo "${DIOR_C_OK}Draft written to $outfile${DIOR_C_RESET}"
    else
        git-cliff --unreleased
    fi
}
_dior_register "changelog" "Draft the next release's changelog from commit history ${DIOR_C_OPT}[--out <file>] [--dry-run]${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}🏷️  CHANGELOG DRAFT${DIOR_C_RESET} ${DIOR_C_DIM}— dior changelog${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Runs git-cliff (config: Diors-Builds' own cliff.toml) over every commit since
the last tag, grouped by the same 11 Conventional Commits types the repo uses.

${DIOR_C_WARN}⚠️  DRAFT ONLY -- this does NOT write docs/CHANGELOG.md.${DIOR_C_RESET} That file backfills
each commit's hash one release LATER, stays in sync with CHANGELOG-SUMMARY.md
and DEVLOG.md, and is checked by \`dior docs audit\`'s structural rules -- none
of which a generator can reproduce. Use this output as a starting point to
hand-adapt, not as the final entry.

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%s${DIOR_C_RESET} ${DIOR_C_OPT}%-16s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior changelog" "" "Print the draft to stdout" \
    "dior changelog" "--out <file>" "Write the draft to a file instead" \
    "dior changelog" "--dry-run" "Say what would run, generate nothing")
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"

# ------------------------------------------------------------------------------
# dior bump — bump package.json AND package-lock.json together
# ------------------------------------------------------------------------------
# Uses `npm version --no-git-tag-version` rather than hand-editing JSON --
# verified live (scratch copy, 2026-08-03 23:47 EDT) that this is the one
# command that updates BOTH package.json's "version" and package-lock.json's
# two version fields (top-level + packages[""]) atomically and correctly,
# with npm's own lockfile-writing logic instead of a hand-rolled risk of
# getting the lockfile's structure slightly wrong. --no-git-tag-version means
# it only edits files -- it does NOT commit or tag, matching this project's
# own rule that the bump/changelog commit and the tag are separate, deliberate
# steps (project_git_workflow: ONE commit + ONE tag per release, both asked).
_dior_bump() {
    shift 1
    local dry=0 version=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) dry=1 ;;
            -*) _dior_bad_opt "bump" "$1"; return 1 ;;
            *)
                if [ -n "$version" ]; then
                    echo "${DIOR_C_ERROR}⚠️  Only one version is supported (already got '$version')${DIOR_C_RESET}"
                    return 1
                fi
                version="$1" ;;
        esac
        shift
    done

    if [ -z "$version" ]; then
        dior help bump
        return 1
    fi
    if ! [[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' ]]; then
        echo "${DIOR_C_ERROR}⚠️  '$version' doesn't look like a version (expected X.Y.Z, optionally -pre etc.)${DIOR_C_RESET}"
        return 1
    fi

    cd "$DIOR_BOT_DIR" || return 1
    if [ ! -f package.json ]; then
        echo "${DIOR_C_ERROR}⚠️  No package.json in $DIOR_BOT_DIR${DIOR_C_RESET}"
        return 1
    fi
    local current
    current=$(node -p "require('./package.json').version" 2>/dev/null)

    if [ $dry -eq 1 ]; then
        echo "${DIOR_C_DIM}Would bump package.json + package-lock.json: $current -> $version${DIOR_C_RESET} ${DIOR_C_DIM}(dry run, nothing written)${DIOR_C_RESET}"
        return
    fi

    if npm version "$version" --no-git-tag-version --allow-same-version >/dev/null; then
        echo "${DIOR_C_OK}Bumped:${DIOR_C_RESET} package.json + package-lock.json ${DIOR_C_DIM}$current -> ${DIOR_C_RESET}${DIOR_C_ARG}$version${DIOR_C_RESET}"
    else
        echo "${DIOR_C_ERROR}⚠️  npm version failed -- nothing changed${DIOR_C_RESET}"
        return 1
    fi
}
_dior_register "bump" "Bump package.json + package-lock.json together ${DIOR_C_ARG}<version>${DIOR_C_RESET} ${DIOR_C_OPT}[--dry-run]${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}🏷️  VERSION BUMP${DIOR_C_RESET} ${DIOR_C_DIM}— dior bump${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Bumps package.json's version AND package-lock.json's two version fields
together, via \`npm version --no-git-tag-version\` -- the one command that
updates both correctly in one atomic step, since npm owns the lockfile format.

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%s${DIOR_C_RESET} ${DIOR_C_ARG}%-14s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior bump" "2.52.0" "Bump both files to exactly that version" \
    "dior bump" "2.52.0-pre" "Pre-release suffixes are accepted too")
$(printf "  ${DIOR_C_CMD}%s${DIOR_C_RESET} ${DIOR_C_ARG}%-8s${DIOR_C_RESET} ${DIOR_C_OPT}%-5s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior bump" "2.52.0" "--dry-run" "Say what would change, write nothing")

${DIOR_C_DIM}Does NOT commit, tag, or touch the changelog -- this project's own workflow
keeps the bump/changelog commit and the git tag as two separate, deliberate
steps, both asked before they happen. This only edits the two files.${DIOR_C_RESET}
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"
