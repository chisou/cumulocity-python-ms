#!/usr/bin/env bash
# Tests `just init` without touching this repository.
#
# Copies the template into a temporary folder (all files git knows about,
# including uncommitted changes, but nothing ignored such as .venv or .env),
# runs `just init` there with fixed answers and checks the generated project.
# Finally checks that a second `just init` is refused.
#
# Usage (from anywhere):
#   .template/test-init.sh [example] [MULTI_TENANT|PER_TENANT] [ASL2|MIT|BSD3|GPL3]
#
# The example is a file name in src/main without .py, e.g. simple_tenant.
# Defaults are multi_tenant, MULTI_TENANT and ASL2. To test all examples:
#   for e in multi_tenant simple_tenant; do .template/test-init.sh $e; done
#
# To see what users see, run it interactively. You answer the questions
# yourself; nothing is checked, and the generated project is kept:
#   .template/test-init.sh -i
#
# On success, prints "OK (example, isolation, license)" and removes the temporary folder.
# On failure, prints which check failed, keeps the folder for inspection and
# exits with 1.
#
# Note: only checks the files `init` writes; it doesn't check whether the
# generated microservice actually runs.
#
# This is a template-only file; `just init` removes it with .template/.
set -eu

interactive=false
if [ "${1:-}" = "-i" ]; then
    interactive=true
    shift
fi

example="${1:-multi_tenant}"
isolation="${2:-MULTI_TENANT}"
license="${3:-ASL2}"
dir="$(mktemp -d)"

fail() {
    echo "FAILED ($example, $isolation, $license): $1 (see $dir)" >&2
    exit 1
}

# copy the template like GitHub would, but including uncommitted changes
cd "$(dirname "$0")/.."
template="$(pwd)"
git ls-files -co --exclude-standard | tar -cf - -T - | tar -xf - -C "$dir"
cd "$dir"

if $interactive; then
    just init
    echo
    echo "Generated project in $dir:"
    ls -A "$dir"
    exit 0
fi

printf 'test-ms\nACME Corp\nA test\n%s\n%s\n%s\n' "$example" "$isolation" "$license" | just init > /dev/null

[ -e .template ] && fail ".template still exists"
[ "$(ls src/main/*.py)" = "src/main/main.py" ] || fail "src/main should only contain main.py"
cmp -s src/main/main.py "$template/src/main/$example.py" || fail "main.py is not $example.py"
[ "$(cat MICROSERVICE_NAME)" = "test-ms" ] || fail "MICROSERVICE_NAME not set"
[ "$(cat ISOLATION)" = "$isolation" ] || fail "ISOLATION should be $isolation"
grep -q '^name = "test-ms"' pyproject.toml || fail "pyproject.toml name not set"
grep -q 'ACME Corp' LICENSE || fail "LICENSE has no provider"
grep -q '{NAME}\|{YEAR}\|{PROVIDER}\|{DESCRIPTION}' README.md LICENSE && fail "placeholders left"
[ -f CHANGELOG.md ] || fail "CHANGELOG.md missing"
just init 2> /dev/null && fail "second run was not refused"

rm -rf "$dir"
echo "OK ($example, $isolation, $license)"
