# ==============================================================================
# 📄 TEXT — small standalone text utilities, unrelated to the bot itself
# ==============================================================================
#
# Added 2026-08-03 21:24 EDT. First command: `text unwrap` -- LLM output
# (Claude especially) sometimes hard-wraps prose at a fixed column width,
# where every visual line is a real "\n", not a soft wrap. This rejoins those
# into flowing paragraphs while leaving headings/lists/code fences/blockquotes/
# tables/front matter alone.
#
# Engine swapped 2026-09-06 EDT: now runs scripts/reflow-prose.mjs, a port of
# Diors-Builds' drastically-revised docs-reflow engine (itself the successor
# to this command's original engine, MarkEdit's `markedit-dior-unwrap.js`).
# The old engine's blockquote handling collapsed a multi-paragraph `>` block
# into one marker line, losing the bare `>` that separates quoted paragraphs
# -- see scripts/reflow-prose.mjs's header for the full rationale and the
# conservation invariant it now verifies before writing anything.
#
# `text paste` added the same day, alongside the engine swap: `text unwrap -`
# reads stdin, but a human pasting a genuinely long document directly into an
# open stdin prompt goes through the terminal's own line discipline, which on
# some ttys silently truncates a very long single line at a fixed per-line
# buffer size (canonical-mode input queues are commonly 1-4KB) -- a failure
# mode that never shows up in a quick 2-3 line test. `text paste` sidesteps
# the tty entirely: it reads the clipboard via `pbpaste` straight into a file
# (a real pipe, not a line-buffered terminal read), so document length never
# interacts with terminal buffering.

# ------------------------------------------------------------------------------
# Shared engine runner for `text unwrap` and `text paste` -- one call site for
# invoking scripts/reflow-prose.mjs so the two commands can't drift out of
# sync on how failures are reported. Prints "⚠️ Failed:" + the script's
# stderr and returns 1 on failure; on success, echoes the script's
# machine-readable "inputLines outputLines changed" line for the caller to
# parse.
# ------------------------------------------------------------------------------
_dior_text_reflow_run() {
    local input="$1" output="$2" result
    result="$(node "$DIOR_CLI_DIR/scripts/reflow-prose.mjs" "$input" "$output" 2>&1)"
    if [ $? -ne 0 ]; then
        echo "${DIOR_C_ERROR}⚠️  Failed:${DIOR_C_RESET}"
        echo "$result"
        return 1
    fi
    echo "$result"
}

