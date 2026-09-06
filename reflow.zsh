# ==============================================================================
# 📄 REFLOW — rejoin hard-wrapped prose into soft-wrapped paragraphs
# ==============================================================================
#
# History: added 2026-08-03 21:24 EDT as `text unwrap`, a CLI port of the
# MarkEdit extension `markedit-dior-unwrap.js` (the "Hard-Break Fixer") -- LLM
# output (Claude especially) sometimes hard-wraps prose at a fixed column
# width, where every visual line is a real "\n", not a soft wrap. Engine
# swapped 2026-09-06 EDT to scripts/reflow-prose.mjs, a port of Diors-Builds'
# drastically-revised docs-reflow engine: the old engine's blockquote handling
# collapsed a multi-paragraph `>` block into one marker line, losing the bare
# `>` that separates quoted paragraphs -- see reflow-prose.mjs's header for
# the full rationale and the conservation invariant it verifies before
# writing anything. Redesigned twice more the same day: `text unwrap`/a
# `text paste` sibling command briefly became a single `dior reflow` with a
# freeform `<file>|-` argument, then settled as the two-subcommand group
# below (`reflow file` / `reflow text`) -- a fixed MODE word for each source
# matches this CLI's own stated grammar ("bare word = MODE, --flag =
# combinable") better than an auto-detected positional does, and reads
# unambiguously without needing `-` to mean two different things depending
# on whether stdin happens to be a pipe.
#
# WHY `reflow text` READS THE CLIPBOARD, NEVER A LITERAL ARGUMENT
# ---------------------------------------------------------------------------
# There is deliberately no `--paste <text>` flag that takes pasted content as
# a literal argument VALUE. Real prose routinely contains characters a shell
# treats specially -- quotes, backticks, `$`, `!`, backslashes -- and any of
# those inside a `--paste "..."` value can terminate the string early,
# trigger command substitution, or expand a variable/history reference
# before `dior` ever sees the text. That is a correctness bug waiting to
# happen on ordinary input, not an edge case. `reflow text` instead reads
# the clipboard directly via `pbpaste` straight into a file: the document's
# bytes never pass through shell argument parsing or quoting at all, and
# pbpaste's output never touches the terminal's own line discipline either --
# both were candidate failure modes for a long document and this sidesteps
# both at once. Need to feed it text from a script instead of the clipboard?
# `echo "$text" | dior reflow text --stdin` -- the shell's own redirection
# handles that safely, with none of the quoting hazard `--paste` would have.
# `--stdin` is required explicitly rather than auto-detected: a non-tty
# stdin that is neither a real pipe nor ever sends EOF (measured 2026-09-06
# in a non-interactive automation context) makes a `[ -t 0 ]`-style guess
# hang forever instead of falling back to the clipboard, so this never
# guesses -- no `--stdin` always means the clipboard, which cannot hang.
# ==============================================================================

# ------------------------------------------------------------------------------
# Shared engine runner -- one call site for invoking scripts/reflow-prose.mjs
# so every destination (file, --out, --copy) reports a failure identically.
# Prints "⚠️ Failed:" + the script's stderr and returns 1 on failure; on
# success, echoes the script's machine-readable "inputLines outputLines
# changed" line for the caller to parse. NOT used for the plain-stdout
# destination -- see the comment at that call site for why.
# ------------------------------------------------------------------------------
_dior_reflow_run() {
    local input="$1" output="$2" result
    result="$(node "$DIOR_CLI_DIR/scripts/reflow-prose.mjs" "$input" "$output" 2>&1)"
    if [ $? -ne 0 ]; then
        echo "${DIOR_C_ERROR}⚠️  Failed:${DIOR_C_RESET}"
        echo "$result"
        return 1
    fi
    echo "$result"
}

# Finds the next available "<base>_reflowed[_N].<ext>" path in $1, so
# re-running reflow on the same input never clobbers a previous run's output.
_dior_reflow_next_name() {
    local dir="$1" base="$2" ext="$3" n=1 candidate
    while true; do
        if [ "$n" -eq 1 ]; then
            candidate="$dir/${base}_reflowed.${ext}"
        else
            candidate="$dir/${base}_reflowed_${n}.${ext}"
        fi
        [ -e "$candidate" ] || { echo "$candidate"; return; }
        n=$((n + 1))
    done
}

