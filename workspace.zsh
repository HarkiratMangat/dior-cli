# ==============================================================================
# 🧭 WORKSPACE — environment health, navigation, and the notes scratchpad
# ==============================================================================
#
# Added 2026-08-03 23:34 EDT. Four standalone (single-word) commands: doctor,
# notes, repo, cd. None of them take a subcommand -- each is a leaf, not a
# group -- so they dispatch through the SAME bare-command path `update`
# already used (or, for `cd`'s flags, the newer flag-shaped variant of it in
# core.zsh's dior()). Grouped together in the menu under one shared
# "WORKSPACE COMMANDS" header (DIOR_GROUP_HEADER in core.zsh) rather than each
# getting its own single-row section.

# ------------------------------------------------------------------------------
# dior doctor — is this machine ready to work on Dior's Builds?
# ------------------------------------------------------------------------------
_dior_doctor() {
    local ok_n=0 warn_n=0

    _doctor_ok() {
        printf "  ${DIOR_C_OK}%-6s${DIOR_C_RESET} %s\n" "OK" "$1"
        ok_n=$((ok_n + 1))
    }
    _doctor_warn() {
        printf "  ${DIOR_C_WARN}%-6s${DIOR_C_RESET} %s\n" "WARN" "$1"
        warn_n=$((warn_n + 1))
    }

    echo "${DIOR_C_TITLE}🧭 DIOR DOCTOR${DIOR_C_RESET}"
    echo ""

    # --- Node ---
    if command -v node >/dev/null 2>&1; then
        local nv major
        nv=$(node --version)
        major=${${nv#v}%%.*}
        if [ "$major" -ge 24 ]; then
            _doctor_ok "node $nv (>= 24, matches package.json engines)"
        else
            _doctor_warn "node $nv is older than the required >=24 (package.json engines)"
        fi
    else
        _doctor_warn "node not found on PATH"
    fi

    # --- gcloud (VM deploy/restart/observability) ---
    if command -v gcloud >/dev/null 2>&1; then
        local acct
        acct=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)
        if [ -n "$acct" ]; then
            _doctor_ok "gcloud authenticated as $acct"
        else
            _doctor_warn "gcloud installed but no active account -- 'gcloud auth login'"
        fi
    else
        _doctor_warn "gcloud not found -- needed for 'dior bot vm'/'dior bot check'"
    fi

    # --- wrangler (legal site deploy) ---
    if command -v npx >/dev/null 2>&1 && npx --no-install wrangler --version >/dev/null 2>&1; then
        _doctor_ok "wrangler available"
    else
        _doctor_warn "wrangler not resolvable via npx -- needed for 'dior legal deploy'"
    fi

    # --- gh (branches, PRs) ---
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        _doctor_ok "gh authenticated"
    else
        _doctor_warn "gh not installed or not authenticated -- needed for 'dior branches'"
    fi

    # --- git identity (must be the shared dior identity, never a real personal email) ---
    local git_email
    git_email=$(git config --global user.email 2>/dev/null)
    if [ "$git_email" = "21996007+HarkiratMangat@users.noreply.github.com" ]; then
        _doctor_ok "git identity is the shared noreply address"
    elif [ -n "$git_email" ]; then
        _doctor_warn "git user.email is '$git_email', not the expected noreply address"
    else
        _doctor_warn "git user.email is not set globally"
    fi

    # --- topgrade / git-cliff (dior update / dior changelog) ---
    command -v topgrade >/dev/null 2>&1 && _doctor_ok "topgrade available" || _doctor_warn "topgrade not found -- 'dior update' needs it"
    command -v git-cliff >/dev/null 2>&1 && _doctor_ok "git-cliff available" || _doctor_warn "git-cliff not found -- 'dior changelog' needs it"

    # --- DIOR_BOT_DIR sanity ---
    if [ -d "$DIOR_BOT_DIR/.git" ]; then
        _doctor_ok "DIOR_BOT_DIR is a real git repo ($DIOR_BOT_DIR)"
    else
        _doctor_warn "DIOR_BOT_DIR ($DIOR_BOT_DIR) doesn't look like a git repo"
    fi

    # --- Mongo reachability, dev + prod. Never prints a URI or credential -- only
    # whether a connection succeeds, using mongosh's own exit code. ---
    if command -v mongosh >/dev/null 2>&1; then
        if mongosh "mongodb://localhost:27017/diors-builds-dev" --quiet --eval "1" >/dev/null 2>&1; then
            _doctor_ok "local dev Mongo reachable"
        else
            _doctor_warn "local dev Mongo NOT reachable (mongodb://localhost:27017) -- is it running?"
        fi
        # Prod URI comes from .env, read only to hand to mongosh -- never echoed.
        local prod_uri
        prod_uri=$(rg -m1 "^MONGODB_URI=" "$DIOR_BOT_DIR/.env" 2>/dev/null | cut -d= -f2-)
        if [ -n "$prod_uri" ]; then
            if mongosh "$prod_uri" --quiet --eval "1" >/dev/null 2>&1; then
                _doctor_ok "prod Mongo Atlas reachable"
            else
                _doctor_warn "prod Mongo Atlas NOT reachable (network, or a stale/rotated credential?)"
            fi
        fi
    else
        _doctor_warn "mongosh not found -- can't check Mongo reachability"
    fi

    # --- .env vs .env.dev key drift, NAMES ONLY -- never a value. Real gotcha this
    # exists to catch: dotenv.config() at index.js backfills anything .env.dev
    # omits from prod's .env, so a key silently present in BOTH isn't a problem,
    # but a key unique to .env (never overridden in dev) is worth knowing about. ---
    if [ -f "$DIOR_BOT_DIR/.env" ] && [ -f "$DIOR_BOT_DIR/.env.dev" ]; then
        local -a prod_keys dev_keys only_prod
        prod_keys=(${(f)"$(rg -o '^[A-Z_][A-Z0-9_]*(?==)' "$DIOR_BOT_DIR/.env" 2>/dev/null)"})
        dev_keys=(${(f)"$(rg -o '^[A-Z_][A-Z0-9_]*(?==)' "$DIOR_BOT_DIR/.env.dev" 2>/dev/null)"})
        only_prod=(${prod_keys:|dev_keys})
        if [ ${#only_prod} -eq 0 ]; then
            _doctor_ok ".env.dev covers every key set in .env"
        else
            _doctor_warn ".env.dev is missing keys .env has (backfilled from prod, may be unintended): ${(j:, :)only_prod}"
        fi
    fi

    echo ""
    if [ $warn_n -eq 0 ]; then
        echo "${DIOR_C_OK}✅ $ok_n check(s) passed, nothing to flag.${DIOR_C_RESET}"
    else
        echo "${DIOR_C_WARN}⚠️  $warn_n warning(s), $ok_n check(s) passed.${DIOR_C_RESET}"
    fi

    unfunction _doctor_ok _doctor_warn
}
_dior_register "doctor" "Check this machine is ready to work on Dior's Builds" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}🧭 DIOR DOCTOR${DIOR_C_RESET} ${DIOR_C_DIM}— dior doctor${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Checks node/gcloud/wrangler/gh/topgrade/git-cliff availability, git identity,
whether DIOR_BOT_DIR is a real repo, Mongo reachability (dev + prod, connection
only -- never prints a URI or credential), and whether .env.dev is missing any
key .env sets (names only, never values -- dotenv silently backfills a missing
dev key from prod, which is sometimes exactly what you want and sometimes not).

${DIOR_C_DIM}Nothing here is auto-fixed -- it only reports, so you decide what to act on.${DIOR_C_RESET}
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"

# ------------------------------------------------------------------------------
# dior repo — open the Claude Code projects folder in Finder
# ------------------------------------------------------------------------------
_dior_repo() {
    open "/Applications/Claude Code"
}
_dior_register "repo" "Open /Applications/Claude Code in Finder" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}📂 OPEN PROJECTS FOLDER${DIOR_C_RESET} ${DIOR_C_DIM}— dior repo${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Opens ${DIOR_C_ARG}/Applications/Claude Code${DIOR_C_RESET} in Finder -- the parent folder holding every
project (Diors-Builds, dior-cli, Gif-Background-Remover, ...).

${DIOR_C_DIM}For the TERMINAL equivalent (cd, not Finder), see 'dior cd'.${DIOR_C_RESET}
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"

# ------------------------------------------------------------------------------
# dior cd — jump the CURRENT shell to a known project directory
# ------------------------------------------------------------------------------
# Deliberately NOT subshelled, unlike every other cd in this codebase
# (_dior_bot_dev, _dior_bot_commit's git -C, etc. all go out of their way to
# avoid leaking a directory change into the caller's shell). Here that IS the
# entire point -- `dior` is a real shell function, not an external command, so
# a plain `cd` inside it changes the actual interactive shell, exactly like
# typing `cd` by hand would. Don't "fix" this by wrapping it in a subshell.
_dior_cd() {
    shift 1
    local target="/Applications/Claude Code"
    case "$1" in
        "") ;;
        --dioreo) target="$DIOR_BOT_DIR" ;;
        --gif) target="/Applications/Claude Code/Gif-Background-Remover" ;;
        --cli) target="$DIOR_CLI_DIR" ;;
        *) _dior_bad_opt "cd" "$1"; return 1 ;;
    esac
    if [ ! -d "$target" ]; then
        echo "${DIOR_C_ERROR}⚠️  No such directory: $target${DIOR_C_RESET}"
        return 1
    fi
    cd "$target" && echo "${DIOR_C_DIM}→${DIOR_C_RESET} $target"
}
_dior_register "cd" "Jump this shell to a known project ${DIOR_C_OPT}[--dioreo|--gif|--cli]${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}📁 QUICK CD${DIOR_C_RESET} ${DIOR_C_DIM}— dior cd${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Changes THIS shell's working directory -- unlike every other command here,
this one is deliberately not subshelled, so it actually moves you.

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%s${DIOR_C_RESET} ${DIOR_C_OPT}%-9s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior cd" "" "/Applications/Claude Code -- the parent folder of every project" \
    "dior cd" "--dioreo" "Diors-Builds (same path as \$DIOR_BOT_DIR)" \
    "dior cd" "--gif" "Gif-Background-Remover" \
    "dior cd" "--cli" "This CLI's own repo (\$DIOR_CLI_DIR)")

  ${DIOR_C_DIM}Finder equivalent for the bare case: 'dior repo'.${DIOR_C_RESET}
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"

