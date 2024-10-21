#!/bin/bash

$cwd="$(pwd)"

src="$cwd/template"
dst="$cwd/cookiecutter/{{cookiecutter.project_slug}}"

function error {
  echo "$1" >&2
  exit 1
}


# (1) copy source files
echo "Copying source files ..."
cp -v "$src/requirements*.txt" "$dst" | exit 1
cp -v "$src/*.py" "$dst" | exit 1
cp -v "$src/*.md" "$dst" | exit 1
cp -v "$src/*.sh" "$dst" | exit 1
cp -v -r "$src/src" "$dst/src" | exit 1

# (2) update template files

#

  {% if cookiecutter.entrypoint == 'Multi-Tenant Microservice' -%}"isolation": "MULTI_TENANT",
  {% elif cookiecutter.entrypoint == 'Single-Tenant Microservice' -%}"isolation": "PER_TENANT",{% endif -%}





requirements.txt
requirements-dev.txt

tasks.py
microservice_util.py

build.sh
src/c8y_ms