# ------------------------------------------------------------------------------
# dior text unwrap — fix hard-wrapped lines in a Markdown/text file
# ------------------------------------------------------------------------------
_dior_text_unwrap() {
    shift 2
    local input="" outdir="$HOME/Downloads" in_place=0 out_given=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --out|-o)
                if [ -z "$2" ]; then
                    echo "${DIOR_C_ERROR}⚠️  --out needs a directory argument${DIOR_C_RESET}"
                    return 1
                fi
                outdir="$2"
                out_given=1
                shift
                ;;
            --in-place|-i) in_place=1 ;;
            --help|-h) dior help text unwrap; return ;;
            -*)
                if [ "$1" != "-" ]; then
                    _dior_bad_opt "text unwrap" "$1"; return 1
                fi
                ;&
            *)
                if [ -n "$input" ]; then
                    echo "${DIOR_C_ERROR}⚠️  Only one input file is supported (already got '$input')${DIOR_C_RESET}"
                    return 1
                fi
                input="$1"
                ;;
        esac
        shift
    done

    if [ -z "$input" ]; then
        dior help text unwrap
        return 1
    fi
    local from_stdin=0
    [ "$input" = "-" ] && from_stdin=1
    if [ "$from_stdin" -eq 0 ] && [ ! -f "$input" ]; then
        echo "${DIOR_C_ERROR}⚠️  No such file: ${DIOR_C_ARG}$input${DIOR_C_RESET}"
        return 1
    fi
    if [ "$in_place" -eq 1 ] && [ "$out_given" -eq 1 ]; then
        echo "${DIOR_C_ERROR}⚠️  --in-place and --out are mutually exclusive -- in-place always writes back to the input file itself${DIOR_C_RESET}"
        return 1
    fi
    if [ "$from_stdin" -eq 1 ] && [ "$in_place" -eq 1 ]; then
        echo "${DIOR_C_ERROR}⚠️  --in-place needs a real file -- pasted input (${DIOR_C_ARG}-${DIOR_C_RESET}) has nothing to write back to${DIOR_C_RESET}"
        return 1
    fi
    if ! command -v node >/dev/null 2>&1; then
        echo "${DIOR_C_ERROR}⚠️  node isn't on PATH -- required to run the reflow script${DIOR_C_RESET}"
        return 1
    fi

    local output
    if [ "$in_place" -eq 1 ]; then
        # Resolve to an absolute path the same way the non-in-place branch does below, so the
        # printed path is consistent either way -- cosmetic only, doesn't change what gets written.
        output="$(cd "$(dirname "$input")" && pwd)/$(basename "$input")" || return 1
    else
        mkdir -p "$outdir" || return 1
        # Resolve to an absolute path via a subshell cd -- keeps this correct regardless of the
        # caller's cwd, mirrors bot commit's "git -C over cd" reasoning without touching the real shell.
        outdir="$(cd "$outdir" && pwd)" || return 1

        local base ext
        if [ "$from_stdin" -eq 1 ]; then
            base="pasted"
            ext="md"
        else
            base="${input:t:r}"    # zsh modifiers: :t = tail (basename), :r = remove extension
            ext="${input:e}"       # :e = extension, without the dot
            [ -z "$ext" ] && ext="md"
        fi
        output="$outdir/${base}-unwrapped.${ext}"
    fi

    local result
    result="$(_dior_text_reflow_run "$input" "$output")"
    if [ $? -ne 0 ]; then
        echo "$result"
        return 1
    fi

    local in_lines out_lines changed
    read -r in_lines out_lines changed <<< "$result"
    if [ "$changed" = "0" ]; then
        echo "${DIOR_C_DIM}No hard-wrapped lines found${DIOR_C_RESET} ${DIOR_C_DIM}($([ "$in_place" -eq 1 ] && echo "left as-is" || echo "wrote an unchanged copy anyway"))${DIOR_C_RESET}"
        [ "$in_place" -eq 1 ] && return
    fi
    if [ "$in_place" -eq 1 ]; then
        echo "${DIOR_C_HEAD}Fixed in place:${DIOR_C_RESET} ${DIOR_C_ARG}$output${DIOR_C_RESET} ${DIOR_C_DIM}($in_lines -> $out_lines lines)${DIOR_C_RESET}"
    else
        local shown_input="$input"
        [ "$from_stdin" -eq 1 ] && shown_input="(stdin)"
        echo "${DIOR_C_HEAD}Fixed:${DIOR_C_RESET} ${DIOR_C_ARG}$shown_input${DIOR_C_RESET} ${DIOR_C_DIM}($in_lines lines)${DIOR_C_RESET} -> ${DIOR_C_ARG}$output${DIOR_C_RESET} ${DIOR_C_DIM}($out_lines lines)${DIOR_C_RESET}"
    fi
}
_dior_register "text unwrap" "Rejoin LLM-style hard-wrapped lines in ${DIOR_C_ARG}<file>${DIOR_C_RESET}${DIOR_C_OPT}|-${DIOR_C_RESET} ${DIOR_C_OPT}[--out <dir>|--in-place]${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}📄 HARD-BREAK FIXER${DIOR_C_RESET} ${DIOR_C_DIM}— dior text unwrap${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Rejoins prose that got hard-wrapped at a fixed column width (every visual line
is a real newline, not a soft wrap -- common when pasting LLM output) back
into flowing paragraphs. Headings, lists (rejoined per-item), fenced/indented
code blocks, blockquotes, tables, thematic breaks, HTML lines, YAML front
matter, and genuine Markdown hard breaks (2+ trailing spaces, or a trailing
backslash) are all left alone.

