# ==============================================================================
# dior CLI — browse.zsh
# ==============================================================================
# The interactive (arrow-key) command browser that bare `dior` launches.
#
# Loaded by ~/.config/dior/dior.zsh AFTER core.zsh and help.zsh. Added
# 2026-07-27 12:30 EDT. `dior help` is deliberately untouched by this file --
# it stays a plain printed reference so it can still be piped, screenshotted,
# and (most importantly) diffed before/after a refactor, which is this repo's
# only real regression test. The browser is a SECOND surface over the same
# manifest, not a replacement for the first.
#
# THE ONE RULE THIS IS BUILT AROUND: always show the literal command that will
# run. The preview line at the bottom is the exact string handed to `dior`, so
# the browser teaches the CLI instead of replacing it. Every design decision
# below falls out of that -- notably, options the real CLI would REJECT can't
# be selected here at all (see the constraint tables), because a preview line
# that doesn't run would break the only promise this screen makes.
#
# KEY MAP:
#   up/down    move between commands
#   left/right move the cursor along the highlighted command's flags
#   Space      toggle the flag under the cursor
#   Tab        cycle the highlighted command's mode (bare word) -- including
#              "none", which is a real, distinct choice: it means the command's
#              own bare-invocation behavior
#   + / -      step a valued flag's number (only `--logs` has one today)
#   ?          print that command's full guide
#   Enter      run the previewed command
#   q          quit without running anything
#
# Esc is NOT a quit key, on purpose. Arrow keys arrive as the three bytes
# Esc-[-A, so an Esc-means-quit binding can only be told apart from an arrow by
# a read timeout -- i.e. by guessing, which feels randomly broken exactly when
# the terminal is slow. `q` is unambiguous and always works.

# ------------------------------------------------------------------------------
# Constraint tables
# ------------------------------------------------------------------------------
# ⚠️ THESE DUPLICATE VALIDATION THAT ALREADY LIVES IN bot.zsh. That is a real
# (accepted) cost: bot.zsh rejects a bad combination AFTER you type it, and the
# browser has to know the same rules BEFORE you can build it. There is no way to
# share one copy without making bot.zsh's validators introspectable, which is a
# much bigger change than this feature justifies. If you change a rule in
# bot.zsh, change it here too -- the pointers below name the exact lines.

# Mode -> flags that mode forbids. Mirrors bot.zsh's launch/registration guard:
# the dev bot re-registers its slash commands on every boot, so --list would show
# the previous boot's set and --clear would be undone seconds later.
typeset -gA DIOR_BROWSE_MODE_BLOCKS
DIOR_BROWSE_MODE_BLOCKS=(
    "bot dev watch"   "--list --clear"
    "bot dev nowatch" "--list --clear"
)

# Why, in three words, for the flag row. One per command is enough -- a command
# with two different reasons doesn't exist yet, and inventing the generality now
# would cost more than editing this line later.
typeset -gA DIOR_BROWSE_BLOCK_WHY
DIOR_BROWSE_BLOCK_WHY=(
    "bot dev" "kill or alone"
)

# Flags that are mutually exclusive with each other -- a second MODE axis
# wearing --flag syntax. bot.zsh rejects '--list --clear' outright, so turning
# one on here turns the other off rather than building a command that errors.
typeset -gA DIOR_BROWSE_FLAG_XGROUP
DIOR_BROWSE_FLAG_XGROUP=(
    "bot dev" "--list --clear"
)

# Commands where every mode is consequential and there is deliberately no
# default (see CLAUDE.md's option-grammar section). Enter is refused until you
# pick one, rather than the browser inventing a default the CLI declined to have.
typeset -gA DIOR_BROWSE_NEEDS_MODE
DIOR_BROWSE_NEEDS_MODE=(
    "bot vm" 1
    "update" 1
)

# Flags that carry a number, as "default step min max". The default matches the
# CLI's own (bot.zsh's --logs falls back to 25), so the browser's starting state
# and a bare `dior bot check --logs` mean the same thing.
typeset -gA DIOR_BROWSE_VALUES
DIOR_BROWSE_VALUES=(
    "bot check --logs" "25 5 5 500"
)

