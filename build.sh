#!/bin/bash
# Copyright (c) 2024 Cumulocity GmbH

name=""
version=""
isolation=""
provider=""

while [[ $# -gt 0 ]]; do
  # options
  case "$1" in
    -h|--help)
      echo "Usage: build.sh -n <name> -v <version> -i <isolation> -p <provider>"
      exit 0
      ;;
  esac
  # arguments
  if [[ -z "$2" || "$2" == -* ]]; then
    echo "Parameter $1 needs an argument."
    exit 2
  fi
  case "$1" in
    -n|--name)
      name="$2"
      shift 2
      ;;
    -v|--version)
      version="$2"
      shift 2
      ;;
    -i|--isolation)
      isolation="$2"
      shift 2
      ;;
    -p|--provider)
      provider="$2"
      shift 2
      ;;
  esac
done


if [ -z "$name" ]; then
  echo "Missing name parameter (-n/--name)."
  exit 2
fi

if [ -z "$version" ]; then
  echo "Missing version parameter (-v/--version)."
  exit 2
fi

if [ -z "$isolation" ]; then
  echo "Missing isolation parameter (-i/--isolation)."
  exit 2
fi

if [ -z "$provider" ]; then
  echo "Missing provider parameter (-p/--provider)."
  exit 2
fi

architecture=$(uname -m)
img_name=`echo "$name" | tr '[:upper:]' '[:lower:]' | tr '[:punct:]' '-'`

build_dir="./build"
dist_dir="./dist"
target="$dist_dir/$img_name.zip"

echo "Name: $name, Image Name: $img_name, Version: $version, Isolation: $isolation, Provider: $provider"
echo "Build directory:    $build_dir"
echo "Target location:    $target"
echo "Host Architecture:  $architecture"
echo ""

if ! [[ -d "src" ]]; then
  echo "This script must be run from the project base directory."
  exit 2
fi

# prepare directories
[[ -d "$build_dir" ]] && rm -rf "$build_dir"
mkdir -p "$build_dir"
[[ -d "$dist_dir" ]] && rm -rf "$dist_dir"
mkdir -p "$dist_dir"

# copy & render sources
cp ./requirements-ms.txt "$build_dir/requirements.txt"
cp -r src/main "$build_dir"
cp ./src/cumulocity.json "$build_dir/cumulocity.json"
cp ./src/Dockerfile "$build_dir/Dockerfile"
sed -i -e "s/{VERSION}/$version/g" "$build_dir/cumulocity.json"
sed -i -e "s/{ISOLATION}/$isolation/g" "$build_dir/cumulocity.json"
sed -i -e "s/{PROVIDER}/$provider/g" "$build_dir/cumulocity.json"

# build image
echo "Building image (amd64) ..."
#export DOCKER_DEFAULT_PLATFORM=linux/amd64
#docker build -t "$name" "$build_dir"
docker buildx build --platform linux/amd64 -t "$name" "$build_dir"
docker save -o "$dist_dir/image.tar" "$name"
zip -j "$dist_dir/$img_name.zip" "$build_dir/cumulocity.json" "$dist_dir/image.tar"

echo ""
echo "Created uploadable archive: $target"