# ==============================================================================
# dior CLI — update.zsh
# ==============================================================================
# The 'update' command: system-wide updates via topgrade, plus updating the
# dior CLI itself.
#
# Loaded by ~/.config/dior/dior.zsh, which ~/.zshrc sources. Split out of
# ~/.zshrc on 2026-07-27 11:10 EDT (it had grown to 675 of that file's 723 lines, with no
# version control and no backup) — a pure relocation, no behavior change. See
# dior.zsh for the architecture overview and the load order these files rely on.
#
# RETIRED 2026-08-03 23:56 EDT: the six hand-written per-package-manager
# functions (brew/uv/pipx/pip3/npm/all) this file used to hold, in favor of
# topgrade (~/.config/topgrade.toml) -- a dedicated, actively-maintained tool
# that already covers everything those five did (Homebrew, pipx, pip3, npm)
# PLUS gcloud, gh extensions, Claude Code, and dozens more, without hand-rolled
# per-manager logic to keep in sync as new tools get installed. `uv self
# update`'s standalone-binary self-update isn't one of topgrade's own steps,
# but `brew upgrade` already covers uv when it was installed via Homebrew,
# which is how it's actually installed here.
# Configured to skip system/mas/microsoft_office/containers (Harkirat's
# explicit list: never touch the OS itself, the Mac App Store, Microsoft
# Office, or Docker/container runtimes) -- see topgrade.toml's own disable
# array, audited and extended 2026-08-03 23:56 EDT (only "mas" was missing;
# system/containers/microsoft_office were already there).

_dior_update() {
    shift 1
    local dry=0
    for arg in "$@"; do
        case "$arg" in
            --dry-run) dry=1 ;;
            *) _dior_bad_opt "update" "$arg"; return 1 ;;
        esac
    done

    if ! command -v topgrade >/dev/null 2>&1; then
        echo "${DIOR_C_ERROR}⚠️  topgrade isn't installed (brew install topgrade)${DIOR_C_RESET}"
        return 1
    fi

    if [ $dry -eq 1 ]; then
        topgrade -n
    else
        topgrade
    fi
}

# dior update self — updates the CLI's OWN repo, not a package manager. A real
# `git pull`, not subshelled: DIOR_CLI_DIR is a git repo like any other, and
# there's no state to leak by ending up there afterward (unlike bot dev's cd,
# which deliberately avoids leaving the caller's shell in a different repo).
_dior_update_self() {
    echo "🔄 Updating dior CLI ($DIOR_CLI_DIR)..."
    if ! git -C "$DIOR_CLI_DIR" pull --ff-only; then
        echo "${DIOR_C_WARN}⚠️  Pull failed or wasn't a fast-forward -- resolve manually in $DIOR_CLI_DIR${DIOR_C_RESET}"
        return 1
    fi
    echo "${DIOR_C_OK}Restart your shell (or 'exec zsh') to load any new commands.${DIOR_C_RESET}"
}

_dior_register "update" "Update your Mac via topgrade ${DIOR_C_OPT}[self] [--dry-run]${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}🧹 SYSTEM UPDATE${DIOR_C_RESET} ${DIOR_C_DIM}— dior update${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Runs topgrade (~/.config/topgrade.toml) -- Homebrew (formula + cask), pipx,
pip3, npm, yarn, gcloud components, gh extensions, Claude Code, and every
other step topgrade knows about, all in one pass.

${DIOR_C_WARN}⚠️  Deliberately SKIPPED (topgrade.toml's disable list):${DIOR_C_RESET} the OS itself
(\"system\"), the Mac App Store (\"mas\"), Microsoft Office, and Docker/container
runtimes (\"containers\") -- none of these are touched, ever.

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%s${DIOR_C_RESET} ${DIOR_C_OPT}%-9s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior update" "" "Run topgrade for real" \
    "dior update" "--dry-run" "Show every command topgrade WOULD run, run nothing" \
    "dior update" "self" "Update the dior CLI itself (git pull, this repo only)")

  ${DIOR_C_DIM}'self' is unrelated to topgrade -- it pulls ~/.config/dior's own git repo, since
  this CLI is versioned separately from anything topgrade manages.${DIOR_C_RESET}
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"
