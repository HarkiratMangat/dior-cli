# ==============================================================================
# 📄 TEXT — small standalone text utilities, unrelated to the bot itself
# ==============================================================================
#
# Added 2026-08-03 21:24 EDT. First command: `text unwrap`, a CLI port of the
# MarkEdit extension `markedit-dior-unwrap.js` (the "Hard-Break Fixer") -- LLM
# output (Claude especially) sometimes hard-wraps prose at a fixed column width,
# where every visual line is a real "\n", not a soft wrap. This rejoins those
# into flowing paragraphs while leaving headings/lists/code fences/blockquotes/
# tables/front matter alone. See scripts/unwrap-hard-breaks.js for the actual
# join logic and why it's a separate file from the MarkEdit extension's copy.

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
            -*) _dior_bad_opt "text unwrap" "$1"; return 1 ;;
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
    if [ ! -f "$input" ]; then
        echo "${DIOR_C_ERROR}⚠️  No such file: ${DIOR_C_ARG}$input${DIOR_C_RESET}"
        return 1
    fi
    if [ "$in_place" -eq 1 ] && [ "$out_given" -eq 1 ]; then
        echo "${DIOR_C_ERROR}⚠️  --in-place and --out are mutually exclusive -- in-place always writes back to the input file itself${DIOR_C_RESET}"
        return 1
    fi
    if ! command -v node >/dev/null 2>&1; then
        echo "${DIOR_C_ERROR}⚠️  node isn't on PATH -- required to run the unwrap script${DIOR_C_RESET}"
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

        local base="${input:t:r}"    # zsh modifiers: :t = tail (basename), :r = remove extension
        local ext="${input:e}"       # :e = extension, without the dot
        [ -z "$ext" ] && ext="md"
        output="$outdir/${base}-unwrapped.${ext}"
    fi

    local result
    if ! result="$(node "$DIOR_CLI_DIR/scripts/unwrap-hard-breaks.js" "$input" "$output" 2>&1)"; then
        echo "${DIOR_C_ERROR}⚠️  Failed:${DIOR_C_RESET}"
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
        echo "${DIOR_C_HEAD}Fixed:${DIOR_C_RESET} ${DIOR_C_ARG}$input${DIOR_C_RESET} ${DIOR_C_DIM}($in_lines lines)${DIOR_C_RESET} -> ${DIOR_C_ARG}$output${DIOR_C_RESET} ${DIOR_C_DIM}($out_lines lines)${DIOR_C_RESET}"
    fi
}
_dior_register "text unwrap" "Rejoin LLM-style hard-wrapped lines in ${DIOR_C_ARG}<file>${DIOR_C_RESET} ${DIOR_C_OPT}[--out <dir>|--in-place]${DIOR_C_RESET}" \
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

Without ${DIOR_C_OPT}--in-place${DIOR_C_RESET}, the original file is never modified -- the fixed copy is always a
new file. ${DIOR_C_OPT}--in-place${DIOR_C_RESET} and ${DIOR_C_OPT}--out${DIOR_C_RESET} are mutually exclusive."
