# ==============================================================================
# dior CLI — bot.zsh
# ==============================================================================
# The 'bot' command group: local dev bot, git commit, VM deploy/restart, observability.
#
# Loaded by ~/.config/dior/dior.zsh, which ~/.zshrc sources. Split out of
# ~/.zshrc on 2026-07-27 11:10 EDT (it had grown to 675 of that file's 723 lines, with no
# version control and no backup) — a pure relocation, no behavior change. See
# dior.zsh for the architecture overview and the load order these files rely on.

# ==============================================================================
# 🤖 BOT OBSERVABILITY & DEPLOYMENT COMMANDS
# ==============================================================================

_dior_bot_status() {
    # Executes the local bash script that pings the GCP VM to check health,
    # IP address, bot service uptime, and error counts.
    "$DIOR_BOT_DIR/scripts/vmstatus.sh"
}

_dior_bot_baseline() {
    # Mirrors Claude's pre-deploy health check flow.
    # The '2>&1' catches any background errors (stderr) and prints them
    # normally (stdout) so you don't miss any warnings.
    cd "$DIOR_BOT_DIR" || return
    echo "=== BASELINE (pre-deploy) ==="
    bash scripts/vmstatus.sh 2>&1
}

_dior_bot_logs() {
    # '${3:-25}' means: use the 3rd argument provided, but if it's empty,
    # default to 25 lines. (e.g., 'dior bot logs 50' fetches 50 lines).
    "$DIOR_BOT_DIR/scripts/vmstatus.sh" logs "${3:-25}"
}

_dior_bot_peaks() {
    # Executes the local script that queries GCP Cloud Monitoring APIs
    # for CPU and RAM usage peaks.
    "$DIOR_BOT_DIR/scripts/vmpeaks.sh"
}

# Anonymous immediately-invoked function (not a bare top-level `local`): zsh
# doesn't error on `local` outside a function, but it also doesn't scope it --
# the variable would leak as a permanent global in every terminal session.
# Wrapping it like this keeps BOT_OBS_GUIDE genuinely function-scoped, gone as
# soon as this block finishes running.
() {
    local BOT_OBS_GUIDE="${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}📊 GUIDE: Bot Observability (status / baseline / logs / peaks)${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Queries the GCP VM remotely to check on the bot's health.

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%-22s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior bot status" "Quick glance at IP, systemd service state, load avg, and RAM." \
    "dior bot baseline" "Runs the pre-deploy check ${DIOR_C_DIM}(redirects hidden errors to stdout so you don't miss warnings)${DIOR_C_RESET}." \
    "dior bot logs [N=25]" "Pulls the last N lines of systemd journalctl logs ${DIOR_C_DIM}(e.g. 'dior bot logs 100')${DIOR_C_RESET}." \
    "dior bot peaks" "Queries GCP Cloud Monitoring API for 12h/24h/7d CPU & RAM spikes ${DIOR_C_DIM}(to prevent surprise billing)${DIOR_C_RESET}.")
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"
    _dior_register "bot status" "GCP VM health, bot service state, and errors" "$BOT_OBS_GUIDE"
    _dior_register "bot baseline" "Run pre-deploy health check" "$BOT_OBS_GUIDE"
    _dior_register "bot logs" "Tail journalctl logs ${DIOR_C_ARG}[N=25]${DIOR_C_RESET}" "$BOT_OBS_GUIDE"
    _dior_register "bot peaks" "Cloud Monitoring CPU and RAM peaks for the VM" "$BOT_OBS_GUIDE"
}

_dior_bot_commands() {
    # Validated HERE, before node ever runs -- devCommands.js's own usage text (printed via
    # console.error when $3 is missing/invalid) is plain, uncolored stdlib output with no way
    # to match dior's styling from this side of a subprocess call. Catching it here means that
    # text never gets a chance to print; the user only ever sees dior's own colored guide.
    case "$3" in
        list|clear)
            node "$DIOR_BOT_DIR/scripts/devCommands.js" "$3"
            ;;
        *)
            echo "${DIOR_C_WARN}⚠️  'dior bot commands' needs an argument.${DIOR_C_RESET} Use ${DIOR_C_CMD}list${DIOR_C_RESET} or ${DIOR_C_CMD}clear${DIOR_C_RESET} -- see ${DIOR_C_CMD}dior help bot commands${DIOR_C_RESET}."
            ;;
    esac
}
_dior_register "bot commands" "List/clear DEV app's slash commands ${DIOR_C_ARG}<list|clear>${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}📋 GUIDE: dior bot commands${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Manages the DEV app's registered slash commands ${DIOR_C_DIM}(Dio (Dev) — separate from prod)${DIOR_C_RESET}.

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%-25s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior bot commands list" "Shows what's currently registered on the dev application." \
    "dior bot commands clear" "Registers an empty list so dev's commands vanish from the / picker.")

  ${DIOR_C_DIM}They come back automatically the next time the dev bot boots.${DIOR_C_RESET}
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"

