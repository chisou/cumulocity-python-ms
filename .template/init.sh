#!/usr/bin/env bash
# Turns the template into a new project. Run via `just init`; it removes
# itself (with the whole .template folder) when done.
set -eu

# --- colors (only on a terminal, and not if NO_COLOR is set) ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    cr=$'\033[0;31m'
    cg=$'\033[0;32m'
    cy=$'\033[1;33m'
    cc=$'\033[0;36m'
    nc=$'\033[0m'
else
    cr='' cg='' cy='' cc='' nc=''
fi

usage() {
    cat <<EOF
Usage: just init [options]

Turns this template into your own project. Asks for every value not given as option.

Options:
  -n, --name <name>                Microservice name, only a-z, 0-9 and -, at most
                                   23 characters (default: folder name)
  -p, --provider <provider>        Provider, i.e. your company
  -d, --description <text>         Short description
  -e, --example <example>          Example to start from, a folder name in src/app
  -i, --isolation <isolation>      MULTI_TENANT or PER_TENANT (default: MULTI_TENANT)
  -l, --license <license>          ASL2, MIT, BSD3 or GPL3 (default: ASL2)
  -h, --help                       Show this help
EOF
}

name=""
provider=""
description=""
example=""
isolation=""
license=""

# fails unless option $1 has a value $2
assert_arg() { [[ -n "${2:-}" && "$2" != -* ]] || { echo "${cr}Parameter $1 needs an argument.${nc}" >&2; exit 2; }; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)        usage; exit 0 ;;
    -n|--name)        assert_arg "$@"; name="$2";        shift 2 ;;
    -p|--provider)    assert_arg "$@"; provider="$2";    shift 2 ;;
    -d|--description) assert_arg "$@"; description="$2"; shift 2 ;;
    -e|--example)     assert_arg "$@"; example="$2";     shift 2 ;;
    -i|--isolation)   assert_arg "$@"; isolation="$2";   shift 2 ;;
    -l|--license)     assert_arg "$@"; license="$2";     shift 2 ;;
    *) echo "${cr}Unknown parameter: $1${nc}" >&2; usage; exit 2 ;;
  esac
done

# choose <prompt> <default> <item>...: lets the user pick one item, sets $choice.
# An item is "value" or "value|description". On a terminal, the user picks with
# up/down (or k/j) and Enter; without a capable terminal (e.g. in scripts) the value is typed.
choose() {
    local prompt="$1" default="$2"
    shift 2
    local items=("$@") n=$# selected=0 i value key rest

    if ! [ -t 0 ] || ! [ -t 1 ] || [ "${TERM:-dumb}" = "dumb" ]; then
        echo "${cc}${prompt}:${nc}"
        for item in "${items[@]}"; do
            printf "  ${cy}%-20s${nc} %s\n" "${item%%|*}" "${item#*|}"
        done
        read -p "${cc}${prompt} [$default]:${nc} " choice || true
        choice="${choice:-$default}"
        return
    fi

    for ((i = 0; i < n; i++)); do
        [ "${items[i]%%|*}" = "$default" ] && selected=$i
    done

    echo "${cc}${prompt}${nc} (up/down, Enter)"
    printf '\033[?25l'  # hide cursor, show it again when done or interrupted
    trap 'printf "\033[?25h\n"; exit 130' INT
    while true; do
        for ((i = 0; i < n; i++)); do
            value="${items[i]%%|*}"
            if [ "$i" -eq "$selected" ]; then
                printf "\033[2K  ${cy}> %-20s${nc} %s\n" "$value" "${items[i]#*|}"
            else
                printf "\033[2K    %-20s %s\n" "$value" "${items[i]#*|}"
            fi
        done
        IFS= read -rsn1 key || { printf '\033[?25h\n'; exit 130; }
        case "$key" in
            "")   break ;;  # Enter
            k)    [ "$selected" -gt 0 ] && selected=$((selected - 1)) ;;
            j)    [ "$selected" -lt $((n - 1)) ] && selected=$((selected + 1)) ;;
            $'\033')  # arrow keys arrive as ESC [ A / ESC [ B (or ESC O A / ESC O B in application mode)
                IFS= read -rsn2 rest || true
                case "$rest" in
                    "[A"|"OA") [ "$selected" -gt 0 ] && selected=$((selected - 1)) ;;
                    "[B"|"OB") [ "$selected" -lt $((n - 1)) ] && selected=$((selected + 1)) ;;
                esac ;;
        esac
        printf "\033[%dA" "$n"  # back to the first item for redrawing
    done
    trap - INT
    choice="${items[selected]%%|*}"

    # collapse the menu to the chosen value
    printf "\033[%dA\033[J\033[?25h" $((n + 1))
    echo "${cc}${prompt}:${nc} $choice"
}

