# ==============================================================================
# dior CLI — update.zsh
# ==============================================================================
# The 'update' command group: per-package-manager update commands.
#
# Loaded by ~/.config/dior/dior.zsh, which ~/.zshrc sources. Split out of
# ~/.zshrc on 2026-07-27 11:10 EDT (it had grown to 675 of that file's 723 lines, with no
# version control and no backup) — a pure relocation, no behavior change. See
# dior.zsh for the architecture overview and the load order these files rely on.
#
# CONSOLIDATED 2026-07-27 11:10 EDT: these six were six separate MENU entries
# sharing one guide, which meant the top-level menu was 40% package managers.
# They're now one entry with six sub-options. The commands themselves did not
# change -- `dior update brew` still resolves to _dior_update_brew exactly as
# before, so there's nothing to relearn.

_dior_update_brew() {
    echo "🍺 Updating Homebrew..."
    # The '&&' ensures the next command only runs if the previous one succeeds.
    brew update && brew upgrade && brew cleanup
}

_dior_update_uv() {
    echo "⚡️ Upgrading uv tools & binary..."
    # Upgrades all isolated CLI tools installed via uv tool (e.g. cyberdrop-dl-patched).
    # Also self-updates the uv binary if standalone installer was used.
    uv tool upgrade --all
    command -v uv >/dev/null 2>&1 && uv self update 2>/dev/null
}

_dior_update_pipx() {
    echo "📦 Updating pipx CLI tools..."
    # Updates all isolated terminal tools managed by pipx.
    pipx upgrade-all
}

_dior_update_pip3() {
    echo "🐍 Updating global pip3 libraries..."
    pip3 cache purge
    # Batched into one install call instead of 'xargs -n1' (one pip3 install per
    # package) -- same result, faster, still a no-op when nothing is outdated.
    local outdated
    outdated=$(pip3 list --outdated --format=json | python3 -c "import json, sys; print(' '.join([x['name'] for x in json.load(sys.stdin)]))")
    if [ -n "$outdated" ]; then
        pip3 install -U ${=outdated}
    fi
    pip3 cache purge
}

_dior_update_npm() {
    echo "⚡️ Updating global npm packages..."
    # Updates global Node.js packages (-g flag) like claude-code and railway/cli.
    npm update -g
}

_dior_update_all() {
    # Chains the individual commands together for a full system sweep
    dior update brew
    dior update uv
    dior update pipx
    dior update pip3
    dior update npm
    echo "\n✨ All package managers are up to date!"
}

# Bare `dior update`. No default action on purpose: every mode is a real system
# mutation and 'all' would fire five package managers off a single bare word, so
# this shows the guide instead. Reached via the dispatcher's _dior_<group>
# fallback, which only ever fires when $2 is EMPTY -- `dior update nope` still
# routes to the suggester and gets reported as the typo it is.
_dior_update() {
    dior help update
}

_dior_register "update" "Update package managers ${DIOR_C_ARG}<brew|uv|pipx|pip3|npm|all>${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}🧹 PACKAGE UPDATES${DIOR_C_RESET} ${DIOR_C_DIM}— dior update${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Automates keeping your Mac development environment secure and fast.

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%s${DIOR_C_RESET} ${DIOR_C_ARG}%-5s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior update" "brew" "Updates Homebrew ${DIOR_C_DIM}(system apps, terminal utilities, macOS tools)${DIOR_C_RESET}" \
    "dior update" "uv" "Upgrades isolated Python tools ${DIOR_C_DIM}(e.g. cyberdrop-dl-patched; fast Rust dependency resolution)${DIOR_C_RESET}" \
    "dior update" "pipx" "Updates isolated Python terminal apps ${DIOR_C_DIM}(e.g. cloudinary-cli; kept bubbled from system Python)${DIOR_C_RESET}" \
    "dior update" "pip3" "Updates global Python libraries ${DIOR_C_DIM}(e.g. requests, pillow; also clears the stale pip cache)${DIOR_C_RESET}" \
    "dior update" "npm" "Updates global Node.js packages ${DIOR_C_DIM}(e.g. claude-code, railway)${DIOR_C_RESET}" \
    "dior update" "all" "Runs all five above, one after another")

  ${DIOR_C_DIM}A bare 'dior update' shows this guide rather than running anything --
  'all' would fire five package managers off a single bare word.${DIOR_C_RESET}
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"