# ------------------------------------------------------------------------------
# dior reflow file — reflow a file on disk
# ------------------------------------------------------------------------------
_dior_reflow_file() {
    shift 2
    local input="" outdir="" out_given=0 overwrite=0 copy=0
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
            --overwrite|-w) overwrite=1 ;;
            --copy|-c) copy=1 ;;
            --help|-h) dior help reflow file; return ;;
            -*) _dior_bad_opt "reflow file" "$1"; return 1 ;;
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
        dior help reflow file
        return 1
    fi
    if [ ! -f "$input" ]; then
        echo "${DIOR_C_ERROR}⚠️  No such file: ${DIOR_C_ARG}$input${DIOR_C_RESET}"
        return 1
    fi
    if [ "$out_given" -eq 1 ] && [ "$overwrite" -eq 1 ]; then
        echo "${DIOR_C_ERROR}⚠️  --out and --overwrite are mutually exclusive${DIOR_C_RESET}"
        return 1
    fi
    if ! command -v node >/dev/null 2>&1; then
        echo "${DIOR_C_ERROR}⚠️  node isn't on PATH -- required to run the reflow engine${DIOR_C_RESET}"
        return 1
    fi

    local output
    if [ "$overwrite" -eq 1 ]; then
        output="$(cd "$(dirname "$input")" && pwd)/$(basename "$input")" || return 1
    else
        local dir base ext
        if [ "$out_given" -eq 1 ]; then dir="$outdir"; else dir="$(dirname "$input")"; fi
        mkdir -p "$dir" || return 1
        dir="$(cd "$dir" && pwd)" || return 1
        base="${input:t:r}"    # zsh modifiers: :t = tail (basename), :r = remove extension
        ext="${input:e}"       # :e = extension, without the dot
        [ -z "$ext" ] && ext="md"
        output="$(_dior_reflow_next_name "$dir" "$base" "$ext")"
    fi

    local result
    result="$(_dior_reflow_run "$input" "$output")"
    if [ $? -ne 0 ]; then
        echo "$result"
        return 1
    fi

    local in_lines out_lines changed
    read -r in_lines out_lines changed <<< "$result"
    if [ "$overwrite" -eq 1 ]; then
        if [ "$changed" = "0" ]; then
            echo "${DIOR_C_DIM}No hard-wrapped lines found -- left as-is${DIOR_C_RESET}"
        else
            echo "${DIOR_C_HEAD}Fixed in place:${DIOR_C_RESET} ${DIOR_C_ARG}$output${DIOR_C_RESET} ${DIOR_C_DIM}($in_lines -> $out_lines lines)${DIOR_C_RESET}"
        fi
    else
        echo "${DIOR_C_HEAD}Fixed:${DIOR_C_RESET} ${DIOR_C_ARG}$input${DIOR_C_RESET} ${DIOR_C_DIM}($in_lines lines)${DIOR_C_RESET} -> ${DIOR_C_ARG}$output${DIOR_C_RESET} ${DIOR_C_DIM}($out_lines lines)${DIOR_C_RESET}"
    fi
    if [ "$copy" -eq 1 ]; then
        if command -v pbcopy >/dev/null 2>&1; then
            pbcopy < "$output"
            echo "${DIOR_C_DIM}(also copied to the clipboard)${DIOR_C_RESET}"
        else
            echo "${DIOR_C_ERROR}⚠️  pbcopy isn't on PATH -- couldn't also copy to the clipboard${DIOR_C_RESET}"
        fi
    fi
}
_dior_register "reflow file" "Reflow ${DIOR_C_ARG}<path>${DIOR_C_RESET} ${DIOR_C_OPT}[--out <dir>|--overwrite] [--copy]${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}📄 REFLOW A FILE${DIOR_C_RESET} ${DIOR_C_DIM}— dior reflow file${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Rejoins prose that got hard-wrapped at a fixed column width (every visual line
is a real newline, not a soft wrap) back into flowing paragraphs. Headings,
lists (rejoined per-item), fenced/indented code blocks, blockquotes, tables,
thematic breaks, HTML lines, YAML front matter, and genuine Markdown hard
breaks (2+ trailing spaces, or a trailing backslash) are all left alone.

${DIOR_C_HEAD}USAGE${DIOR_C_RESET}
  ${DIOR_C_CMD}dior reflow file${DIOR_C_RESET} ${DIOR_C_ARG}<path>${DIOR_C_RESET}                 ${DIOR_C_DIM}-> writes <name>_reflowed.<ext> beside it${DIOR_C_RESET}
  ${DIOR_C_CMD}dior reflow file${DIOR_C_RESET} ${DIOR_C_ARG}<path>${DIOR_C_RESET} ${DIOR_C_OPT}--out <dir>${DIOR_C_RESET}   ${DIOR_C_DIM}-> writes it there instead${DIOR_C_RESET}
  ${DIOR_C_CMD}dior reflow file${DIOR_C_RESET} ${DIOR_C_ARG}<path>${DIOR_C_RESET} ${DIOR_C_OPT}-o <dir>${DIOR_C_RESET}      ${DIOR_C_DIM}-> same, short form${DIOR_C_RESET}
  ${DIOR_C_CMD}dior reflow file${DIOR_C_RESET} ${DIOR_C_ARG}<path>${DIOR_C_RESET} ${DIOR_C_OPT}--overwrite${DIOR_C_RESET}   ${DIOR_C_DIM}-> overwrites <path> itself, no copy${DIOR_C_RESET}
  ${DIOR_C_CMD}dior reflow file${DIOR_C_RESET} ${DIOR_C_ARG}<path>${DIOR_C_RESET} ${DIOR_C_OPT}-w${DIOR_C_RESET}            ${DIOR_C_DIM}-> same, short form${DIOR_C_RESET}
  ${DIOR_C_CMD}dior reflow file${DIOR_C_RESET} ${DIOR_C_ARG}<path>${DIOR_C_RESET} ${DIOR_C_OPT}--copy${DIOR_C_RESET}        ${DIOR_C_DIM}-> also copies the result to the clipboard${DIOR_C_RESET}