${DIOR_C_HEAD}USAGE${DIOR_C_RESET}
  ${DIOR_C_CMD}dior text unwrap${DIOR_C_RESET} ${DIOR_C_ARG}<file>${DIOR_C_RESET}                 ${DIOR_C_DIM}-> writes <name>-unwrapped.<ext> to ~/Downloads${DIOR_C_RESET}
  ${DIOR_C_CMD}dior text unwrap${DIOR_C_RESET} ${DIOR_C_ARG}<file>${DIOR_C_RESET} ${DIOR_C_OPT}--out <dir>${DIOR_C_RESET}   ${DIOR_C_DIM}-> writes it there instead${DIOR_C_RESET}
  ${DIOR_C_CMD}dior text unwrap${DIOR_C_RESET} ${DIOR_C_ARG}<file>${DIOR_C_RESET} ${DIOR_C_OPT}-o <dir>${DIOR_C_RESET}      ${DIOR_C_DIM}-> same, short form${DIOR_C_RESET}
  ${DIOR_C_CMD}dior text unwrap${DIOR_C_RESET} ${DIOR_C_ARG}<file>${DIOR_C_RESET} ${DIOR_C_OPT}--in-place${DIOR_C_RESET}   ${DIOR_C_DIM}-> overwrites <file> itself, no copy${DIOR_C_RESET}
  ${DIOR_C_CMD}dior text unwrap${DIOR_C_RESET} ${DIOR_C_ARG}<file>${DIOR_C_RESET} ${DIOR_C_OPT}-i${DIOR_C_RESET}           ${DIOR_C_DIM}-> same, short form${DIOR_C_RESET}
  ${DIOR_C_CMD}<cmd> | dior text unwrap${DIOR_C_RESET} ${DIOR_C_ARG}-${DIOR_C_RESET}         ${DIOR_C_DIM}-> reads stdin (piped from another command), writes pasted-unwrapped.md${DIOR_C_RESET}

Without ${DIOR_C_OPT}--in-place${DIOR_C_RESET}, the original file is never modified -- the fixed copy is always a
new file. ${DIOR_C_OPT}--in-place${DIOR_C_RESET} and ${DIOR_C_OPT}--out${DIOR_C_RESET} are mutually exclusive.

${DIOR_C_DIM}Pasting a whole document by hand? Use ${DIOR_C_RESET}${DIOR_C_CMD}dior text paste${DIOR_C_RESET}${DIOR_C_DIM} instead -- it reads${DIOR_C_RESET}
${DIOR_C_DIM}the clipboard directly rather than an open stdin prompt, which avoids the${DIOR_C_RESET}
${DIOR_C_DIM}per-line truncation risk of a long interactive tty paste. The ${DIOR_C_RESET}${DIOR_C_ARG}-${DIOR_C_RESET}${DIOR_C_DIM} form above${DIOR_C_RESET}
${DIOR_C_DIM}is for piping text in from another command, not for pasting by hand.${DIOR_C_RESET}"

