# ==============================================================================
# 🚀 DIOR MASTER CLI TOOL — loader
# ==============================================================================
#
# ~/.zshrc sources THIS file, and nothing else. Everything below it loads from
# ~/.config/dior/. Split out of ~/.zshrc on 2026-07-27 11:10 EDT, when the block had grown
# to 675 of that file's 723 lines (93%) with no version control and no backup --
# four rounds of restructuring had happened with no way to diff or roll back.
# The move was a pure relocation with zero behavior change, verified by diffing
# the complete rendered output of every menu, guide, and error path before and
# after. Startup cost was measured first and was NOT a reason to split: the whole
# block sources in ~10ms of a ~130ms shell start.
#
# ARCHITECTURE: every command is a small function named `_dior_<group>_<name>`
# (e.g. _dior_bot_status, _dior_update_brew), and its help text lives in exactly
# ONE place: the DIOR_HELP_SUMMARY / DIOR_HELP_DETAIL manifest in core.zsh,
# populated via _dior_register. `dior` itself just resolves "$1 $2" to a function
# name and calls it, or resolves "help $2 $3" to a manifest lookup. DISPLAY order
# (menu, tab-completion, "did you mean" lists) is driven separately by
# DIOR_MENU_ORDER -- an explicit, hand-curated list, not alphabetical -- so it
# groups commands by what they're actually for instead of by spelling.
#
# LOAD ORDER MATTERS, and only in one direction: core.zsh must come first.
# The guide text in bot.zsh/update.zsh is built at SOURCE time (the ${DIOR_C_*}
# color codes are expanded when _dior_register is called, not when the guide is
# printed), so both the color variables and _dior_register itself have to already
# exist. help.zsh's `compdef` also needs compinit, which ~/.zshrc runs earlier in
# its UV & PYTHON TOOLING SETUP section -- that's why the source line stays where
# the block used to be rather than moving to the end of ~/.zshrc.
#
# VISUAL DESIGN RULES (2026-07-27, after the help output kept drifting
# inconsistent across edits -- this is the actual fix, not another spot-patch):
#   1. "->" (dimmed) for every "here's a command, here's what it does" row --
#      dior's own commands, dior's own sub-options (nowatch/kill, list/clear,
#      brew/uv/etc). ":" is reserved for cases actively teaching an EXTERNAL
#      fixed syntax the user has to reproduce exactly (git's `type:` commit
#      prefixes, the literal quote characters) -- there, a colon matches the
#      real syntax being shown and an arrow would misrepresent it.
#   2. Every parenthetical aside/example is dimmed. No exceptions.
#   3. One column width per guide (not per sub-section) -- a guide's USAGE
#      table and its option descriptions are the SAME table, not two tables
#      that happen to sit near each other. Where a guide used to repeat the
#      same info twice at two different indents (e.g. bot dev's USAGE block
#      and its separate "WHAT EACH OPTION DOES" block), they're merged into
#      one row per option instead.
#   4. The top-level menu's command list and its "need help" tips are visually
#      DIFFERENT kinds of content (a reference table vs. usage instructions) --
#      so the tips are plain sentences now, not a second pseudo-table with its
#      own column width sitting right under the first one.
#
# HISTORY: this replaced an earlier version (Gemini-authored) where every
# command's logic AND its two help-text copies were three independent
# hand-written things kept in sync by hand -- adding one command meant editing
# three separate places. Rewritten 2026-07-26 23:09 EDT with Claude after that
# friction showed up while adding `bot commands`; extended 2026-07-27 08:17 EDT
# with group-scoped help, --help/-h, a "did you mean" suggester, ANSI color,
# workflow-ordered grouping, and tab-completion; redesigned 2026-07-27 08:45 EDT
# for the visual consistency rules above; relocated here 2026-07-27 11:10 EDT.

# Resolved from this file's own path rather than hardcoded, so the whole
# directory can be moved or symlinked (e.g. into a dotfiles repo) without
# editing anything. ${0:A:h} is zsh for "absolute path of this file, directory
# part" -- it works when sourced, unlike $0 alone.
DIOR_CLI_DIR="${0:A:h}"

# core.zsh first -- see LOAD ORDER above. The rest are independent of each other.
source "$DIOR_CLI_DIR/core.zsh"
source "$DIOR_CLI_DIR/help.zsh"
source "$DIOR_CLI_DIR/bot.zsh"
source "$DIOR_CLI_DIR/legal.zsh"
source "$DIOR_CLI_DIR/text.zsh"
source "$DIOR_CLI_DIR/workspace.zsh"
source "$DIOR_CLI_DIR/checks.zsh"
source "$DIOR_CLI_DIR/release.zsh"
source "$DIOR_CLI_DIR/update.zsh"