Without ${DIOR_C_OPT}--overwrite${DIOR_C_RESET}, the original file is never modified -- the fixed copy is
always a new file, and re-running never clobbers a previous result: a taken
${DIOR_C_ARG}name_reflowed.ext${DIOR_C_RESET} becomes ${DIOR_C_ARG}name_reflowed_2.ext${DIOR_C_RESET}, then ${DIOR_C_ARG}_3${DIOR_C_RESET}, and so on.
${DIOR_C_OPT}--overwrite${DIOR_C_RESET} and ${DIOR_C_OPT}--out${DIOR_C_RESET} are mutually exclusive; ${DIOR_C_OPT}--copy${DIOR_C_RESET} combines with either."

# ------------------------------------------------------------------------------
# dior reflow text — reflow the clipboard's contents (or piped stdin, with
# --stdin). The whole body runs inside a zsh `{ } always { }` block, zsh's
# native equivalent of bash's `trap ... RETURN` (which zsh doesn't have --
# its trap builtin only takes real signals plus EXIT/ZERR) -- an `always`
# block's cleanup clause runs no matter how the try-block leaves, `return`
# included, so temp-file cleanup lives in exactly one place regardless of
# which branch below returns.
# ------------------------------------------------------------------------------
_dior_reflow_text() {
    shift 2
    local outdir="" out_given=0 copy=0 use_stdin=0
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
            --copy|-c) copy=1 ;;
            --stdin) use_stdin=1 ;;
            --help|-h) dior help reflow text; return ;;
            *) _dior_bad_opt "reflow text" "$1"; return 1 ;;
        esac
        shift
    done

    if ! command -v node >/dev/null 2>&1; then
        echo "${DIOR_C_ERROR}⚠️  node isn't on PATH -- required to run the reflow engine${DIOR_C_RESET}"
        return 1
    fi

    local -a tmp_files
    tmp_files=()
    {
        # Deliberately NOT auto-detected via `[ -t 0 ]`: measured 2026-09-06
        # that a non-interactive context can leave stdin neither a tty nor a
        # pipe that ever sends EOF, so guessing "not a tty -> read stdin"
        # hangs forever instead of falling back to the clipboard. --stdin is
        # required to read fd 0 at all; without it this always reads the
        # clipboard, which cannot hang -- pbpaste returns immediately
        # regardless of the caller's stdin.
        local node_input
        if [ "$use_stdin" -eq 1 ]; then
            node_input="-"
        else
            if ! command -v pbpaste >/dev/null 2>&1; then
                echo "${DIOR_C_ERROR}⚠️  pbpaste isn't on PATH -- reading the clipboard needs macOS${DIOR_C_RESET}"
                return 1
            fi
            local tmp_in
            tmp_in="$(mktemp "${TMPDIR:-/tmp}/dior-reflow-in.XXXXXX")" || return 1
            tmp_files+=("$tmp_in")
            pbpaste > "$tmp_in"
            if [ ! -s "$tmp_in" ]; then
                echo "${DIOR_C_DIM}Clipboard is empty -- nothing to reflow${DIOR_C_RESET}"
                return 1
            fi
            node_input="$tmp_in"
        fi

        if [ "$out_given" -eq 1 ]; then
            mkdir -p "$outdir" || return 1
            local dir
            dir="$(cd "$outdir" && pwd)" || return 1
            local output
            output="$(_dior_reflow_next_name "$dir" "pasted" "md")"
            local result
            result="$(_dior_reflow_run "$node_input" "$output")"
            if [ $? -ne 0 ]; then
                echo "$result"
                return 1
            fi
            local in_lines out_lines changed
            read -r in_lines out_lines changed <<< "$result"
            echo "${DIOR_C_HEAD}Fixed:${DIOR_C_RESET} ${DIOR_C_DIM}($in_lines lines)${DIOR_C_RESET} -> ${DIOR_C_ARG}$output${DIOR_C_RESET} ${DIOR_C_DIM}($out_lines lines)${DIOR_C_RESET}"
            if [ "$copy" -eq 1 ]; then
                if command -v pbcopy >/dev/null 2>&1; then
                    pbcopy < "$output"
                    echo "${DIOR_C_DIM}(also copied to the clipboard)${DIOR_C_RESET}"
                else
                    echo "${DIOR_C_ERROR}⚠️  pbcopy isn't on PATH -- couldn't also copy to the clipboard${DIOR_C_RESET}"
                fi
            fi
            return 0
        fi

        if [ "$copy" -eq 1 ]; then
            if ! command -v pbcopy >/dev/null 2>&1; then
                echo "${DIOR_C_ERROR}⚠️  pbcopy isn't on PATH -- copying to the clipboard needs macOS${DIOR_C_RESET}"
                return 1
            fi
            local tmp_out
            tmp_out="$(mktemp "${TMPDIR:-/tmp}/dior-reflow-out.XXXXXX")" || return 1
            tmp_files+=("$tmp_out")
            local result
            result="$(_dior_reflow_run "$node_input" "$tmp_out")"
            if [ $? -ne 0 ]; then
                echo "$result"
                return 1
            fi
            pbcopy < "$tmp_out"
            local in_lines out_lines changed
            read -r in_lines out_lines changed <<< "$result"
            echo "${DIOR_C_HEAD}Fixed${DIOR_C_RESET} ${DIOR_C_DIM}($in_lines -> $out_lines lines) -- copied to the clipboard, ready to paste${DIOR_C_RESET}"
            return 0
        fi

        # Plain: stream the reflowed text straight to stdout, byte for byte
        # -- no decoration mixed in, so `dior reflow text | pbcopy` (or any
        # other pipe) gets exactly the reflowed text. Bypasses
        # _dior_reflow_run on purpose: that helper captures through $(...),
        # which strips trailing newlines and would buffer the whole document
        # instead of streaming it.
        node "$DIOR_CLI_DIR/scripts/reflow-prose.mjs" "$node_input" -
    } always {
        rm -f "${tmp_files[@]}"
    }
}
_dior_register "reflow text" "Reflow the clipboard ${DIOR_C_OPT}[--out <dir>] [--copy] [--stdin]${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}📋 REFLOW PASTED TEXT${DIOR_C_RESET} ${DIOR_C_DIM}— dior reflow text${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Same engine as ${DIOR_C_CMD}dior reflow file${DIOR_C_RESET}, sourced from the clipboard instead of a file
on disk. There is no flag that takes the text as a literal argument -- see
this command's own file (reflow.zsh) for why that would be unsafe for
ordinary prose. Reading via ${DIOR_C_CMD}pbpaste${DIOR_C_RESET} also means a long document never
touches the terminal's own line discipline the way pasting into an open
stdin prompt can.