_dior_bot_commit() {
    # A smart commit wrapper.
    # $3 is the commit title, $4 is the optional detailed body.
    cd "$DIOR_BOT_DIR" || return

    # If no commit message ($3) is provided, open the standard interactive git editor
    # -- that path already has its own escape hatch (save empty / exit without saving),
    # so it doesn't need the confirm gate below.
    if [ -z "$3" ]; then
        echo "📝 No message provided. Opening interactive git commit..."
        git add .
        git commit
    else
        echo "About to stage everything and commit:"
        echo "  Title: ${DIOR_C_ARG}$3${DIOR_C_RESET}"
        [ -n "$4" ] && echo "  Body:  ${DIOR_C_ARG}$4${DIOR_C_RESET}"
        if ! _dior_confirm "Proceed?"; then
            echo "❌ Cancelled -- nothing was staged or committed."
            return
        fi

        echo "💾 Staging and committing changes..."
        git add .

        # If a body description ($4) is provided, pass it as a second -m flag to git
        if [ -n "$4" ]; then
            git commit -q -m "$3" -m "$4"
        else
            git commit -q -m "$3"
        fi

        # Print the last 3 commits to confirm it worked
        echo "--- HEAD now ---"
        git log --oneline -3
    fi
}
_dior_register "bot commit" "Stage all and commit ${DIOR_C_ARG}['<Title>' ['<Body>']]${DIOR_C_RESET} ${DIOR_C_DIM}(confirms first)${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}📝 GUIDE: dior bot commit${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
A smart wrapper for Git staging and committing.
${DIOR_C_DIM}The quotes in the USAGE examples below are real characters to type, not placeholder
notation -- see QUOTE RULES at the bottom for which kind to use.${DIOR_C_RESET}

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%-37s${DIOR_C_RESET} ${DIOR_C_DIM}%s${DIOR_C_RESET}\n" \
    "dior bot commit" "(no args -- opens your editor for a multi-line commit)" \
    "dior bot commit '<Title>'" "(quick commit, title only -- shows a y/N confirm first)" \
    "dior bot commit '<Title>' '<Body>'" "(title + optional body -- also confirms first)")

  ${DIOR_C_WARN}⚠️  A single '-' flag (e.g. '-help' instead of '--help'/'-h') is NOT recognized as a
     help flag -- it gets read as the commit Title. The confirm step above is the safety net.${DIOR_C_RESET}

${DIOR_C_HEAD}CONVENTIONAL COMMITS RULESET:${DIOR_C_RESET}
  Format: ${DIOR_C_ARG}<type>(<optional scope>): <description>${DIOR_C_RESET} ${DIOR_C_DIM}(lowercase, no trailing period)${DIOR_C_RESET}
  Breaking change: put ${DIOR_C_ARG}!${DIOR_C_RESET} right before the colon, e.g. 'feat!: drop old API'.

$(printf "  ${DIOR_C_CMD}%-37s${DIOR_C_RESET} %s\n" \
    "feat:" "A new feature ${DIOR_C_DIM}(e.g., 'feat: add vision API logging')${DIOR_C_RESET}" \
    "fix:" "A bug fix ${DIOR_C_DIM}(e.g., 'fix: patch database timeout')${DIOR_C_RESET}" \
    "docs:" "Documentation-only changes ${DIOR_C_DIM}(e.g., 'docs: update CLAUDE.md')${DIOR_C_RESET}" \
    "refactor:" "Code change that's neither a fix nor a feature ${DIOR_C_DIM}(no behavior change)${DIOR_C_RESET}" \
    "perf:" "A performance improvement" \
    "style:" "Formatting/whitespace only, no logic change" \
    "test:" "Adding or correcting tests" \
    "build:" "Build system or dependency changes ${DIOR_C_DIM}(e.g., 'build: move xlsx to devDeps')${DIOR_C_RESET}" \
    "ci:" "CI/CD pipeline changes" \
    "chore:" "Maintenance tasks ${DIOR_C_DIM}(e.g., 'chore: update npm packages')${DIOR_C_RESET}" \
    "revert:" "Reverts a previous commit")
  ${DIOR_C_DIM}Full reference + rationale: docs/reference/commit-and-branch-naming.md${DIOR_C_RESET}

${DIOR_C_HEAD}QUOTE RULES:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}•${DIOR_C_RESET} %-19s ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "Single Quotes ('...')" "BEST -- use these if your message has special characters, code, or double quotes inside." \
    "Double Quotes (\"...\")" "OK, but the terminal might misinterpret dollar signs (\$) or backticks.")
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"

# Shared by both bot deploy and bot restart -- they differed only in whether
# 'manual' gets passed to deploy.sh, so the gcloud PATH-fix + SSH call now lives
# once instead of being duplicated across both case blocks.
_dior_vm_deploy() {
    local mode="$1"
    command -v gcloud >/dev/null 2>&1 || export PATH="/opt/homebrew/bin:$PATH"
    # '| grep -vE' filters out noisy SSH host key warnings to keep the terminal clean.
    gcloud compute ssh diors-builds-bot --zone=us-east1-b --quiet --command="cd ~/diors-builds && ./scripts/deploy.sh $mode" 2>&1 | grep -vE "Warning: Permanently added"
}