# ------------------------------------------------------------------------------
# dior text paste — reflow whatever's on the clipboard, no file and no open
# stdin prompt involved
# ------------------------------------------------------------------------------
_dior_text_paste() {
    shift 2
    local outdir="" out_given=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --out|-o)
                if [ -z "$2" ]; then
                    echo "${DIOR_C_ERROR}⚠️  --out needs a directory argument${DIOR_C_RESET}"
                    return 1
                fi
                outdir="$2"
                out_given=1
                shift
                ;;
            --help|-h) dior help text paste; return ;;
            *) _dior_bad_opt "text paste" "$1"; return 1 ;;
        esac
        shift
    done

    if ! command -v pbpaste >/dev/null 2>&1 || ! command -v pbcopy >/dev/null 2>&1; then
        echo "${DIOR_C_ERROR}⚠️  pbpaste/pbcopy aren't on PATH -- this command is macOS-only${DIOR_C_RESET}"
        return 1
    fi
    if ! command -v node >/dev/null 2>&1; then
        echo "${DIOR_C_ERROR}⚠️  node isn't on PATH -- required to run the reflow script${DIOR_C_RESET}"
        return 1
    fi

    # pbpaste's stdout goes straight into a real file -- a pipe, never the
    # tty's line discipline -- which is the whole point of this command over
    # `dior text unwrap -` for a document pasted by hand: a long interactive
    # tty paste can be silently truncated per-line by the terminal's
    # canonical-mode input buffer, and that risk doesn't exist for a pipe.
    local tmp_in tmp_out
    tmp_in="$(mktemp "${TMPDIR:-/tmp}/dior-paste-in.XXXXXX")" || return 1
    tmp_out="$(mktemp "${TMPDIR:-/tmp}/dior-paste-out.XXXXXX")" || return 1
    pbpaste > "$tmp_in"

    if [ ! -s "$tmp_in" ]; then
        echo "${DIOR_C_DIM}Clipboard is empty -- nothing to reflow${DIOR_C_RESET}"
        rm -f "$tmp_in" "$tmp_out"
        return 1
    fi

    local result
    result="$(_dior_text_reflow_run "$tmp_in" "$tmp_out")"
    if [ $? -ne 0 ]; then
        echo "$result"
        rm -f "$tmp_in" "$tmp_out"
        return 1
    fi

    local in_lines out_lines changed
    read -r in_lines out_lines changed <<< "$result"

    if [ "$out_given" -eq 1 ]; then
        mkdir -p "$outdir" || { rm -f "$tmp_in" "$tmp_out"; return 1; }
        outdir="$(cd "$outdir" && pwd)" || { rm -f "$tmp_in" "$tmp_out"; return 1; }
        local output="$outdir/pasted-unwrapped.md"
        cp "$tmp_out" "$output"
        echo "${DIOR_C_HEAD}Fixed:${DIOR_C_RESET} ${DIOR_C_ARG}(clipboard)${DIOR_C_RESET} ${DIOR_C_DIM}($in_lines lines)${DIOR_C_RESET} -> ${DIOR_C_ARG}$output${DIOR_C_RESET} ${DIOR_C_DIM}($out_lines lines)${DIOR_C_RESET}"
    else
        pbcopy < "$tmp_out"
        if [ "$changed" = "0" ]; then
            echo "${DIOR_C_DIM}No hard-wrapped lines found -- clipboard left as-is${DIOR_C_RESET}"
        else
            echo "${DIOR_C_HEAD}Fixed:${DIOR_C_RESET} ${DIOR_C_DIM}($in_lines -> $out_lines lines) -- copied back to the clipboard, ready to paste${DIOR_C_RESET}"
        fi
    fi
    rm -f "$tmp_in" "$tmp_out"
}
_dior_register "text paste" "Reflow the clipboard's contents ${DIOR_C_OPT}[--out <dir>]${DIOR_C_RESET} ${DIOR_C_DIM}(copies the fix back to the clipboard by default)${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}📋 CLIPBOARD REFLOW${DIOR_C_RESET} ${DIOR_C_DIM}— dior text paste${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Same engine as ${DIOR_C_CMD}dior text unwrap${DIOR_C_RESET}, sourced from the macOS clipboard instead of a
file or stdin. Built for pasting a genuinely long document: reading it via
${DIOR_C_CMD}pbpaste${DIOR_C_RESET} into a file never touches the terminal's own line discipline, so
there's no risk of a long pasted line getting silently truncated the way an
interactive tty paste into an open stdin prompt can be.

${DIOR_C_HEAD}USAGE${DIOR_C_RESET}
  ${DIOR_C_CMD}dior text paste${DIOR_C_RESET}                     ${DIOR_C_DIM}-> reflows the clipboard, copies the result back to it${DIOR_C_RESET}
  ${DIOR_C_CMD}dior text paste${DIOR_C_RESET} ${DIOR_C_OPT}--out <dir>${DIOR_C_RESET}         ${DIOR_C_DIM}-> writes pasted-unwrapped.md there instead of touching the clipboard${DIOR_C_RESET}
  ${DIOR_C_CMD}dior text paste${DIOR_C_RESET} ${DIOR_C_OPT}-o <dir>${DIOR_C_RESET}            ${DIOR_C_DIM}-> same, short form${DIOR_C_RESET}

Copy the text you want fixed, run the command with nothing else on the
clipboard queue in between, then paste -- the clipboard now holds the
reflowed version, ready to go wherever it's needed."
