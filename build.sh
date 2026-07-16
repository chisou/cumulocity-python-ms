#!/usr/bin/env bash
# Copyright (c) 2024 Cumulocity GmbH
set -euo pipefail

name=""
version=""
isolation=""
provider=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "Usage: build.sh -n <name> -v <version> -i <isolation> -p <provider>"
      exit 0
      ;;
  esac
  if [[ -z "${2:-}" || "$2" == -* ]]; then
    echo "Parameter $1 needs an argument."
    exit 2
  fi
  case "$1" in
    -n|--name)      name="$2";      shift 2 ;;
    -v|--version)   version="$2";   shift 2 ;;
    -i|--isolation) isolation="$2"; shift 2 ;;
    -p|--provider)  provider="$2";  shift 2 ;;
    *) echo "Unknown parameter: $1"; exit 2 ;;
  esac
done

[[ -z "$name" ]]      && { echo "Missing name parameter (-n/--name).";            exit 2; }
[[ -z "$version" ]]   && { echo "Missing version parameter (-v/--version).";      exit 2; }
[[ -z "$isolation" ]] && { echo "Missing isolation parameter (-i/--isolation).";  exit 2; }
[[ -z "$provider" ]]  && { echo "Missing provider parameter (-p/--provider).";    exit 2; }

# --- Target is ALWAYS linux/amd64 for Cumulocity; host may differ ---
target_platform="linux/amd64"

host_arch="$(uname -m)"
img_name="$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr '[:punct:]' '-')"
img_tag="local/$img_name:$version"

build_dir="./build"
dist_dir="./dist"
target="$dist_dir/$img_name.zip"

echo "Name: $name, Image Name: $img_name, Version: $version, Isolation: $isolation, Provider: $provider"
echo "Build directory:    $build_dir"
echo "Target location:    $target"
echo "Host Architecture:  $host_arch"
echo "Target platform:    $target_platform"
echo "Image tag (docker): $img_tag"
echo ""

[[ -d "src" ]] || { echo "This script must be run from the project base directory."; exit 2; }

# --- Prepare directories ---
rm -rf "$build_dir" "$dist_dir"
mkdir -p "$build_dir" "$dist_dir"

# --- Copy & render sources (portable sed) ---
cp ./requirements-ms.txt "$build_dir/requirements.txt"
cp -r src/main "$build_dir"
cp ./src/cumulocity.json "$build_dir/cumulocity.json"
cp ./src/Dockerfile "$build_dir/Dockerfile"

# Portable in-place edit: write to a temp file, then move (works on GNU + BSD sed)
render() {
  local file="$1"
  sed -e "s/{VERSION}/$version/g" \
      -e "s/{ISOLATION}/$isolation/g" \
      -e "s/{PROVIDER}/$provider/g" \
      "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}
render "$build_dir/cumulocity.json"

# --- Build image (always amd64 target, load into local docker) ---
echo "Building image ($target_platform) ..."
docker buildx build \
  --platform "$target_platform" \
  --load \
  -t "$img_tag" \
  "$build_dir"
docker save -o "$dist_dir/image.tar" "$img_tag"


# --- Verify image platform ---
echo "Verifying image platform ..."
image_os="$(docker inspect --format '{{.Os}}' "$img_tag")"
image_arch="$(docker inspect --format '{{.Architecture}}' "$img_tag")"
image_platform="$image_os/$image_arch"
echo "Image platform is: $image_platform"
[[ "$image_platform" == "$target_platform" ]] || { echo "ERROR: Wrong image platform, expected $target_platform."; exit 1; }

# --- Package uploadable archive ---
zip -j "$target" "$build_dir/cumulocity.json" "$dist_dir/image.tar"

echo ""
echo "Created uploadable archive: $target"