# every folder in src/app with a main.py is an example; the first line of its
# README.md (without the leading "# ") describes it
examples=()
for d in src/app/*/; do
    [ -f "${d}main.py" ] && examples+=("$(basename "$d")")
done

# ask for everything not given as option, check each value before changing anything
if [ -z "$name" ]; then
    read -p "${cc}Microservice name [$(basename "$PWD")]:${nc} " name
    name="${name:-$(basename "$PWD")}"
fi
# Cumulocity's rule for microservice names
[[ "$name" =~ ^[a-z0-9-]{1,23}$ ]] || {
    echo "${cr}Invalid name: $name (only a-z, 0-9 and -, at most 23 characters)${nc}" >&2
    exit 2
}
[ -n "$provider" ] || read -p "${cc}Provider (your company):${nc} " provider
[ -n "$description" ] || read -p "${cc}Short description:${nc} " description
if [ -z "$example" ]; then
    items=()
    for e in "${examples[@]}"; do
        items+=("$e|$(head -n 1 "src/app/$e/README.md" | sed 's/^# *//')")
    done
    choose "Example to start from" multi_tenant "${items[@]}"
    example="$choice"
fi
[ -f "src/app/$example/main.py" ] || { echo "${cr}Unknown example: $example${nc}" >&2; exit 2; }

if [ -z "$isolation" ]; then
    choose "Isolation" MULTI_TENANT \
        "MULTI_TENANT|One instance serves all subscribed tenants" \
        "PER_TENANT|One instance per subscribed tenant"
    isolation="$choice"
fi
case "$isolation" in
    MULTI_TENANT|PER_TENANT) ;;
    *) echo "${cr}Unknown isolation: $isolation${nc}" >&2; exit 2 ;;
esac

if [ -z "$license" ]; then
    choose "License" ASL2 \
        "ASL2|Apache License 2.0" \
        "MIT|MIT License" \
        "BSD3|BSD 3-Clause License" \
        "GPL3|GNU General Public License v3"
    license="$choice"
fi
case "$license" in
    ASL2) classifier="Apache Software License" ;;
    MIT)  classifier="MIT License" ;;
    BSD3) classifier="BSD License" ;;
    GPL3) classifier="GNU General Public License v3 (GPLv3)" ;;
    *) echo "${cr}Unknown license: $license${nc}" >&2; exit 2 ;;
esac

# microservice settings
echo "$name" > MICROSERVICE_NAME
echo "$provider" > PROVIDER
echo "$isolation" > ISOLATION

# the chosen example becomes the app itself: its files move up into src/app
# (replacing main.py, which only selects an example), the others go
find src/app -name __pycache__ -prune -exec rm -r {} +
rm src/app/main.py
for other in "${examples[@]}"; do
    [ "$other" = "$example" ] || rm -r "src/app/$other"
done
mv -f "src/app/$example"/* src/app/
rmdir "src/app/$example"
rm src/app/README.md

# the example's imports name it (app.<example>.x), the project's don't (app.x)
find src/app -name '*.py' -exec sed -i.bak "s/app\.$example\([. ]\)/app\1/g" {} +
find src/app -name '*.bak' -delete

# user values go into sed replacements (where \, | and & are special) and
# into TOML strings (where \ and " are special), so they need escaping
sed_escape() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }
toml_escape() { printf '%s' "$1" | sed -e 's/[\\"]/\\&/g'; }

sed_name="$(sed_escape "$name")"
sed_provider="$(sed_escape "$provider")"
sed_description="$(sed_escape "$description")"
toml_name="$(sed_escape "$(toml_escape "$name")")"
toml_provider="$(sed_escape "$(toml_escape "$provider")")"
toml_description="$(sed_escape "$(toml_escape "$description")")"

# project metadata
sed -i.bak \
    -e "s|^name = .*|name = \"$toml_name\"|" \
    -e "s|^description = .*|description = \"$toml_description\"|" \
    -e "s|^authors = .*|authors = [{name=\"$toml_provider\"}]|" \
    -e "s|\"License :: .*\"|\"License :: OSI Approved :: $classifier\"|" \
    pyproject.toml
rm pyproject.toml.bak

# uv.lock records the project name too; `uv sync --locked` (Dockerfile) fails if it's outdated
uv lock --quiet

# LICENSE, README, CHANGELOG
sed -e "s|{YEAR}|$(date +%Y)|" \
    -e "s|{PROVIDER}|$sed_provider|" \
    -e "s|{DESCRIPTION}|$sed_description|" \
    ".template/licenses/$license" > LICENSE

sed -e "s|{NAME}|$sed_name|" \
    -e "s|{DESCRIPTION}|$sed_description|" \
    .template/README.md > README.md

printf '# Changelog\n\n## [Unreleased]\n\n- Project created from the cumulocity-python-ms template.\n' > CHANGELOG.md

rm -r .template

echo "${cg}Done.${nc} ${cy}Check the [project.urls] in pyproject.toml, then commit.${nc}"
