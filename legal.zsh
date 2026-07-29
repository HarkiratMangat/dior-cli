# ==============================================================================
# ⚖️  LEGAL PAGES — build, deploy, and check the hosted Terms/Privacy site
# ==============================================================================
#
# Added 2026-07-29 18:24 EDT, when the legal set (LICENSE / NOTICE / ToS / Privacy)
# shipped in Diors-Builds v2.43.0 and got a public home on Cloudflare Pages.
#
# WHY THIS GROUP EXISTS AT ALL. Discord REQUIRES the Terms and Privacy URLs to be
# publicly reachable and linked in the Developer Portal. That makes this site a
# live dependency of the bot's listing, not a nice-to-have — so "is it up?" and
# "does the deployed copy still match the Markdown?" need to be one command each,
# not a sequence someone has to remember.
#
# THE ONE INVARIANT WORTH PROTECTING. docs/legal/*.md is the legally operative
# source; public/legal/*.html is generated from it. If those drift, the project is
# publishing a privacy policy that contradicts its own source of truth at two
# different URLs — worse than having none. So `deploy` ALWAYS rebuilds first and
# refuses to upload if the build's own verifier fails, and `check` compares live
# bytes against the local build rather than just asking for a 200.
#
# NO CREDENTIAL LIVES HERE. wrangler holds its own OAuth token (from
# `wrangler login`), revocable from the Cloudflare dashboard. A Cloudflare secret
# must never reach the bot's .env — that file is the bot's RUNTIME environment and
# the bot never makes a Cloudflare call. Same mistake GEMINI_API_KEY already made.

DIOR_LEGAL_PROJECT="diors-builds-legal"
DIOR_LEGAL_HOST="https://diors-builds-legal.pages.dev"

# Cloudflare Pages serves extensionless canonical URLs and 308-redirects the
# .html form. These are the redirect TARGETS, so they are what belongs in the
# Discord Developer Portal — pasting the .html form costs every visitor a
# redirect hop for no reason. Verified live 2026-07-29 18:24 EDT.
DIOR_LEGAL_TERMS_URL="$DIOR_LEGAL_HOST/legal/terms"
DIOR_LEGAL_PRIVACY_URL="$DIOR_LEGAL_HOST/legal/privacy"

# ------------------------------------------------------------------------------
# dior legal build — regenerate the HTML from the Markdown
# ------------------------------------------------------------------------------
_dior_legal_build() {
    cd "$DIOR_BOT_DIR" || return 1
    echo "${DIOR_C_HEAD}Rebuilding legal pages from docs/legal/*.md${DIOR_C_RESET}"
    node scripts/buildLegalPages.js
}

# ------------------------------------------------------------------------------
# dior legal deploy — build, then push to Cloudflare Pages
# ------------------------------------------------------------------------------
_dior_legal_deploy() {
    shift 2
    local skip_confirm=0
    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes) skip_confirm=1 ;;
            *) _dior_bad_option "legal deploy" "$1"; return 1 ;;
        esac
        shift
    done

    cd "$DIOR_BOT_DIR" || return 1

    # Build FIRST and bail on failure. The build self-verifies (every multi-word
    # run of source must survive into the HTML, and every internal link must
    # resolve), so a non-zero exit here means the output is not publishable.
    # Deploying anyway would put a known-incomplete legal document online.
    echo "${DIOR_C_HEAD}1/2  Rebuilding${DIOR_C_RESET}"
    if ! node scripts/buildLegalPages.js; then
        echo "${DIOR_C_WARN}⚠️  Build failed its own verification — NOT deploying.${DIOR_C_RESET}"
        echo "   Fix the findings above. The live site is untouched."
        return 1
    fi

    if [ "$skip_confirm" -eq 0 ]; then
        echo ""
        echo "${DIOR_C_DIM}This publishes to $DIOR_LEGAL_HOST — a public site Discord links to.${DIOR_C_RESET}"
        _dior_confirm "Deploy the legal pages to Cloudflare?" || { echo "Cancelled."; return 1; }
    fi

    echo ""
    echo "${DIOR_C_HEAD}2/2  Deploying to Cloudflare Pages${DIOR_C_RESET}"
    npx wrangler pages deploy public \
        --project-name="$DIOR_LEGAL_PROJECT" \
        --branch main \
        --commit-dirty=true || return 1

    echo ""
    echo "${DIOR_C_DIM}Verifying the live site matches what was just built...${DIOR_C_RESET}"
    sleep 5
    _dior_legal_check check
}

