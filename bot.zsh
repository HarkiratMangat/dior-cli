# ==============================================================================
# dior CLI — bot.zsh
# ==============================================================================
# The 'bot' command group: local dev bot, git commit, VM deploy/restart, observability.
#
# Loaded by ~/.config/dior/dior.zsh, which ~/.zshrc sources. Split out of
# ~/.zshrc on 2026-07-27 11:10 EDT (it had grown to 675 of that file's 723 lines, with no
# version control and no backup) — a pure relocation, no behavior change. See
# dior.zsh for the architecture overview and the load order these files rely on.
#
# CONSOLIDATED 2026-07-27 11:10 EDT from 8 commands to 4:
#   bot commands list|clear  -> bot dev --list / --clear   (both were dev-only)
#   bot deploy / bot restart -> bot vm deploy|restart
#   bot status/baseline/logs/peaks -> bot check [mode] [--flags]
# `bot baseline` turned out to be `bot status` with a banner -- both ran the
# same scripts/vmstatus.sh -- which is why the old guide grouped them while the
# old menu didn't. It survives as the `baseline` MODE of bot check, keeping its
# pre-deploy header, and can never print alongside a plain status.

# ==============================================================================
# 🧪 LOCAL DEV BOT
# ==============================================================================

_dior_bot_dev() {
    # Runs the LOCAL dev bot (separate Discord app + local Mongo -- see CLAUDE.md's
    # "local dev bot" section). Always uses .env.dev, never the prod .env/token.
    shift 2
    local mode="" reg="" arg

    for arg in "$@"; do
        case "$arg" in
            watch|nowatch|kill)
                if [ -n "$mode" ]; then
                    echo "${DIOR_C_WARN}⚠️  '$mode' and '$arg' can't both run${DIOR_C_RESET} — they're modes, pick one"
                    return 1
                fi
                mode="$arg" ;;
            --list|--clear)
                if [ -n "$reg" ]; then
                    echo "${DIOR_C_WARN}⚠️  '$reg' and '$arg' can't both run${DIOR_C_RESET} — pick one"
                    return 1
                fi
                reg="$arg" ;;
            *) _dior_bad_opt "bot dev" "$arg"; return 1 ;;
        esac
    done

    # A slash-command action alongside a LAUNCH is always meaningless, in both
    # directions, so it's rejected rather than quietly reordered:
    #   --list  before a launch shows the PREVIOUS boot's commands (the bot
    #           re-registers them on startup), and it can't run after the launch
    #           because launching blocks the terminal until you stop it.
    #   --clear before a launch is undone seconds later by that same re-register.
    # Pairing them with `kill` is fine -- kill returns, so both actually happen.
    if [ -n "$reg" ] && { [ "$mode" = "watch" ] || [ "$mode" = "nowatch" ]; }; then
        echo "${DIOR_C_WARN}⚠️  '$reg' can't be combined with '$mode'${DIOR_C_RESET}"
        echo "   The dev bot re-registers its slash commands every time it boots, so"
        echo "   '$reg' would be stale or undone the moment '$mode' starts it."
        echo "   Run it on its own ${DIOR_C_DIM}(${DIOR_C_RESET}${DIOR_C_CMD}dior bot dev $reg${DIOR_C_RESET}${DIOR_C_DIM})${DIOR_C_RESET}, or alongside ${DIOR_C_CMD}kill${DIOR_C_RESET}"
        return 1
    fi

    # With no mode AND no flag at all, the default is a watch launch. With a flag
    # but no mode, the flag runs alone -- launching is what you get when you ask
    # for nothing, not something that tags along behind an explicit request.
    if [ -z "$mode" ] && [ -z "$reg" ]; then
        mode="watch"
    fi

    # Fixed execution order, derived from one fact: launching blocks the
    # terminal, so anything that RETURNS has to happen before it or never at all.
    if [ "$mode" = "kill" ]; then
        # Match only THIS exact invocation pattern so nothing else on the Mac
        # can ever get caught by this. Shows PID + full command line before
        # killing anything, and sends a plain SIGTERM (not -9) so discord.js
        # gets a chance to close its gateway connection cleanly.
        local matches
        matches=$(pgrep -fl "env-file=.env.dev.*index.js" 2>/dev/null)
        if [ -z "$matches" ]; then
            echo "📭 No local dev-bot instances found running"
        else
            echo "🔪 Found running dev-bot instance(s):"
            echo "$matches"
            echo "$matches" | awk '{print $1}' | xargs kill
            echo "✅ Sent SIGTERM. Re-run 'dior bot dev kill' if any linger"
        fi
    fi

    case "$reg" in
        --list)  node "$DIOR_BOT_DIR/scripts/devCommands.js" list ;;
        --clear) node "$DIOR_BOT_DIR/scripts/devCommands.js" clear ;;
    esac

    # Subshell so the `cd` can't leak into the caller's shell and leave the
    # terminal sitting in the repo after the bot exits.
    case "$mode" in
        watch)
            echo "🚀 Starting local dev bot (--watch, auto-restarts on save)..."
            ( cd "$DIOR_BOT_DIR" && node --watch --env-file=.env.dev index.js ) ;;
        nowatch)
            echo "🚀 Starting local dev bot (no --watch)..."
            ( cd "$DIOR_BOT_DIR" && node --env-file=.env.dev index.js ) ;;
    esac
}
_dior_register "bot dev" "Run the local dev bot ${DIOR_C_OPT}[watch|nowatch|kill] [--list|--clear]${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}🧪 LOCAL DEV BOT${DIOR_C_RESET} ${DIOR_C_DIM}— dior bot dev${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Runs the LOCAL dev bot. Always uses .env.dev, never the prod .env/token.

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%s${DIOR_C_RESET} ${DIOR_C_OPT}%-8s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior bot dev" "" "Start it with \`node --watch --env-file=.env.dev index.js\`" \
    "dior bot dev" "nowatch" "Same, but without --watch ${DIOR_C_DIM}(when file-watching gets in the way of debugging)${DIOR_C_RESET}" \
    "dior bot dev" "kill" "Find and stop any locally-running dev-bot process" \
    "dior bot dev" "--list" "Show which slash commands the dev app currently has registered" \
    "dior bot dev" "--clear" "Unregister them so they vanish from Discord's / picker")

${DIOR_C_HEAD}COMBINING OPTIONS:${DIOR_C_RESET}
  ${DIOR_C_OPT}watch${DIOR_C_RESET}/${DIOR_C_OPT}nowatch${DIOR_C_RESET}/${DIOR_C_OPT}kill${DIOR_C_RESET} are modes ${DIOR_C_DIM}(pick one)${DIOR_C_RESET}; ${DIOR_C_OPT}--list${DIOR_C_RESET}/${DIOR_C_OPT}--clear${DIOR_C_RESET} stack onto ${DIOR_C_OPT}kill${DIOR_C_RESET} only
$(printf "  ${DIOR_C_CMD}%-25s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior bot dev kill --clear" "Stop the bot, then wipe its slash commands" \
    "dior bot dev kill --list" "Stop the bot, then show what's still registered" \
    "dior bot dev --list" "Just look -- nothing is started or stopped")

  ${DIOR_C_DIM}A launch can't be combined with --list/--clear: the dev bot re-registers its
  slash commands on every boot, so --list would show the previous boot's set and
  --clear would be undone seconds later. dior rejects those pairings outright.${DIOR_C_RESET}

  ${DIOR_C_DIM}kill only ever looks at processes on THIS Mac -- it has no path to the VM or
  the prod token. It always prints the matched PID and command line before
  sending SIGTERM.${DIOR_C_RESET}

  ${DIOR_C_DIM}To stop a running dev bot: Ctrl-\\ ${DIOR_C_RESET}${DIOR_C_DIM}(SIGQUIT), or ${DIOR_C_RESET}${DIOR_C_CMD}dior bot dev kill${DIOR_C_RESET}${DIOR_C_DIM} from a second tab.${DIOR_C_RESET}
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"

# ==============================================================================
# 📝 GIT COMMIT
# ==============================================================================

_dior_bot_commit() {
    # A smart commit wrapper.
    # $3 is the commit title, $4 is the optional detailed body.
    #
    # Uses `git -C` rather than `cd` so it can't leave the caller's shell sitting
    # in the repo afterwards -- a plain `cd` inside a function changes the real
    # interactive shell's working directory, which this used to do.
    if [ -z "$3" ]; then
        # No commit message -- open the standard interactive git editor. That
        # path has its own escape hatch (save empty / exit without saving), so it
        # doesn't need the confirm gate below.
        echo "📝 No message provided. Opening interactive git commit..."
        git -C "$DIOR_BOT_DIR" add .
        git -C "$DIOR_BOT_DIR" commit
    else
        echo "About to stage everything and commit:"
        echo "  Title: ${DIOR_C_ARG}$3${DIOR_C_RESET}"
        [ -n "$4" ] && echo "  Body:  ${DIOR_C_ARG}$4${DIOR_C_RESET}"
        if ! _dior_confirm "Proceed?"; then
            echo "❌ Cancelled -- nothing was staged or committed"
            return
        fi

        echo "💾 Staging and committing changes..."
        git -C "$DIOR_BOT_DIR" add .

        # If a body description ($4) is provided, pass it as a second -m flag to git
        if [ -n "$4" ]; then
            git -C "$DIOR_BOT_DIR" commit -q -m "$3" -m "$4"
        else
            git -C "$DIOR_BOT_DIR" commit -q -m "$3"
        fi

        echo "--- HEAD now ---"
        git -C "$DIOR_BOT_DIR" log --oneline -3
    fi
}
_dior_register "bot commit" "Stage all and commit ${DIOR_C_OPT}['<Title>' ['<Body>']]${DIOR_C_RESET} ${DIOR_C_DIM}(confirms first)${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}📝 GIT COMMIT${DIOR_C_RESET} ${DIOR_C_DIM}— dior bot commit${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
A smart wrapper for Git staging and committing.
${DIOR_C_DIM}The quotes in the USAGE examples below are real characters to type, not placeholder
notation -- see QUOTE RULES at the bottom for which kind to use.${DIOR_C_RESET}

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%s${DIOR_C_RESET} ${DIOR_C_OPT}%-21s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior bot commit" "" "Opens your editor for a multi-line commit" \
    "dior bot commit" "'<Title>'" "Quick commit, title only ${DIOR_C_DIM}(shows a y/N confirm first)${DIOR_C_RESET}" \
    "dior bot commit" "'<Title>' '<Body>'" "Title + body ${DIOR_C_DIM}(also confirms first)${DIOR_C_RESET}")

  ${DIOR_C_WARN}⚠️  A single '-' flag (e.g. '-help' instead of '--help'/'-h') is NOT recognized as a
     help flag -- it gets read as the commit Title. The confirm step above is the safety net.${DIOR_C_RESET}

${DIOR_C_HEAD}CONVENTIONAL COMMITS RULESET:${DIOR_C_RESET}
  Format: ${DIOR_C_ARG}<type>(<optional scope>): <description>${DIOR_C_RESET} ${DIOR_C_DIM}(lowercase, no trailing period)${DIOR_C_RESET}
  Breaking change: put ${DIOR_C_ARG}!${DIOR_C_RESET} right before the colon, e.g. 'feat!: drop old API'

$(printf "  ${DIOR_C_CMD}%-10s${DIOR_C_RESET} %s\n" \
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
$(printf "  ${DIOR_C_CMD}•${DIOR_C_RESET} %-22s ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "Single Quotes ('...')" "BEST -- use these if your message has special characters, code, or double quotes inside" \
    "Double Quotes (\"...\")" "OK, but the terminal might misinterpret dollar signs (\$) or backticks")
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"

# ==============================================================================
# 🚀 VM DEPLOYMENT
# ==============================================================================

# Shared by both deploy and restart -- they differ only in whether 'manual' gets
# passed to deploy.sh, so the gcloud PATH-fix + SSH call lives once.
_dior_vm_deploy() {
    local mode="$1"
    command -v gcloud >/dev/null 2>&1 || export PATH="/opt/homebrew/bin:$PATH"
    # '| grep -vE' filters out noisy SSH host key warnings to keep the terminal clean.
    gcloud compute ssh diors-builds-bot --zone=us-east1-b --quiet --command="cd ~/diors-builds && ./scripts/deploy.sh $mode" 2>&1 | grep -vE "Warning: Permanently added"
}

_dior_bot_vm() {
    # No default action on purpose. Every mode here touches the LIVE prod bot,
    # so a bare `dior bot vm` shows the guide rather than picking one for you --
    # bare-word defaulting to `deploy` is exactly the class of accident that the
    # confirm gates below exist to catch.
    case "$3" in
        deploy)
            if ! _dior_confirm "🚀 This will SSH into the VM, pull latest code, and restart the live bot service. Proceed?"; then
                echo "❌ Cancelled -- nothing was deployed"
                return
            fi
            echo "🚀 Triggering remote deploy (pull & restart) on GCP VM..."
            echo "=== DEPLOY (git pull + restart on VM) ==="
            _dior_vm_deploy
            ;;
        restart)
            if ! _dior_confirm "🔄 This will SSH into the VM and restart the live bot service WITHOUT pulling new code. Proceed?"; then
                echo "❌ Cancelled -- nothing was restarted"
                return
            fi
            echo "🔄 Triggering remote manual restart (NO pull) on GCP VM..."
            echo "=== MANUAL RESTART (NO PULL) ==="
            _dior_vm_deploy manual
            ;;
        "") dior help bot vm ;;
        *)  _dior_bad_opt "bot vm" "$3"; return 1 ;;
    esac
}
_dior_register "bot vm" "Deploy or restart the live bot ${DIOR_C_ARG}<deploy|restart>${DIOR_C_RESET} ${DIOR_C_DIM}(confirms first)${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}🚀 VM DEPLOYMENT${DIOR_C_RESET} ${DIOR_C_DIM}— dior bot vm${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Handles the Google Cloud Platform (GCP) remote pipeline.

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%s${DIOR_C_RESET} ${DIOR_C_ARG}%-8s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior bot vm" "deploy" "Pull the latest code from GitHub, write a '.restart-reason' marker, and restart the bot service" \
    "dior bot vm" "restart" "Restart the bot service WITHOUT pulling code -- skips 'git pull' entirely")

  ${DIOR_C_DIM}Both confirm before doing anything. A bare 'dior bot vm' shows this guide
  rather than defaulting to either one -- both touch the live prod bot.${DIOR_C_RESET}

${DIOR_C_HEAD}IMPORTANT:${DIOR_C_RESET}
  ${DIOR_C_WARN}⚠️  deploy pulls from GitHub, not your local branch -- push your code first, or it deploys the old version.${DIOR_C_RESET}
  ${DIOR_C_WARN}⚠️  restart is for when you SSH in and change an .env secret manually and just need a reboot, no code change.${DIOR_C_RESET}
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"

# ==============================================================================
# 📊 BOT OBSERVABILITY
# ==============================================================================

_dior_bot_check() {
    shift 2
    local mode="" want_peaks=0 want_logs=0 want_all=0 logs_n=25 sawflag=0 sections=0

    while [ $# -gt 0 ]; do
        case "$1" in
            status|baseline)
                if [ -n "$mode" ] && [ "$mode" != "$1" ]; then
                    # status and baseline are two PRESENTATIONS of one section,
                    # not two sections -- printing both would be the same data
                    # twice. Refuse rather than silently picking one.
                    echo "${DIOR_C_WARN}⚠️  'status' and 'baseline' can't both run${DIOR_C_RESET}"
                    echo "   They're the same check -- baseline just adds a pre-deploy header. Pick one."
                    return 1
                fi
                mode="$1" ;;
            --peaks) want_peaks=1; sawflag=1 ;;
            --logs)
                want_logs=1; sawflag=1
                # Consume a following count only if it's actually numeric, so
                # `--logs --peaks` doesn't eat the next flag as a line count.
                if [[ "$2" == <-> ]]; then logs_n="$2"; shift; fi ;;
            --all) want_all=1; want_peaks=1; want_logs=1; sawflag=1 ;;
            *) _dior_bad_opt "bot check" "$1"; return 1 ;;
        esac
        shift
    done

    # Bare `dior bot check` means status. Naming ANY flag means you get exactly
    # the sections you named -- status doesn't tag along uninvited. --all is
    # defined as plain shorthand for `status --peaks --logs`, so it supplies the
    # default mode too (and leaves an explicit `baseline --all` alone).
    if [ -z "$mode" ] && { [ $sawflag -eq 0 ] || [ $want_all -eq 1 ]; }; then
        mode="status"
    fi

    [ -n "$mode" ] && sections=$((sections + 1))
    [ $want_peaks -eq 1 ] && sections=$((sections + 1))
    [ $want_logs -eq 1 ] && sections=$((sections + 1))

    # Headers only when more than one section is printing -- a lone status
    # doesn't need a banner announcing itself. The blank line SEPARATES
    # sections, so it goes before every header except the first; leading with
    # one just pushes the output away from the prompt for no reason.
    local printed=0
    _dior_check_head() {
        [ $sections -le 1 ] && return
        [ $printed -gt 0 ] && echo ""
        echo "${DIOR_C_HEAD}── $1 ──${DIOR_C_RESET}"
        printed=1
    }

    # FIXED output order regardless of the order the flags were typed in:
    # status -> peaks -> logs. A stable layout is skimmable; logs is always the
    # longest output, so it goes last and never buries the short sections.
    case "$mode" in
        baseline)
            _dior_check_head "BASELINE (pre-deploy)"
            [ $sections -le 1 ] && echo "=== BASELINE (pre-deploy) ==="
            bash "$DIOR_BOT_DIR/scripts/vmstatus.sh" 2>&1 ;;
        status)
            _dior_check_head "STATUS"
            "$DIOR_BOT_DIR/scripts/vmstatus.sh" ;;
    esac

    if [ $want_peaks -eq 1 ]; then
        _dior_check_head "PEAKS"
        "$DIOR_BOT_DIR/scripts/vmpeaks.sh"
    fi

    if [ $want_logs -eq 1 ]; then
        _dior_check_head "LOGS (last $logs_n)"
        "$DIOR_BOT_DIR/scripts/vmstatus.sh" logs "$logs_n"
    fi

    unfunction _dior_check_head
}
_dior_register "bot check" "VM health, usage peaks, and logs ${DIOR_C_OPT}[status|baseline] [--peaks] [--logs [N]]${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}📊 BOT OBSERVABILITY${DIOR_C_RESET} ${DIOR_C_DIM}— dior bot check${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Queries the GCP VM remotely to check on the bot's health.

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%s${DIOR_C_RESET} ${DIOR_C_OPT}%-11s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior bot check" "" "Same as 'status' -- the default when you name nothing" \
    "dior bot check" "status" "IP, systemd service state, load average, and RAM" \
    "dior bot check" "baseline" "The same snapshot, under a pre-deploy header" \
    "dior bot check" "--peaks" "12h/24h/7d CPU & RAM spikes from GCP Cloud Monitoring" \
    "dior bot check" "--logs [N]" "Last N lines of journalctl logs ${DIOR_C_DIM}(N defaults to 25)${DIOR_C_RESET}" \
    "dior bot check" "--all" "Shorthand for 'status --peaks --logs'")

${DIOR_C_HEAD}COMBINING OPTIONS:${DIOR_C_RESET}
  ${DIOR_C_OPT}status${DIOR_C_RESET}/${DIOR_C_OPT}baseline${DIOR_C_RESET} are modes ${DIOR_C_DIM}(pick one)${DIOR_C_RESET}; the ${DIOR_C_OPT}--flags${DIOR_C_RESET} stack freely onto either
$(printf "  ${DIOR_C_CMD}%-32s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior bot check --logs 40" "Just 40 lines of logs -- no status above them" \
    "dior bot check --logs 40 --peaks" "Peaks, then 40 lines of logs" \
    "dior bot check status --logs 40" "Status, then 40 lines of logs" \
    "dior bot check baseline --all" "Baseline, then peaks, then 25 lines of logs")

  ${DIOR_C_DIM}Sections always print in the same order -- status, then peaks, then logs --
  no matter what order you type the flags in. Logs is always the longest output,
  so it goes last and never buries the short sections above it.${DIOR_C_RESET}

  ${DIOR_C_DIM}Naming any flag gives you ONLY what you named. Bare 'dior bot check' is the
  one shorthand: it means 'status'.${DIOR_C_RESET}
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"