# ------------------------------------------------------------------------------
# Browser state
# ------------------------------------------------------------------------------
# Kept per-command rather than reset on every move, so arrowing away from a
# half-configured command and back doesn't silently discard what you picked.
typeset -gA DIOR_BROWSE_MODE    # "bot dev" -> "watch"  ("" means no mode / bare)
typeset -gA DIOR_BROWSE_ON      # "bot dev" -> " --list "  (space-delimited SET)
typeset -gA DIOR_BROWSE_FCUR    # "bot dev" -> 1  (1-based index into its flags)
typeset -gA DIOR_BROWSE_VALUE   # "bot check --logs" -> "50"
typeset -g  DIOR_BROWSE_SEL     # 1-based index into DIOR_MENU_ORDER

# Scratch, filled by _dior_browse_axes. Global because two other functions read
# them; `local` in the setter would make them invisible to the callers.
typeset -ga DIOR_BROWSE_A_MODES
typeset -ga DIOR_BROWSE_A_FLAGS

# Splits one command's DIOR_SUBOPTS string into its two axes. This is the whole
# reason the grammar's SHAPE rule is worth having: "bare word = mode, --x =
# flag" means the browser needs no separate table of what combines with what.
_dior_browse_axes() {
    local w
    DIOR_BROWSE_A_MODES=() DIOR_BROWSE_A_FLAGS=()
    for w in ${=DIOR_SUBOPTS[$1]}; do
        case "$w" in
            --*) DIOR_BROWSE_A_FLAGS+=("$w") ;;
            *)   DIOR_BROWSE_A_MODES+=("$w") ;;
        esac
    done
}

# Composite "<command> <flag>" keys are built into a single variable before
# being used as a subscript, never written inline as `arr[$key $f]=`. Two
# reasons, both load-bearing: zsh pattern-matches an assignment subscript and
# chokes on the embedded space ("bad pattern"), and CLAUDE.md's existing warning
# about literal-string subscripts applies for the same underlying reason. Reads
# happen to tolerate it; writes do not, so both use the variable form.
_dior_browse_vkey() { print -r -- "$1 $2" }

# All locals are declared ONCE at the top, never inside the loop. `local f` run a
# second time in the same scope makes zsh ECHO "f=<value>" to stdout instead of
# quietly redeclaring -- which corrupts every function here that returns its
# result on stdout.
_dior_browse_reset() {
    local key f vk
    local -a spec
    DIOR_BROWSE_SEL=1
    for key in "${DIOR_MENU_ORDER[@]}"; do
        DIOR_BROWSE_MODE[$key]=""
        DIOR_BROWSE_ON[$key]=" "
        DIOR_BROWSE_FCUR[$key]=1
        _dior_browse_axes "$key"
        for f in "${DIOR_BROWSE_A_FLAGS[@]}"; do
            vk="$(_dior_browse_vkey "$key" "$f")"
            if [ -n "${DIOR_BROWSE_VALUES[$vk]}" ]; then
                spec=( ${=DIOR_BROWSE_VALUES[$vk]} )
                DIOR_BROWSE_VALUE[$vk]="${spec[1]}"
            fi
        done
    done
}

# True (0) when $2 is a flag the currently-chosen mode of $1 forbids.
_dior_browse_blocked() {
    # ⚠️ `mode` is assigned on its OWN line, not folded into the `local` above.
    # zsh declares every name in a `local` statement BEFORE assigning any of
    # them, so `local key="$1" mode="${arr[$key]}"` reads the just-emptied local
    # `key`, not "$1" -- silently yielding an empty subscript. bash evaluates
    # left-to-right and does not have this behavior. Never reference a variable
    # in the same `local` that declares it.
    local key="$1" flag="$2" blocked vk mode
    mode="${DIOR_BROWSE_MODE[$key]}"
    [ -z "$mode" ] && return 1
    vk="$(_dior_browse_vkey "$key" "$mode")"
    blocked="${DIOR_BROWSE_MODE_BLOCKS[$vk]}"
    [ -z "$blocked" ] && return 1
    [[ " $blocked " == *" $flag "* ]]
}