# ------------------------------------------------------------------------------
# dior legal check — is it up, and does it match the local build?
# ------------------------------------------------------------------------------
_dior_legal_check() {
    cd "$DIOR_BOT_DIR" || return 1

    # A real browser UA. Cloudflare 403s some automated agents, which would
    # otherwise read as "the site is down" when it is perfectly healthy — that
    # exact false alarm cost real time on 2026-07-29 18:24 EDT.
    local ua="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36"
    local drift=0 down=0 f local_sum live_sum code tmp
    tmp=$(mktemp)

    echo "${DIOR_C_TITLE}⚖️  LEGAL SITE${DIOR_C_RESET} ${DIOR_C_DIM}— $DIOR_LEGAL_HOST${DIOR_C_RESET}"
    echo ""

    for f in legal/terms.html legal/privacy.html legal/index.html LICENSE NOTICE; do
        # -L is REQUIRED: Pages 308-redirects the .html form to its extensionless
        # canonical URL, and without -L every check returns 0 bytes and every
        # comparison "fails". That produced a completely false drift report once.
        code=$(curl -s -L --compressed -A "$ua" -o "$tmp" -w '%{http_code}' "$DIOR_LEGAL_HOST/$f")

        if [ "$code" != "200" ]; then
            printf "  ${DIOR_C_WARN}%-6s${DIOR_C_RESET} %s ${DIOR_C_DIM}(HTTP %s)${DIOR_C_RESET}\n" "DOWN" "$f" "$code"
            down=$((down + 1))
            continue
        fi

        if [ ! -f "public/$f" ]; then
            printf "  ${DIOR_C_WARN}%-6s${DIOR_C_RESET} %s ${DIOR_C_DIM}(live, but no local copy to compare)${DIOR_C_RESET}\n" "?" "$f"
            continue
        fi

        local_sum=$(shasum -a 256 "public/$f" | cut -d' ' -f1)
        live_sum=$(shasum -a 256 "$tmp" | cut -d' ' -f1)

        if [ "$local_sum" = "$live_sum" ]; then
            printf "  ${DIOR_C_OK}%-6s${DIOR_C_RESET} %s\n" "OK" "$f"
        else
            printf "  ${DIOR_C_WARN}%-6s${DIOR_C_RESET} %s ${DIOR_C_DIM}(live copy differs from local build)${DIOR_C_RESET}\n" "DRIFT" "$f"
            drift=$((drift + 1))
        fi
    done

    rm -f "$tmp"
    echo ""

    if [ "$down" -gt 0 ]; then
        echo "${DIOR_C_WARN}⚠️  $down file(s) not serving. Discord requires these URLs to be reachable.${DIOR_C_RESET}"
        echo "   ${DIOR_C_DIM}Run 'dior legal deploy' to republish.${DIOR_C_RESET}"
        return 1
    fi

    if [ "$drift" -gt 0 ]; then
        # Drift means the Markdown was edited and the site was never republished —
        # so the live legal documents are stale. That is the failure this command
        # exists to catch, and it is the same "merged never meant deployed" trap
        # the bot's own DEPLOY panel was built for.
        echo "${DIOR_C_WARN}⚠️  $drift file(s) DRIFTED — the live site is behind your local build.${DIOR_C_RESET}"
        echo "   ${DIOR_C_DIM}Someone edited docs/legal/*.md without redeploying. Run 'dior legal deploy'.${DIOR_C_RESET}"
        return 1
    fi

    echo "${DIOR_C_OK}✅ Live site is up and byte-identical to your local build.${DIOR_C_RESET}"
    echo ""
    echo "${DIOR_C_HEAD}Discord Developer Portal URLs${DIOR_C_RESET} ${DIOR_C_DIM}(canonical — no redirect hop)${DIOR_C_RESET}"
    printf "  ${DIOR_C_DIM}Terms of Service URL${DIOR_C_RESET}  ${DIOR_C_CMD}%s${DIOR_C_RESET}\n" "$DIOR_LEGAL_TERMS_URL"
    printf "  ${DIOR_C_DIM}Privacy Policy URL${DIOR_C_RESET}    ${DIOR_C_CMD}%s${DIOR_C_RESET}\n" "$DIOR_LEGAL_PRIVACY_URL"
}

