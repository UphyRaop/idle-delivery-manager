#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
godot_bin="${GODOT_BIN:-godot}"
output=build/web

# Stage every export in a clean directory before replacing the previous build.
mkdir -p build
staging="$(mktemp -d build/web.XXXXXXXX)"
trap 'rm -rf -- "$staging"' EXIT

"$godot_bin" --headless --path . --editor --import
"$godot_bin" --headless --path . --export-release Web "$staging/index.html"

for asset in index.html index.js index.wasm index.pck; do
  test -s "$staging/$asset"
done

cp CNAME "$staging/CNAME"
touch "$staging/.nojekyll"
rm -rf -- "$output"
mv -- "$staging" "$output"
