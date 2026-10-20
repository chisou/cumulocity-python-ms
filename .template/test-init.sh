#!/usr/bin/env bash
# Tests `just init` without touching this repository.
#
# Copies the template into a temporary folder (all files git knows about,
# including uncommitted changes, but nothing ignored such as .venv or .env),
# runs `just init` there with fixed values and checks the generated project.
# Finally checks that a second `just init` is refused.
#
# On success, prints "OK (example, isolation, license)" and removes the
# temporary folder. On failure, prints which check failed, keeps the folder for
# inspection and exits with 1.
#
# Only checks the files `init` writes; it doesn't check whether the generated
# microservice actually runs.
#
# This is a template-only file; `just init` removes it with .template/.
set -eu

usage() {
    cat <<EOF
Usage: .template/test-init.sh [options]

Runs \`just init\` on a temporary copy of the template and checks the result.

Options:
  -e, --example <example>          Example to test, a folder name in src/app
                                   (default: advanced)
  -i, --isolation <isolation>      MULTI_TENANT or PER_TENANT (default: MULTI_TENANT)
  -l, --license <license>          ASL2, MIT, BSD3 or GPL3 (default: ASL2)
  -I, --interactive                Let \`just init\` ask you for every value not given as
                                   option, to see what users see. Checks nothing and keeps
                                   the generated project.
  -h, --help                       Show this help

Examples:
  .template/test-init.sh
  .template/test-init.sh -e simple_tenant -i PER_TENANT -l MIT
  .template/test-init.sh --interactive
  for e in advanced multi_tenant multi_tenant_n20 simple_tenant; do .template/test-init.sh -e \$e; done
EOF
}

example=""
isolation=""
license=""
interactive=false

# fails unless option $1 has a value $2
assert_arg() { [[ -n "${2:-}" && "$2" != -* ]] || { echo "Parameter $1 needs an argument." >&2; exit 2; }; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)        usage; exit 0 ;;
    -I|--interactive) interactive=true; shift ;;
    -e|--example)     assert_arg "$@"; example="$2";   shift 2 ;;
    -i|--isolation)   assert_arg "$@"; isolation="$2"; shift 2 ;;
    -l|--license)     assert_arg "$@"; license="$2";   shift 2 ;;
    *) echo "Unknown parameter: $1" >&2; usage; exit 2 ;;
  esac
done

# copy the template like GitHub would, but including uncommitted changes
cd "$(dirname "$0")/.."
template="$(pwd)"
dir="$(mktemp -d)"
# (files deleted but not yet committed are still known to git, but can't be copied)
git ls-files -co --exclude-standard | while IFS= read -r f; do [ -e "$f" ] && echo "$f"; done \
    | tar -cf - -T - | tar -xf - -C "$dir"
cd "$dir"

if $interactive; then
    # pass on only the given options, `just init` asks for the rest
    [ -n "$example" ] && set -- "$@" --example "$example"
    [ -n "$isolation" ] && set -- "$@" --isolation "$isolation"
    [ -n "$license" ] && set -- "$@" --license "$license"
    just init "$@"
    echo
    echo "Generated project in $dir:"
    ls -A "$dir"
    exit 0
fi

example="${example:-advanced}"
isolation="${isolation:-MULTI_TENANT}"
license="${license:-ASL2}"

fail() {
    echo "FAILED ($example, $isolation, $license): $1 (see $dir)" >&2
    exit 1
}

# values with characters that are special to sed (\ | &) and TOML (\ ")
provider='ACME & Sons | "Best" \ Co'
description='R&D tools | for "things" \ more'

# invalid values must be rejected before anything is changed
for bad_name in "My-Service" "my_service" "my service" "a-name-longer-than-23-chars"; do
    # all other values are valid, so the name is the only reason to fail
    just init --name "$bad_name" --provider "$provider" --description "$description" \
        --example "$example" --isolation "$isolation" --license "$license" \
        < /dev/null > /dev/null 2>&1 && fail "invalid name '$bad_name' was accepted"
done
[ -d .template ] && [ "$(cat MICROSERVICE_NAME)" = "$(cat "$template/MICROSERVICE_NAME")" ] \
    || fail "files were changed although the name was invalid"

# all values given, so `just init` must not ask; no input makes it fail if it does
just init \
    --name test-ms \
    --provider "$provider" \
    --description "$description" \
    --example "$example" \
    --isolation "$isolation" \
    --license "$license" \
    < /dev/null > /dev/null || fail "just init failed"

[ -e .template ] && fail ".template still exists"
[ -f src/app/main.py ] || fail "src/app/main.py missing"
[ -z "$(find src/app -mindepth 1 -maxdepth 1 -name README.md)" ] || fail "example README.md was not removed"
for other in "$template"/src/app/*/; do
    other="$(basename "$other")"
    [ "$other" = "__pycache__" ] || [ "$other" = "$example" ] || [ ! -e "src/app/$other" ] \
        || fail "example $other was not removed"
done
[ ! -e "src/app/$example" ] || fail "example folder was not flattened"
sed "s/app\.$example\([. ]\)/app\1/g" "$template/src/app/$example/main.py" | cmp -s - src/app/main.py \
    || fail "main.py is not the main.py of $example"
grep -rq "app\.$example" src/app && fail "imports still name the example"
# the project must import without the template (needs the template's .venv)
if [ -x "$template/.venv/bin/python" ]; then
    (cd src && "$template/.venv/bin/python" -c "import app.main") > /dev/null 2>&1 \
        || fail "src/app/main.py can't be imported"
fi
[ "$(cat MICROSERVICE_NAME)" = "test-ms" ] || fail "MICROSERVICE_NAME not set"
[ "$(cat PROVIDER)" = "$provider" ] || fail "PROVIDER not set"
[ "$(cat ISOLATION)" = "$isolation" ] || fail "ISOLATION should be $isolation"
python3 - "$provider" "$description" 2> /dev/null <<'EOF' || fail "pyproject.toml invalid or values not set"
import sys, tomllib
project = tomllib.load(open("pyproject.toml", "rb"))["project"]
assert project["name"] == "test-ms"
assert project["authors"][0]["name"] == sys.argv[1]
assert project["description"] == sys.argv[2]
EOF
uv lock --check --quiet 2> /dev/null || fail "uv.lock is out of date"
grep -qF -- "$provider" LICENSE || fail "LICENSE has no provider"
grep -qF -- "$description" README.md || fail "README.md has no description"
grep -q '{NAME}\|{YEAR}\|{PROVIDER}\|{DESCRIPTION}' README.md LICENSE && fail "placeholders left"
[ -f CHANGELOG.md ] || fail "CHANGELOG.md missing"
just init 2> /dev/null && fail "second run was not refused"

rm -rf "$dir"
echo "OK ($example, $isolation, $license)"
