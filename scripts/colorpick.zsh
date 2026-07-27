#!/usr/bin/env zsh
# ==============================================================================
# dior colour picker
# ==============================================================================
# Tracked in scripts/. Prints only; changes nothing -- it never edits core.zsh.
#
# LIST MODE -- one line per colour, the whole line in that colour:
#   zsh scripts/colorpick.zsh                 every colour, 1-255
#   zsh scripts/colorpick.zsh 117 147 213     only these
#   zsh scripts/colorpick.zsh 100-160         a range
#   zsh scripts/colorpick.zsh 75 100-130 213  ranges and singles together
#   zsh scripts/colorpick.zsh --16            just the 16 theme-defined system colours
#   zsh scripts/colorpick.zsh --grey          just the 24-step grey ramp (232-255)
#
# MIX MODE -- one composite line, a different colour per element:
#   zsh scripts/colorpick.zsh --mix mode=117 flag=117 arg=213
#   zsh scripts/colorpick.zsh --mix usage=141b cmd=2 arg=3 mode=117 flag=117 comment=244
#
#   Elements: usage cmd arg mode flag arrow desc comment
#   Values:   a 256-colour index 0-255, optionally suffixed
#               b = bold   (e.g. 141b)
#               d = dim    (e.g. 244d)
#   Anything you don't name keeps its CURRENT dior colour, so you only have to
#   type the pieces you're actually changing.
#
# Note 256-colour indices 0-15 ARE the system colours, so `cmd=2` is your
# theme's green and `mode=12` is the bright blue in use today -- there's no
# separate syntax needed for them.

reset=$'\e[0m'; dim=$'\e[2m'; bold=$'\e[1m'

# Builds an SGR sequence from a value like "117", "141b", "244d".
sgr() {
    local v="$1" pre=""
    case "$v" in
        *b) pre=$'\e[1m'; v="${v%b}" ;;
        *d) pre=$'\e[2m'; v="${v%d}" ;;
    esac
    print -n "${pre}"$'\e[38;5;'"${v}"'m'
}

# The one format line, rendered with a colour per element.
# $1 label  $2 usage  $3 cmd  $4 arg  $5 mode  $6 flag  $7 arrow  $8 desc  $9 comment
row() {
    printf "%s%-6s%s" "$dim" "$1" "$reset"
    printf "%sUSAGE:%s " "$2" "$reset"
    printf "%sdior%s "   "$3" "$reset"
    printf "%s<group> <command>%s " "$4" "$reset"
    printf "%s[mode|mode]%s "       "$5" "$reset"
    printf "%s[--flag|--flag]%s"    "$6" "$reset"
    printf "    %s->%s "            "$7" "$reset"
    printf "%sDescription%s "       "$8" "$reset"
    printf "%s(comment)%s\n"        "$9" "$reset"
}

# ------------------------------------------------------------------ mix mode
# Renders a full mock screen rather than one line, because a theme touching
# titles, dividers, help text and the two ⚠️ severities can't be judged from a
# single row. Prints BEFORE and AFTER so the comparison is direct.
ORDER=( title dividers usage cmd arg mode flag arrow desc help warning error comment )

mock() {
    # $1..$13 in ORDER order
    local t="$1" dv="$2" u="$3" c="$4" a="$5" m="$6" f="$7" ar="$8" d="$9" h="$10" w="$11" er="$12" cm="$13"
    local bar="========================================================"
    printf "%s%s%s\n" "$dv" "$bar" "$reset"
    printf "%s%s%s\n" "$t" "👑 DIOR TERMINAL CLI HUB" "$reset"
    printf "%s%s%s\n" "$dv" "$bar" "$reset"
    printf "%sUsage: %s%sdior <group> <command>%s %s[mode] [--flags]%s\n" "$d" "$reset" "$c" "$reset" "$m" "$reset"
    print ""
    printf "%s%s%s\n" "$u" "🤖 BOT COMMANDS:" "$reset"
    printf "  %s%-11s%s %s->%s %sRun the local dev bot%s %s[watch|nowatch|kill] [--list|--clear]%s\n" \
        "$c" "bot dev" "$reset" "$ar" "$reset" "$d" "$reset" "$m" "$reset"
    printf "  %s%-11s%s %s->%s %sDeploy or restart the live bot%s %s<deploy|restart>%s %s(confirms first)%s\n" \
        "$c" "bot vm" "$reset" "$ar" "$reset" "$d" "$reset" "$a" "$reset" "$cm" "$reset"
    print ""
    printf "%sUSAGE:%s  %sdior bot check%s %s[status|baseline]%s %s[--peaks] [--logs [N]]%s\n" \
        "$u" "$reset" "$c" "$reset" "$m" "$reset" "$f" "$reset"
    print ""
    printf "%s💡 NEED HELP?%s\n" "$h" "$reset"
    printf "  %sAdd%s %s--help%s %sor%s %s-h%s %sto any command%s %s(e.g. dior bot dev --help)%s\n" \
        "$h" "$reset" "$f" "$reset" "$h" "$reset" "$f" "$reset" "$h" "$reset" "$cm" "$reset"
    print ""
    printf "%s⚠️  '--clear' can't be combined with 'watch'%s\n" "$w" "$reset"
    printf "%s⚠️  'nope' isn't a valid option for 'dior bot dev'%s\n" "$er" "$reset"
    printf "%s%s%s\n" "$dv" "$bar" "$reset"
}

