#!/bin/bash

# Copyright (c) 2024 Cumulocity GmbH

# Note: This script updates a cookiecutter template located in a 'cookiecutter'
# sub directory. There is a corresponding GitHub project which can/should be
# added as a sub module: https://github.com/chisou/cookiecutter-cumulocity-python-ms

cwd="$(pwd)"

src="$cwd"
dst="$cwd/cookiecutter/{{cookiecutter.project_slug}}"

function error {
  echo "$1" >&2
  exit 1
}

# (1) copy source files
echo "Copying source files ..."
cp -v "$src/requirements"*.txt "$dst" | exit 1
cp -v "$src/"*.py "$dst" | exit 1
cp -v "$src/build.sh" "$dst" | exit 1
cp -v -r "$src/src" "$dst" | exit 1
