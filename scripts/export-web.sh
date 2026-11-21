#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
godot_bin="${GODOT_BIN:-godot}"
output=build/web

# Stage every export in a clean directory before replacing the previous build.
mkdir -p build
staging="$(mktemp -d build/web.XXXXXXXX)"
trap 'rm -rf -- "$staging"' EXIT

"$godot_bin" --headless --path . --editor --import 2>&1 | tee "$staging/import.log"
if grep -Eq '^(SCRIPT ERROR:|ERROR:|Parse Error:|Failed to load script)' "$staging/import.log"; then
  echo "Godot import reported an error; export cancelled."
  exit 1
fi

"$godot_bin" --headless --path . --export-release Web "$staging/index.html" 2>&1 | tee "$staging/export.log"
if grep -Eq '^(SCRIPT ERROR:|ERROR:|Parse Error:|Failed to load script)' "$staging/export.log"; then
  echo "Godot export reported an error; export cancelled."
  exit 1
fi

for asset in index.html index.js index.wasm index.pck; do
  test -s "$staging/$asset"
done

cp CNAME "$staging/CNAME"
cp favicon.svg "$staging/favicon.svg"
sed -i 's#<head>#<head><link rel="icon" type="image/svg+xml" href="./favicon.svg">#' "$staging/index.html"
grep -q 'href="./favicon.svg"' "$staging/index.html"
touch "$staging/.nojekyll"
rm -f "$staging/import.log" "$staging/export.log"
rm -rf -- "$output"
mv -- "$staging" "$output"