# ------------------------------------------------------------------------------
# dior notes — open the central notes scratchpad, with an open-items count
# ------------------------------------------------------------------------------
_dior_notes() {
    local file="$DIOR_BOT_DIR/docs/diors-builds notes.md"
    if [ ! -f "$file" ]; then
        echo "${DIOR_C_ERROR}⚠️  Not found: $file${DIOR_C_RESET}"
        return 1
    fi
    # Mirrors the SessionStart hook's own scan window (## Questions -> ## 📍,
    # documented in CLAUDE.md) so this count can't drift from what that hook
    # already reports at session start -- counts non-blank, non-heading lines.
    local count
    count=$(awk '/^## Questions/{f=1; next} /^## 📍/{f=0} f && NF && $0 !~ /^#/' "$file" | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
        echo "${DIOR_C_WARN}$count open line(s) in the working sections${DIOR_C_RESET}"
    else
        echo "${DIOR_C_DIM}No open items in the working sections${DIOR_C_RESET}"
    fi
    open "$file"
}
_dior_register "notes" "Open the central notes scratchpad, with an open-items count" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}📝 NOTES SCRATCHPAD${DIOR_C_RESET} ${DIOR_C_DIM}— dior notes${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Opens ${DIOR_C_ARG}docs/diors-builds notes.md${DIOR_C_RESET} in its default app (MarkEdit), after printing how
many open (unmarked) lines sit in its working sections -- the same ## Questions
-> ## 📍 scan window the SessionStart hook already checks every session.
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"