# ------------------------------------------------------------------------------
# dior legal open — open the live pages in a browser
# ------------------------------------------------------------------------------
_dior_legal_open() {
    echo "Opening the live legal pages..."
    open "$DIOR_LEGAL_TERMS_URL"
    open "$DIOR_LEGAL_PRIVACY_URL"
}

_dior_register "legal deploy" "Rebuild the legal pages and publish to Cloudflare ${DIOR_C_OPT}[-y]${DIOR_C_RESET}" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}⚖️  PUBLISH LEGAL PAGES${DIOR_C_RESET} ${DIOR_C_DIM}— dior legal deploy${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Rebuilds public/legal/*.html from docs/legal/*.md, then publishes to Cloudflare
Pages. Ends by verifying the live site byte-for-byte against what it just built.

${DIOR_C_HEAD}USAGE:${DIOR_C_RESET}
$(printf "  ${DIOR_C_CMD}%s${DIOR_C_RESET} ${DIOR_C_OPT}%-6s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "dior legal deploy" "" "Build, confirm, deploy, then verify" \
    "dior legal deploy" "-y" "Skip the confirmation prompt")

${DIOR_C_HEAD}WHY IT BUILDS FIRST:${DIOR_C_RESET}
  The Markdown is the legally operative source; the HTML is generated. If the two
  drift, the site publishes a privacy policy that contradicts its own source at a
  public URL. So the build runs every time, and ${DIOR_C_WARN}if the build fails its own
  verification nothing is uploaded${DIOR_C_RESET} ${DIOR_C_DIM}(it checks that all source text survived
  rendering AND that every internal link resolves)${DIOR_C_RESET}.

${DIOR_C_HEAD}CREDENTIALS:${DIOR_C_RESET}
  Uses wrangler's own OAuth login ${DIOR_C_DIM}(revocable from the Cloudflare dashboard)${DIOR_C_RESET}.
  ${DIOR_C_WARN}No Cloudflare token belongs in the bot's .env${DIOR_C_RESET} ${DIOR_C_DIM}— that is the bot's runtime
  environment and the bot never calls Cloudflare.${DIOR_C_RESET}"

_dior_register "legal check" "Is the legal site up, and does it match your local build?" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}⚖️  LEGAL SITE STATUS${DIOR_C_RESET} ${DIOR_C_DIM}— dior legal check${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Fetches every published file and compares it against your local build.

${DIOR_C_HEAD}WHAT EACH RESULT MEANS:${DIOR_C_RESET}
$(printf "  ${DIOR_C_OK}%-6s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" "OK" "Live and byte-identical to your local build")
$(printf "  ${DIOR_C_WARN}%-6s${DIOR_C_RESET} ${DIOR_C_DIM}->${DIOR_C_RESET} %s\n" \
    "DRIFT" "Live, but STALE -- the .md was edited and never republished" \
    "DOWN" "Not serving. Discord REQUIRES these URLs to be reachable")

${DIOR_C_HEAD}WHY BYTES AND NOT JUST A 200:${DIOR_C_RESET}
  A 200 only proves something is there, not that it is the CURRENT document. The
  failure that actually happens is silent staleness ${DIOR_C_DIM}(the same 'merged never
  meant deployed' trap the bot's own DEPLOY panel exists for)${DIOR_C_RESET}.
  Prints the canonical Discord Portal URLs on success."

_dior_register "legal build" "Regenerate the legal HTML from the Markdown, no deploy" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}⚖️  BUILD LEGAL PAGES${DIOR_C_RESET} ${DIOR_C_DIM}— dior legal build${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Runs scripts/buildLegalPages.js and stops. Nothing is published.

Use this to preview changes locally after editing docs/legal/*.md. The build
verifies its own output and exits non-zero if content went missing or an internal
link broke. ${DIOR_C_DIM}Open public/legal/index.html in a browser to look at the result.${DIOR_C_RESET}

${DIOR_C_DIM}To publish, use 'dior legal deploy' -- which runs this build itself, so you
never have to remember to do both.${DIOR_C_RESET}"

_dior_register "legal open" "Open the live Terms and Privacy pages in a browser" \
"${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
${DIOR_C_TITLE}⚖️  OPEN LEGAL PAGES${DIOR_C_RESET} ${DIOR_C_DIM}— dior legal open${DIOR_C_RESET}
${DIOR_C_TITLE}========================================================${DIOR_C_RESET}
Opens both live pages in your default browser -- the canonical extensionless
URLs, the same ones that belong in the Discord Developer Portal."