_dior_bot_deploy() {
    if ! _dior_confirm "🚀 This will SSH into the VM, pull latest code, and restart the live bot service. Proceed?"; then
        echo "❌ Cancelled -- nothing was deployed."
        return
    fi
    echo "🚀 Triggering remote deploy (pull & restart) on GCP VM..."
    cd "$DIOR_BOT_DIR" || return
    echo "=== DEPLOY (git pull + restart on VM) ==="
    _dior_vm_deploy
}

_dior_bot_restart() {
    if ! _dior_confirm "🔄 This will SSH into the VM and restart the live bot service WITHOUT pulling new code. Proceed?"; then
        echo "❌ Cancelled -- nothing was restarted."
        return
    fi
    echo "🔄 Triggering remote manual restart (NO pull) on GCP VM..."
    echo "=== MANUAL RESTART (NO PULL) ==="
    _dior_vm_deploy manual
}
# Anonymous immediately-invoked function -- see the BOT_OBS_GUIDE block above
# for why (keeps this guide-text scratch variable from leaking as a global).
() {
    local BOT_DEPLOY_GUIDE="${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}🚀 GUIDE: dior bot deploy / restart${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Handles the Google Cloud Platform (GCP) remote pipeline.

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%-19s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior bot deploy" "Pulls the latest code from GitHub, writes a '.restart-reason' marker, and restarts the bot service ${DIOR_C_DIM}(confirms first)${DIOR_C_RESET}." \
    "dior bot restart" "Restarts the bot service WITHOUT pulling code -- skips 'git pull' entirely ${DIOR_C_DIM}(confirms first)${DIOR_C_RESET}.")

${DIOR_C_HEAD}IMPORTANT:${DIOR_C_RESET}
  ${DIOR_C_WARN}⚠️  deploy pulls from GitHub, not your local branch -- push your code first, or it deploys the old version.${DIOR_C_RESET}
  ${DIOR_C_WARN}⚠️  restart is for when you SSH in and change an .env secret manually and just need a reboot, no code change.${DIOR_C_RESET}
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"
    _dior_register "bot deploy" "Pull latest code from GitHub and restart bot on VM ${DIOR_C_DIM}(confirms first)${DIOR_C_RESET}" "$BOT_DEPLOY_GUIDE"
    _dior_register "bot restart" "Manually restart the bot on VM without pulling code ${DIOR_C_DIM}(confirms first)${DIOR_C_RESET}" "$BOT_DEPLOY_GUIDE"
}

_dior_bot_dev() {
    # Runs the LOCAL dev bot (separate Discord app + local Mongo -- see CLAUDE.md's
    # "local dev bot" section). Always uses .env.dev, never the prod .env/token.
    case "$3" in
        "kill")
            # Match only THIS exact invocation pattern so nothing else on the Mac
            # can ever get caught by this. Shows PID + full command line before
            # killing anything, and sends a plain SIGTERM (not -9) so discord.js
            # gets a chance to close its gateway connection cleanly.
            local matches
            matches=$(pgrep -fl "env-file=.env.dev.*index.js" 2>/dev/null)
            if [ -z "$matches" ]; then
                echo "📭 No local dev-bot instances found running."
            else
                echo "🔪 Found running dev-bot instance(s):"
                echo "$matches"
                echo "$matches" | awk '{print $1}' | xargs kill
                echo "✅ Sent SIGTERM. Re-run 'dior bot dev kill' if any linger."
            fi
            ;;
        "nowatch")
            cd "$DIOR_BOT_DIR" || return
            echo "🚀 Starting local dev bot (no --watch)..."
            node --env-file=.env.dev index.js
            ;;
        "")
            cd "$DIOR_BOT_DIR" || return
            echo "🚀 Starting local dev bot (--watch, auto-restarts on save)..."
            node --watch --env-file=.env.dev index.js
            ;;
        *)
            echo "Unknown 'dior bot dev' option: '$3'. Use nothing, 'nowatch', or 'kill'."
            ;;
    esac
}
_dior_register "bot dev" "Launch local dev bot ${DIOR_C_ARG}[nowatch|kill]${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}🧪 GUIDE: dior bot dev${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Runs the LOCAL dev bot. Always uses .env.dev, never the prod .env/token.

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%-22s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior bot dev" "Starts with ${DIOR_C_RESET}${DIOR_C_CMD}node --watch --env-file=.env.dev index.js${DIOR_C_RESET}${DIOR_C_DIM} (auto-restarts on every save)${DIOR_C_RESET}." \
    "dior bot dev nowatch" "Same, but without --watch ${DIOR_C_DIM}(for when file-watching gets in the way of debugging)${DIOR_C_RESET}." \
    "dior bot dev kill" "Finds and stops any locally-running dev-bot process.")

  ${DIOR_C_DIM}kill only ever looks at processes on THIS Mac -- it has no path to the VM or the prod
  token. It always prints the matched PID and command line before sending SIGTERM.${DIOR_C_RESET}
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"
