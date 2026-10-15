#!/usr/bin/env bash
# Turns the template into a new project. Run via `just init`; it removes
# itself (with the whole .template folder) when done.
set -eu

read -p "Microservice name [$(basename "$PWD")]: " name
name="${name:-$(basename "$PWD")}"
read -p "Provider (your company): " provider
read -p "Short description: " description

# every src/main/*.py except main.py is an example; its first line describes it
echo "Available examples:"
examples=()
for f in src/main/*.py; do
    example="$(basename "$f" .py)"
    [ "$example" = "main" ] && continue
    examples+=("$example")
    printf '  %-20s %s\n' "$example" "$(head -1 "$f" | sed 's/^# *//')"
done
read -p "Example to start from [${examples[0]}]: " example
example="${example:-${examples[0]}}"
[ -f "src/main/$example.py" ] || { echo "Unknown example: $example" >&2; exit 1; }

read -p "Isolation? [MULTI_TENANT/PER_TENANT]: " isolation
isolation="${isolation:-MULTI_TENANT}"
read -p "License? [ASL2/MIT/BSD3/GPL3]: " license
license="${license:-ASL2}"

case "$license" in
    MIT)  classifier="MIT License" ;;
    BSD3) classifier="BSD License" ;;
    GPL3) classifier="GNU General Public License v3 (GPLv3)" ;;
    *)    classifier="Apache Software License" ;;
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

# project metadata
sed -i.bak \
    -e "s|^name = .*|name = \"$name\"|" \
    -e "s|^description = .*|description = \"$description\"|" \
    -e "s|^authors = .*|authors = [{name=\"$provider\"}]|" \
    -e "s|\"License :: .*\"|\"License :: OSI Approved :: $classifier\"|" \
    pyproject.toml
rm pyproject.toml.bak

# LICENSE, README, CHANGELOG
sed -e "s|{YEAR}|$(date +%Y)|" \
    -e "s|{PROVIDER}|$provider|" \
    -e "s|{DESCRIPTION}|$description|" \
    ".template/licenses/$license" > LICENSE

sed -e "s|{NAME}|$name|" \
    -e "s|{DESCRIPTION}|$description|" \
    .template/README.md > README.md

printf '# Changelog\n\n## [Unreleased]\n\n- Project created from the cumulocity-python-ms template.\n' > CHANGELOG.md

rm -r .template

echo "Done. Check the [project.urls] in pyproject.toml, then commit."