${DIOR_C_HEAD}USAGE${DIOR_C_RESET}
  ${DIOR_C_CMD}dior reflow text${DIOR_C_RESET}                     ${DIOR_C_DIM}-> reflows the clipboard, prints the result to the terminal${DIOR_C_RESET}
  ${DIOR_C_CMD}dior reflow text${DIOR_C_RESET} ${DIOR_C_OPT}--out <dir>${DIOR_C_RESET}         ${DIOR_C_DIM}-> writes pasted_reflowed.md there instead of printing${DIOR_C_RESET}
  ${DIOR_C_CMD}dior reflow text${DIOR_C_RESET} ${DIOR_C_OPT}--copy${DIOR_C_RESET}              ${DIOR_C_DIM}-> copies the result to the clipboard instead of printing${DIOR_C_RESET}
  ${DIOR_C_CMD}echo \"...\" | dior reflow text${DIOR_C_RESET} ${DIOR_C_OPT}--stdin${DIOR_C_RESET}  ${DIOR_C_DIM}-> reflows piped stdin instead of the clipboard${DIOR_C_RESET}

${DIOR_C_OPT}--stdin${DIOR_C_RESET} is required to read a pipe at all -- without it, ${DIOR_C_CMD}dior reflow text${DIOR_C_RESET} always
reads the clipboard, even with something piped in. That's deliberate: this
command never guesses whether stdin is a real pipe or nothing at all, since
guessing wrong the other way means blocking forever waiting for input that's
never coming.

${DIOR_C_OPT}--out${DIOR_C_RESET} and ${DIOR_C_OPT}--copy${DIOR_C_RESET} combine (writes the file AND copies it). With neither, the
reflowed text prints to stdout plainly, so it composes with a pipe too:
${DIOR_C_CMD}dior reflow text${DIOR_C_RESET} ${DIOR_C_OPT}| pbcopy${DIOR_C_RESET} does the same thing as ${DIOR_C_OPT}--copy${DIOR_C_RESET} by hand."
