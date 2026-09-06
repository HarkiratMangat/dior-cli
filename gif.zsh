# ==============================================================================
# 🎞️  GIF — background removal, resizing and format conversion for animated art
# ==============================================================================
#
# Added 2026-09-03 15:46 EDT. A front end for the `gif-background-remover` skill
# that lives in its own repo (DIOR_GIF_DIR, set in core.zsh) and is also uploaded
# standalone to claude.ai.
#
# WHY A FRONT END AND NOT JUST AN ALIAS
# -------------------------------------
# The skill's script exposes 64 flags. That count is NOT the friction it looks
# like: `--auto` already runs the skill's own `--recommend`, applies its flags,
# renders, re-measures and re-renders once, so the happy path never touches the
# other 63. The friction is that `--auto` deliberately REFUSES two questions it
# will not guess at, and delivers them as prose naming hex colours and bounding
# boxes -- "is the region at bbox [412,180,470,238] outlined in f0c850 interior
# design, or background showing through?". Measured across 304 real assets, that
# fires on 12.8% of them. Nobody can answer it from text; they have to SEE it.
#
# So this is an INTERVIEW, not a flag surface. scripts/gif_wizard.py reads those
# questions out of `--recommend`'s JSON BEFORE anything runs, opens a picture of
# the disputed area, asks in plain English, and then calls `--auto` with the
# answers already supplied so it never refuses. Zero changes to the skill: its
# JSON is already a machine-readable question API.
#
# THE ONE RULE THIS FILE EXISTS TO PROTECT
# ----------------------------------------
# The skill's own docs are emphatic that GUESSING a size target is its single
# worst measured failure -- a guessed target produces a real file at a real size
# and nothing downstream says the number was invented. So `--to` defaults to
# nothing, the default preset is full quality with no compression flags at all,
# and a size cap only ever comes from the person asking for one. When the output
# is large, the CLI names the size and OFFERS. Offering is not acting.
#
# GRAMMAR: bare word = mode (clean/check/presets, pick one), --flag = combinable,
# same as everywhere else in this CLI. `dior gif` bare prints the guide rather
# than picking a mode, because `clean` writes files.

# Everything below shells out to one Python script; the CLI half owns the
# surface (menu, guides, tab-completion, argument validation) and the Python half
# owns the engine (analysis, the questions, rendering, verification). Same split
# as `reflow` -> scripts/reflow-prose.mjs, which is the established
# pattern here rather than a new one.
_dior_gif_run() {
    local mode="$1"; shift
    if ! command -v python3 >/dev/null 2>&1; then
        echo "${DIOR_C_ERROR}⚠️  python3 isn't on PATH -- required to run the gif tools${DIOR_C_RESET}"
        return 1
    fi
    # Export the palette so the Python half prints in the same colours as the rest
    # of the CLI instead of inventing a second visual system. core.zsh already
    # blanks these when stdout isn't a tty, and the script re-checks isatty itself,
    # so a piped run stays escape-code free either way.
    DIOR_C_RESET="$DIOR_C_RESET" DIOR_C_TITLE="$DIOR_C_TITLE" DIOR_C_FOOT="$DIOR_C_FOOT" \
    DIOR_C_HEAD="$DIOR_C_HEAD" DIOR_C_CMD="$DIOR_C_CMD" DIOR_C_ARG="$DIOR_C_ARG" \
    DIOR_C_OPT="$DIOR_C_OPT" DIOR_C_HELP="$DIOR_C_HELP" DIOR_C_WARN="$DIOR_C_WARN" \
    DIOR_C_ERROR="$DIOR_C_ERROR" DIOR_C_OK="$DIOR_C_OK" DIOR_C_DIM="$DIOR_C_DIM" \
    DIOR_GIF_DIR="$DIOR_GIF_DIR" \
        python3 "$DIOR_CLI_DIR/scripts/gif_wizard.py" "$mode" "$@"
}