_dior_browse_is_on() {
    [[ "${DIOR_BROWSE_ON[$1]}" == *" $2 "* ]]
}

_dior_browse_flag_off() {
    DIOR_BROWSE_ON[$1]="${DIOR_BROWSE_ON[$1]// $2 / }"
}

_dior_browse_flag_on() {
    _dior_browse_is_on "$1" "$2" || DIOR_BROWSE_ON[$1]="${DIOR_BROWSE_ON[$1]}$2 "
}

# ------------------------------------------------------------------------------
# The command line -- the single source of the preview AND of what Enter runs.
# ------------------------------------------------------------------------------
# Pure: reads state, writes a string, touches nothing else. Flags are emitted in
# DIOR_SUBOPTS order rather than toggle order, so the same selection always
# renders the same string -- which is what makes this diffable in a test.
_dior_browse_cmdline() {
    # `out` is assigned separately -- see the warning in _dior_browse_blocked.
    local key="$1" f vk out
    out="dior $key"
    [ -n "${DIOR_BROWSE_MODE[$key]}" ] && out="$out ${DIOR_BROWSE_MODE[$key]}"
    _dior_browse_axes "$key"
    for f in "${DIOR_BROWSE_A_FLAGS[@]}"; do
        if _dior_browse_is_on "$key" "$f"; then
            out="$out $f"
            vk="$(_dior_browse_vkey "$key" "$f")"
            [ -n "${DIOR_BROWSE_VALUES[$vk]}" ] && out="$out ${DIOR_BROWSE_VALUE[$vk]}"
        fi
    done
    print -r -- "$out"
}

# ------------------------------------------------------------------------------
# State transitions -- pure functions of (state, key). Testable without a tty.
# ------------------------------------------------------------------------------

