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
  -e, --example <example>          Example to start from, a file name in src/main without .py
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

# every src/main/*.py except main.py is an example; its first line describes it
examples=()
for f in src/main/*.py; do
    [ "$(basename "$f" .py)" = "main" ] || examples+=("$(basename "$f" .py)")
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
    echo "${cc}Available examples:${nc}"
    for e in "${examples[@]}"; do
        printf "  ${cy}%-20s${nc} %s\n" "$e" "$(head -1 "src/main/$e.py" | sed 's/^# *//')"
    done
    read -p "${cc}Example to start from [${examples[0]}]:${nc} " example
    example="${example:-${examples[0]}}"
fi
[ -f "src/main/$example.py" ] && [ "$example" != "main" ] || { echo "${cr}Unknown example: $example${nc}" >&2; exit 2; }

if [ -z "$isolation" ]; then
    read -p "${cc}Isolation? [MULTI_TENANT/PER_TENANT]:${nc} " isolation
    isolation="${isolation:-MULTI_TENANT}"
fi
case "$isolation" in
    MULTI_TENANT|PER_TENANT) ;;
    *) echo "${cr}Unknown isolation: $isolation${nc}" >&2; exit 2 ;;
esac

if [ -z "$license" ]; then
    read -p "${cc}License? [ASL2/MIT/BSD3/GPL3]:${nc} " license
    license="${license:-ASL2}"
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

# entrypoint: chosen example becomes main.py, the others go
mv "src/main/$example.py" src/main/main.py
for other in "${examples[@]}"; do
    [ "$other" = "$example" ] || rm "src/main/$other.py"
done

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
