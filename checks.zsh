# ==============================================================================
# 🔍 CHECKS — thin wrappers around Diors-Builds' own verification scripts
# ==============================================================================
#
# Added 2026-08-03 23:37 EDT. Both of these already exist as real scripts in
# the bot repo (docs-audit.mjs, checkEmojiCaptures.js) -- these commands exist
# purely so they're reachable without `cd`-ing into the repo first, matching
# the same "check the dior CLI before writing a new script" principle that
# motivated the legal-build consolidation (meta-deferred-list.md,
# 2026-08-01 22:20 EDT). Neither wrapper re-implements any logic of its own.

# ------------------------------------------------------------------------------
# dior docs audit — the documentation-consistency gate (also a CI check)
# ------------------------------------------------------------------------------
_dior_docs_audit() {
    cd "$DIOR_BOT_DIR" || return 1
    npm run docs:audit
}
_dior_register "docs audit" "Run the documentation-consistency audit (also a CI gate)" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}🔍 DOCS AUDIT${DIOR_C_RESET} ${DIOR_C_DIM}— dior docs audit${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Runs \`npm run docs:audit\` (scripts/docs-audit.mjs) from Diors-Builds -- checks
the doc map, cross-references, version coverage across all three changelogs,
the changelog hash-chain, the DEVLOG table of contents, tag integrity, record
structure, and the conservation rule (an item leaves an active list only by
appearing in its archive).

${DIOR_C_DIM}ERROR fails the run; WARN never blocks. Also runs as a CI gate on every PR --
this is the same check, just reachable without cd-ing into the repo first.${DIOR_C_RESET}
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"

# ------------------------------------------------------------------------------
# dior emoji check — catch emojis frozen at require() time
# ------------------------------------------------------------------------------
_dior_emoji_check() {
    cd "$DIOR_BOT_DIR" || return 1
    node scripts/checkEmojiCaptures.js
}
_dior_register "emoji check" "Catch emoji ids frozen at require() time instead of render time" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}😀 EMOJI CAPTURE CHECK${DIOR_C_RESET} ${DIOR_C_DIM}— dior emoji check${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Runs scripts/checkEmojiCaptures.js -- proxies emojiMap and records every
string-valued emoji read that happens while each command module LOADS. A
module-level const or object literal that reads an emoji at require() time
keeps the pre-sync PROD id forever, which renders as broken text on the dev
bot (a different Discord application). A clean run reads nothing.

${DIOR_C_DIM}Run this after adding a new module-level emoji reference, or when the dev
bot shows a broken-emoji glyph where a real one should render.${DIOR_C_RESET}
${DIOR_C_FOOT}========================================================${DIOR_C_RESET}"