# Cycles the mode forward, including a "" (no mode) position. "" is a genuine
# choice, not an empty initial state: `dior bot dev` bare means watch, and
# `dior bot vm` bare means "show me the guide" -- both are things you might
# actually want to run, so the cycle has to be able to express them.
_dior_browse_cycle_mode() {
    # `cur` is assigned separately -- see the warning in _dior_browse_blocked.
    local key="$1" i n cur
    cur="${DIOR_BROWSE_MODE[$key]}"
    _dior_browse_axes "$key"
    n=${#DIOR_BROWSE_A_MODES[@]}
    (( n == 0 )) && return

    # Position 0 is "", positions 1..n are the modes.
    local idx=0
    for (( i = 1; i <= n; i++ )); do
        [ "${DIOR_BROWSE_A_MODES[$i]}" = "$cur" ] && idx=$i && break
    done
    idx=$(( (idx + 1) % (n + 1) ))
    if (( idx == 0 )); then
        DIOR_BROWSE_MODE[$key]=""
    else
        DIOR_BROWSE_MODE[$key]="${DIOR_BROWSE_A_MODES[$idx]}"
    fi

    # Landing on a mode can invalidate flags that were already on. Drop them
    # rather than leaving an unrunnable command on screen -- "prevent invalid
    # combinations" has to hold in both directions, not just when toggling.
    local f
    for f in "${DIOR_BROWSE_A_FLAGS[@]}"; do
        _dior_browse_blocked "$key" "$f" && _dior_browse_flag_off "$key" "$f"
    done
}

_dior_browse_move_cursor() {
    local key="$1" delta="$2" n
    _dior_browse_axes "$key"
    n=${#DIOR_BROWSE_A_FLAGS[@]}
    (( n == 0 )) && return
    local cur=${DIOR_BROWSE_FCUR[$key]:-1}
    DIOR_BROWSE_FCUR[$key]=$(( (cur - 1 + delta + n) % n + 1 ))
}

_dior_browse_toggle_flag() {
    local key="$1" f other
    _dior_browse_axes "$key"
    (( ${#DIOR_BROWSE_A_FLAGS[@]} == 0 )) && return
    f="${DIOR_BROWSE_A_FLAGS[${DIOR_BROWSE_FCUR[$key]:-1}]}"

    # A blocked flag is a no-op, not an error. The row already says why it's
    # unavailable, so the useful response to Space is simply nothing happening.
    _dior_browse_blocked "$key" "$f" && return

    if _dior_browse_is_on "$key" "$f"; then
        _dior_browse_flag_off "$key" "$f"
    else
        # Turning on one member of an exclusive group turns the others off --
        # same reason Tab cycles modes instead of toggling them.
        for other in ${=DIOR_BROWSE_FLAG_XGROUP[$key]}; do
            [ "$other" != "$f" ] && _dior_browse_flag_off "$key" "$other"
        done
        _dior_browse_flag_on "$key" "$f"
    fi
}

# Steps a valued flag's number by its configured increment. Stepping a flag
# that's OFF also turns it on -- reaching for "+" on --logs can only mean you
# want logs.
_dior_browse_step_value() {
    local key="$1" dir="$2" f vk step min max next
    local -a spec
    _dior_browse_axes "$key"
    (( ${#DIOR_BROWSE_A_FLAGS[@]} == 0 )) && return
    f="${DIOR_BROWSE_A_FLAGS[${DIOR_BROWSE_FCUR[$key]:-1}]}"
    vk="$(_dior_browse_vkey "$key" "$f")"
    [ -z "${DIOR_BROWSE_VALUES[$vk]}" ] && return
    _dior_browse_blocked "$key" "$f" && return

    spec=( ${=DIOR_BROWSE_VALUES[$vk]} )   # default step min max
    step=${spec[2]} min=${spec[3]} max=${spec[4]}
    next=$(( ${DIOR_BROWSE_VALUE[$vk]} + dir * step ))

    # Clamped, not wrapped: jumping from the max back to the min on a "+" press
    # reads as a bug rather than a feature when you're holding the key down.
    (( next < min )) && next=$min
    (( next > max )) && next=$max
    DIOR_BROWSE_VALUE[$vk]=$next
    _dior_browse_flag_on "$key" "$f"
}

# ------------------------------------------------------------------------------
# Rendering -- pure, returns the frame on stdout. No cursor moves, no input.
# ------------------------------------------------------------------------------
# Colors come from core.zsh and are EMPTY when stdout isn't a tty, which makes
# `zsh -c 'source ~/.zshrc; _dior_browse_frame'` produce clean, diffable plain
# text. That is the intended test harness for everything in this section.

# The option rows for the highlighted command. Printed only for the selection --
# showing every command's options at once turns a 5-line list into a wall and
# defeats the point of having a menu.
_dior_browse_options() {
    local key="$1" m f row cur i point body vk
    _dior_browse_axes "$key"

    if (( ${#DIOR_BROWSE_A_MODES[@]} == 0 )) && (( ${#DIOR_BROWSE_A_FLAGS[@]} == 0 )); then
        echo "       ${DIOR_C_DIM}no options -- Enter opens the interactive git commit editor${DIOR_C_RESET}"
        return
    fi

    if (( ${#DIOR_BROWSE_A_MODES[@]} > 0 )); then
        row=""
        for m in "${DIOR_BROWSE_A_MODES[@]}"; do
            if [ "$m" = "${DIOR_BROWSE_MODE[$key]}" ]; then
                row="$row  ${DIOR_C_OPT}[$m]${DIOR_C_RESET}"
            else
                row="$row  ${DIOR_C_DIM}$m${DIOR_C_RESET}"
            fi
        done
        if [ -z "${DIOR_BROWSE_MODE[$key]}" ] && [ -n "${DIOR_BROWSE_NEEDS_MODE[$key]}" ]; then
            row="$row   ${DIOR_C_WARN}(pick one)${DIOR_C_RESET}"
        fi
        echo "       ${DIOR_C_DIM}mode${DIOR_C_RESET}$row"
    fi

    if (( ${#DIOR_BROWSE_A_FLAGS[@]} > 0 )); then
        row=""
        cur=${DIOR_BROWSE_FCUR[$key]:-1}
        i=0
        for f in "${DIOR_BROWSE_A_FLAGS[@]}"; do
            i=$(( i + 1 ))
            point="  "
            (( i == cur )) && point=" ${DIOR_C_OPT}>${DIOR_C_RESET}"
            body="$f"
            vk="$(_dior_browse_vkey "$key" "$f")"
            [ -n "${DIOR_BROWSE_VALUES[$vk]}" ] && body="$f ${DIOR_BROWSE_VALUE[$vk]}"
            # Two leading spaces per item so the cursor '>' reads as attached to
            # the flag AFTER it rather than floating between two of them.
            if _dior_browse_blocked "$key" "$f"; then
                row="$row  $point ${DIOR_C_DIM}x $body${DIOR_C_RESET}"
            elif _dior_browse_is_on "$key" "$f"; then
                row="$row  $point ${DIOR_C_OPT}* $body${DIOR_C_RESET}"
            else
                row="$row  $point ${DIOR_C_DIM}. $body${DIOR_C_RESET}"
            fi
        done
        echo "       ${DIOR_C_DIM}flag${DIOR_C_RESET}$row"

        # Only explain the block when something is actually blocked right now --
        # a permanent caveat line would read as noise on every other command.
        for f in "${DIOR_BROWSE_A_FLAGS[@]}"; do
            if _dior_browse_blocked "$key" "$f"; then
                echo "             ${DIOR_C_DIM}x = unavailable with '${DIOR_BROWSE_MODE[$key]}' (use ${DIOR_BROWSE_BLOCK_WHY[$key]})${DIOR_C_RESET}"
                break
            fi
        done
    fi
}

_dior_browse_frame() {
    local i key group lastgroup="" padded selkey
    selkey="${DIOR_MENU_ORDER[$DIOR_BROWSE_SEL]}"

    echo "${DIOR_C_TITLE}========================================================${DIOR_C_RESET}"
    echo "${DIOR_C_TITLE}👑 DIOR COMMAND BROWSER${DIOR_C_RESET}"
    echo "${DIOR_C_TITLE}========================================================${DIOR_C_RESET}"

    for (( i = 1; i <= ${#DIOR_MENU_ORDER[@]}; i++ )); do
        key="${DIOR_MENU_ORDER[$i]}"
        group="${key%% *}"
        if [ "$group" != "$lastgroup" ]; then
            echo ""
            if [ "$group" = "bot" ]; then
                echo "${DIOR_C_HEAD}🤖 BOT COMMANDS:${DIOR_C_RESET}"
            else
                echo "${DIOR_C_HEAD}🧹 MAINTENANCE COMMANDS:${DIOR_C_RESET}"
            fi
            lastgroup="$group"
        fi
        # Padding is computed on the PLAIN key, then wrapped in color -- printf's
        # width field counts the invisible escape bytes and would misalign the
        # column otherwise. Same rule as help.zsh's menu.
        padded=$(printf "%-11s" "$key")
        if (( i == DIOR_BROWSE_SEL )); then
            printf "${DIOR_C_OPT}> %s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" "$padded" "$DIOR_HELP_SUMMARY[$key]"
            _dior_browse_options "$key"
        else
            printf "  ${DIOR_C_CMD}%s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" "$padded" "$DIOR_HELP_SUMMARY[$key]"
        fi
    done

    echo ""
    echo "  ${DIOR_C_CMD}$(_dior_browse_cmdline "$selkey")${DIOR_C_RESET}"
    if [ -z "${DIOR_BROWSE_MODE[$selkey]}" ] && [ -n "${DIOR_BROWSE_NEEDS_MODE[$selkey]}" ]; then
        echo "  ${DIOR_C_WARN}Tab to pick a mode -- this command has no default on purpose${DIOR_C_RESET}"
    else
        echo "  ${DIOR_C_DIM}Enter runs exactly this${DIOR_C_RESET}"
    fi
    echo "${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"
    echo "  ${DIOR_C_DIM}up/down${DIOR_C_RESET} command  ${DIOR_C_DIM}left/right${DIOR_C_RESET} flag  ${DIOR_C_DIM}space${DIOR_C_RESET} toggle  ${DIOR_C_DIM}tab${DIOR_C_RESET} mode"
    echo "  ${DIOR_C_DIM}+/-${DIOR_C_RESET} count  ${DIOR_C_DIM}?${DIOR_C_RESET} guide  ${DIOR_C_DIM}enter${DIOR_C_RESET} run  ${DIOR_C_DIM}q${DIOR_C_RESET} quit"
}

# ------------------------------------------------------------------------------
# Input
# ------------------------------------------------------------------------------
# Normalizes one keypress to a word. Arrow keys are three bytes (Esc [ A) or,
# in application-cursor mode, (Esc O A) -- both are handled, since which one a
# terminal sends depends on its mode, not on which key you pressed. The short
# read timeout applies ONLY to the continuation bytes of an escape sequence, so
# a lone Esc degrades to "ignored" rather than to a misread arrow. It is never
# used to decide whether you meant to quit -- that's what `q` is for.
#
# `-u 0` (read from fd 0) rather than bare `read -k`, which zsh services from
# /dev/tty when the shell isn't interactive. _dior_browse already refuses to
# start unless fd 0 is a terminal, so the two are identical in real use -- but
# -u 0 also lets this function be driven from a pipe, which is the only way any
# of the key handling gets automated coverage.
_dior_browse_key() {
    local k rest
    read -k 1 -s -u 0 k || return 1
    case "$k" in
        $'\e')
            read -k 1 -s -u 0 -t 0.05 rest || { echo other; return 0; }
            case "$rest" in
                '['|'O')
                    read -k 1 -s -u 0 -t 0.05 rest || { echo other; return 0; }
                    case "$rest" in
                        A) echo up ;;
                        B) echo down ;;
                        C) echo right ;;
                        D) echo left ;;
                        *) echo other ;;
                    esac ;;
                *) echo other ;;
            esac ;;
        $'\t')        echo tab ;;
        $'\n'|$'\r')  echo enter ;;
        ' ')          echo space ;;
        '?')          echo guide ;;
        '+'|'=')      echo plus ;;   # '=' is unshifted '+', so accept both
        '-'|'_')      echo minus ;;
        q|Q)          echo quit ;;
        *)            echo other ;;
    esac
}

# ------------------------------------------------------------------------------
# Terminal handling
# ------------------------------------------------------------------------------
# Only the cursor is ever hidden -- `read -k -s` handles raw/no-echo per read and
# puts the terminal back itself, so there is no stty state to save and no way for
# a crash to leave the shell in a mode you have to `reset` out of. The cursor is
# restored by _dior_browse_cleanup on EVERY exit path, including Ctrl-C.
_dior_browse_cleanup() {
    printf '\e[?25h'
}

_dior_browse_redraw() {
    local frame="$1"
    # Move up over the previous frame and clear to end of screen, then reprint.
    # Tracking the printed line count is what keeps this from smearing; getting
    # it wrong leaves ghost rows behind, which is the classic failure here.
    (( DIOR_BROWSE_LASTLINES > 0 )) && printf '\e[%dA\e[J' "$DIOR_BROWSE_LASTLINES"
    print -r -- "$frame"
    DIOR_BROWSE_LASTLINES=$(( ${#${(f)frame}} + 1 ))
}

# ------------------------------------------------------------------------------
# The loop
# ------------------------------------------------------------------------------
_dior_browse() {
    # Refuse outright rather than emitting control codes into a pipe. core.zsh
    # computes the DIOR_C_* codes once at source time under `[[ -t 1 ]]`, so in a
    # non-tty they're empty and the cursor/redraw escapes below would be the only
    # thing written -- garbage in, garbage out. The printed menu is the right
    # answer for a pipe, and it's one function call away.
    if [[ ! -t 0 || ! -t 1 ]]; then
        _dior_print_menu
        return
    fi
    # The frame runs ~20 lines with a command expanded; below this the terminal
    # scrolls, which makes the cursor-up arithmetic overshoot and smear.
    if [[ -n "$LINES" ]] && (( LINES < 24 )); then
        echo "${DIOR_C_WARN}⚠️  Terminal too short for the browser (need 24 rows, have $LINES)${DIOR_C_RESET}"
        _dior_print_menu
        return
    fi

    _dior_browse_reset
    typeset -g DIOR_BROWSE_LASTLINES=0

    # Ctrl-C is trapped rather than left to kill the function mid-draw, so the
    # cursor always comes back. NOTE: Harkirat has Ctrl-C remapped at the OS
    # level, so this must not be the ONLY way out -- `q` is the real exit.
    trap '_dior_browse_cleanup; trap - INT; return 130' INT
    printf '\e[?25l'

    local k key n=${#DIOR_MENU_ORDER[@]} cmdline
    while true; do
        key="${DIOR_MENU_ORDER[$DIOR_BROWSE_SEL]}"
        _dior_browse_redraw "$(_dior_browse_frame)"

        k=$(_dior_browse_key) || break
        case "$k" in
            up)    DIOR_BROWSE_SEL=$(( (DIOR_BROWSE_SEL - 2 + n) % n + 1 )) ;;
            down)  DIOR_BROWSE_SEL=$(( DIOR_BROWSE_SEL % n + 1 )) ;;
            left)  _dior_browse_move_cursor "$key" -1 ;;
            right) _dior_browse_move_cursor "$key" 1 ;;
            tab)   _dior_browse_cycle_mode "$key" ;;
            space) _dior_browse_toggle_flag "$key" ;;
            plus)  _dior_browse_step_value "$key" 1 ;;
            minus) _dior_browse_step_value "$key" -1 ;;
            guide)
                # Hand the screen back before printing -- the guide is taller
                # than the frame and the redraw arithmetic can't account for it.
                _dior_browse_cleanup
                printf '\e[J'
                DIOR_BROWSE_LASTLINES=0
                echo "${DIOR_HELP_DETAIL[$key]}"
                echo ""
                printf "${DIOR_C_DIM}  press any key to return to the browser${DIOR_C_RESET}"
                read -k 1 -s -u 0
                printf '\r\e[J'
                printf '\e[?25l'
                ;;
            enter)
                if [ -z "${DIOR_BROWSE_MODE[$key]}" ] && [ -n "${DIOR_BROWSE_NEEDS_MODE[$key]}" ]; then
                    continue
                fi
                cmdline="$(_dior_browse_cmdline "$key")"
                break
                ;;
            quit)  cmdline=""; break ;;
        esac
    done

    _dior_browse_cleanup
    trap - INT

    [ -z "$cmdline" ] && return

    # Restore the screen BEFORE running anything. `_dior_confirm` reads with a
    # plain `read -r` and `bot dev` launches a foreground node process -- both
    # need a normal terminal and a visible cursor, and debugging the alternative
    # is miserable.
    echo ""
    echo "${DIOR_C_DIM}\$${DIOR_C_RESET} ${DIOR_C_CMD}${cmdline}${DIOR_C_RESET}"
    echo ""

    # Word-split rather than `eval`: every token here is a mode, a flag, or a
    # number from a fixed list, so there is nothing to quote and nothing that
    # could smuggle in shell syntax. Goes through the real `dior` dispatcher so
    # the confirm gates on commit/deploy/restart still fire exactly as they do
    # when you type the command yourself.
    local -a argv
    argv=( ${=cmdline} )
    shift argv
    dior "${argv[@]}"
}