if [[ "$1" == "--mix" ]]; then
    shift
    # defaults = the palette as it stands today
    typeset -A e cur
    cur=( title $'\e[1;36m' dividers $'\e[1;36m' usage $'\e[1;35m' cmd $'\e[32m'
          arg $'\e[33m' mode $'\e[94m' flag $'\e[94m' arrow $'\e[2m' desc ""
          help "" warning $'\e[1;33m' error $'\e[1;33m' comment $'\e[2m' )
    for k in "${ORDER[@]}"; do e[$k]="${cur[$k]}"; done

    typeset -A given
    for a in "$@"; do
        [[ "$a" != *=* ]] && { print "  ignoring '$a' -- expected element=value"; continue }
        k="${a%%=*}"; v="${a#*=}"
        if [[ -z "${cur[$k]+x}" ]]; then
            print "  unknown element '$k' -- valid: ${ORDER[*]}"
            continue
        fi
        # `current` keeps whatever that element uses today
        if [[ "$v" == "current" ]]; then
            e[$k]="${cur[$k]}"; given[$k]="current"
        else
            e[$k]="$(sgr "$v")"; given[$k]="$v"
        fi
    done

    print ""
    print "${bold}BEFORE${reset} ${dim}(palette as it ships today)${reset}"
    print ""
    mock "${cur[title]}" "${cur[dividers]}" "${cur[usage]}" "${cur[cmd]}" "${cur[arg]}" \
         "${cur[mode]}" "${cur[flag]}" "${cur[arrow]}" "${cur[desc]}" "${cur[help]}" \
         "${cur[warning]}" "${cur[error]}" "${cur[comment]}"
    print ""
    print "${bold}AFTER${reset}"
    print ""
    mock "${e[title]}" "${e[dividers]}" "${e[usage]}" "${e[cmd]}" "${e[arg]}" \
         "${e[mode]}" "${e[flag]}" "${e[arrow]}" "${e[desc]}" "${e[help]}" \
         "${e[warning]}" "${e[error]}" "${e[comment]}"
    print ""
    if (( ${#given} )); then
        print "${dim}assigned:${reset}"
        for k in "${ORDER[@]}"; do
            [[ -n "${given[$k]}" ]] && printf "  %s%-9s%s %s\n" "${e[$k]}" "$k" "$reset" "${dim}${given[$k]}${reset}"
        done
        print ""
    fi
    exit 0
fi

# ----------------------------------------------------------------- list mode
typeset -a codes
if [[ "$1" == "--16" ]]; then
    codes=( {0..15} )
elif [[ "$1" == "--grey" ]]; then
    codes=( {232..255} )
elif (( $# == 0 )); then
    codes=( {1..255} )
else
    for a in "$@"; do
        case "$a" in
            <->-<->) codes+=( {${a%%-*}..${a##*-}} ) ;;   # a range like 100-160
            <->)     codes+=( "$a" ) ;;                    # a single index
            *)       print "  ignoring '$a' -- expected a number, a range (100-160), --16, --grey or --mix" ;;
        esac
    done
fi

print ""
print "${dim}current (94):${reset}"
row "94" $'\e[1;35m' $'\e[32m' $'\e[33m' $'\e[94m' $'\e[94m' $'\e[2m' "" $'\e[2m'
print ""
for c in "${codes[@]}"; do
    C="$(sgr "$c")"
    # USAGE: stays bold, as it is in the real guides -- everything else takes
    # the flat candidate colour so you can judge it on each element type.
    row "$c" "${bold}${C}" "$C" "$C" "$C" "$C" "$C" "$C" "$C"
done
print ""
print "${dim}narrow down:  colorpick.zsh 100-160        mix elements:  colorpick.zsh --mix mode=117 arg=213${reset}"
print ""