# ------------------------------------------------------------------------------
# dior gif clean — remove the background, asking only what the file actually raises
# ------------------------------------------------------------------------------
_dior_gif_clean() {
    shift 2
    local -a files pass
    while [ $# -gt 0 ]; do
        case "$1" in
            --to)
                if [ -z "$2" ]; then
                    echo "${DIOR_C_ERROR}⚠️  --to needs a preset name ${DIOR_C_RESET}${DIOR_C_DIM}(try 'dior gif presets')${DIOR_C_RESET}"
                    return 1
                fi
                pass+=(--to "$2"); shift ;;
            --out|-o)
                if [ -z "$2" ]; then
                    echo "${DIOR_C_ERROR}⚠️  --out needs a directory argument${DIOR_C_RESET}"
                    return 1
                fi
                pass+=(--out "$2"); shift ;;
            --yes|-y)     pass+=(--yes) ;;
            --no-preview) pass+=(--no-preview) ;;
            --help|-h)    dior help gif clean; return ;;
            -*)           _dior_bad_opt "gif clean" "$1"; return 1 ;;
            *)            files+=("$1") ;;
        esac
        shift
    done

    if [ ${#files} -eq 0 ]; then
        dior help gif clean
        return 1
    fi
    local f
    for f in "${files[@]}"; do
        if [ ! -f "$f" ]; then
            echo "${DIOR_C_ERROR}⚠️  No such file: ${DIOR_C_ARG}$f${DIOR_C_RESET}"
            return 1
        fi
    done

    _dior_gif_run clean "${files[@]}" "${pass[@]}"
}
_dior_register "gif clean" "Remove the background from ${DIOR_C_ARG}<file>${DIOR_C_RESET} ${DIOR_C_OPT}[--to <preset>] [--out <dir>] [--yes]${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}🎞️  BACKGROUND REMOVER${DIOR_C_RESET} ${DIOR_C_DIM}— dior gif clean${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Makes the background of an animated image see-through, keeping the parts of the
design that happen to be the same colour ${DIOR_C_DIM}(a white highlight inside a white-backed
badge, an eye, a label)${DIOR_C_RESET}. Works on GIF, WebP, AVIF, APNG and plain PNG/JPEG.

You don't pick any settings. It looks at the file, works out everything it can,
and asks you only about the things it genuinely cannot tell -- showing you a
picture of the spot in question rather than describing it.

${DIOR_C_HEAD}USAGE${DIOR_C_RESET}
  ${DIOR_C_CMD}dior gif clean${DIOR_C_RESET} ${DIOR_C_ARG}<file>${DIOR_C_RESET}                   ${DIOR_C_DIM}-> asks what it needs, writes <name>_transparent.<ext> beside it${DIOR_C_RESET}
  ${DIOR_C_CMD}dior gif clean${DIOR_C_RESET} ${DIOR_C_ARG}<file...>${DIOR_C_RESET}                ${DIOR_C_DIM}-> several files, one after another${DIOR_C_RESET}
  ${DIOR_C_CMD}dior gif clean${DIOR_C_RESET} ${DIOR_C_ARG}<file>${DIOR_C_RESET} ${DIOR_C_OPT}--to <preset>${DIOR_C_RESET}     ${DIOR_C_DIM}-> skip the 'what's this for' question ('dior gif presets')${DIOR_C_RESET}
  ${DIOR_C_CMD}dior gif clean${DIOR_C_RESET} ${DIOR_C_ARG}<file>${DIOR_C_RESET} ${DIOR_C_OPT}--out <dir>${DIOR_C_RESET}       ${DIOR_C_DIM}-> write the result there instead of beside the original${DIOR_C_RESET}
  ${DIOR_C_CMD}dior gif clean${DIOR_C_RESET} ${DIOR_C_ARG}<file>${DIOR_C_RESET} ${DIOR_C_OPT}--yes${DIOR_C_RESET}             ${DIOR_C_DIM}-> ask nothing; prints every assumption it made${DIOR_C_RESET}
  ${DIOR_C_CMD}dior gif clean${DIOR_C_RESET} ${DIOR_C_ARG}<file>${DIOR_C_RESET} ${DIOR_C_OPT}--no-preview${DIOR_C_RESET}      ${DIOR_C_DIM}-> don't open any picture windows${DIOR_C_RESET}

${DIOR_C_HEAD}WHAT IT MIGHT ASK YOU${DIOR_C_RESET}
  ${DIOR_C_CMD}a hole in the artwork${DIOR_C_RESET}   ${DIOR_C_DIM}-> opens a picture with the spot boxed in pink; you say whether${DIOR_C_RESET}
                          ${DIOR_C_DIM}   it should be see-through or stay filled in${DIOR_C_RESET}
  ${DIOR_C_CMD}a soft fade or glow${DIOR_C_RESET}     ${DIOR_C_DIM}-> opens that frame; you say whether the glow is part of the picture${DIOR_C_RESET}
  ${DIOR_C_CMD}what it's for${DIOR_C_RESET}           ${DIOR_C_DIM}-> best quality, a Discord emoji, a size cap ('dior gif presets')${DIOR_C_RESET}

It only asks about the first two when the file actually raises them ${DIOR_C_DIM}(measured at
about 1 file in 8)${DIOR_C_RESET}. Everything else it works out on its own.

${DIOR_C_WARN}Nothing is ever shrunk unless you ask.${DIOR_C_RESET} The default keeps every frame, the
original timing and the full canvas. If the result is big, it says so and offers
${DIOR_C_DIM}-- guessing a size limit for you is how files quietly come out wrong.${DIOR_C_RESET}

An existing ${DIOR_C_ARG}<name>_transparent.<ext>${DIOR_C_RESET} is never overwritten -- the next run writes
${DIOR_C_ARG}_v2${DIOR_C_RESET}, then ${DIOR_C_ARG}_v3${DIOR_C_RESET}. After each file it checks its own work and says plainly what
it could and couldn't confirm."

# ------------------------------------------------------------------------------
# dior gif check — look, report, write nothing
# ------------------------------------------------------------------------------
_dior_gif_check() {
    shift 2
    local -a files pass
    while [ $# -gt 0 ]; do
        case "$1" in
            --why)     pass+=(--why) ;;
            --help|-h) dior help gif check; return ;;
            -*)        _dior_bad_opt "gif check" "$1"; return 1 ;;
            *)         files+=("$1") ;;
        esac
        shift
    done

    if [ ${#files} -eq 0 ]; then
        dior help gif check
        return 1
    fi
    local f
    for f in "${files[@]}"; do
        if [ ! -f "$f" ]; then
            echo "${DIOR_C_ERROR}⚠️  No such file: ${DIOR_C_ARG}$f${DIOR_C_RESET}"
            return 1
        fi
    done

    _dior_gif_run check "${files[@]}" "${pass[@]}"
}
_dior_register "gif check" "Say what ${DIOR_C_ARG}<file>${DIOR_C_RESET} needs, without writing anything ${DIOR_C_OPT}[--why]${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}🔍 LOOK BEFORE YOU CUT${DIOR_C_RESET} ${DIOR_C_DIM}— dior gif check${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Reads a file and reports what it found -- background colour, frame count, whether
the edges are soft or hard, which format the art actually needs, and whether it
will have any questions for you. Writes nothing at all.

Useful before a batch: run it over the whole set first and you'll know which
files need you present and which can be done with ${DIOR_C_OPT}--yes${DIOR_C_RESET}.

${DIOR_C_HEAD}USAGE${DIOR_C_RESET}
  ${DIOR_C_CMD}dior gif check${DIOR_C_RESET} ${DIOR_C_ARG}<file>${DIOR_C_RESET}          ${DIOR_C_DIM}-> a plain-English summary of that file${DIOR_C_RESET}
  ${DIOR_C_CMD}dior gif check${DIOR_C_RESET} ${DIOR_C_ARG}<file...>${DIOR_C_RESET}       ${DIOR_C_DIM}-> one summary per file${DIOR_C_RESET}
  ${DIOR_C_CMD}dior gif check${DIOR_C_RESET} ${DIOR_C_ARG}<file>${DIOR_C_RESET} ${DIOR_C_OPT}--why${DIOR_C_RESET}    ${DIOR_C_DIM}-> also print the tool's own reasoning, one line per finding${DIOR_C_RESET}

Reading a file takes a few seconds ${DIOR_C_DIM}(around 20 on a long, large one -- it walks every
frame)${DIOR_C_RESET}, so a big batch is worth starting and leaving."

# ------------------------------------------------------------------------------
# dior gif presets — the whole size/format vocabulary, in one screen
# ------------------------------------------------------------------------------
_dior_gif_presets() {
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
            --help|-h) dior help gif presets; return ;;
            *)         _dior_bad_opt "gif presets" "$1"; return 1 ;;
        esac
        shift
    done
    _dior_gif_run presets
}
_dior_register "gif presets" "List what you can ask for with ${DIOR_C_OPT}--to${DIOR_C_RESET} ${DIOR_C_DIM}(sizes, formats)${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}📦 WHAT YOU CAN ASK FOR${DIOR_C_RESET} ${DIOR_C_DIM}— dior gif presets${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Prints every value ${DIOR_C_OPT}--to${DIOR_C_RESET} accepts, with what each one actually means. These are
goals, not settings -- each one expands to a tested combination of the underlying
tool's flags, with the numbers taken from that tool's own measurements.

${DIOR_C_HEAD}USAGE${DIOR_C_RESET}
  ${DIOR_C_CMD}dior gif presets${DIOR_C_RESET}                            ${DIOR_C_DIM}-> the list${DIOR_C_RESET}
  ${DIOR_C_CMD}dior gif clean${DIOR_C_RESET} ${DIOR_C_ARG}<file>${DIOR_C_RESET} ${DIOR_C_OPT}--to <name>${DIOR_C_RESET}         ${DIOR_C_DIM}-> use one${DIOR_C_RESET}
  ${DIOR_C_CMD}dior gif clean${DIOR_C_RESET} ${DIOR_C_ARG}<file>${DIOR_C_RESET} ${DIOR_C_OPT}--to under-500kb${DIOR_C_RESET}    ${DIOR_C_DIM}-> any cap you name${DIOR_C_RESET}

Leave ${DIOR_C_OPT}--to${DIOR_C_RESET} off and you'll be asked, with best quality as the default. There is
deliberately no preset that guesses a limit from the look of the file."
