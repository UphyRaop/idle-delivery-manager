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
mkdir -p "$staging/vendor"
cp web/vendor/maplibre-gl.js web/vendor/maplibre-gl.css web/vendor/MAPLIBRE-LICENSE.txt "$staging/vendor/"
cp web/maplibre_bridge.js web/maplibre_bridge.css "$staging/"
sed -i 's#<head>#<head><link rel="icon" type="image/svg+xml" href="./favicon.svg">#' "$staging/index.html"
grep -q 'href="./favicon.svg"' "$staging/index.html"
python3 - "$staging/index.html" <<'PY'
from pathlib import Path
import sys

html_path = Path(sys.argv[1])
html = html_path.read_text()
html = html.replace(
    '<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0">',
    '<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">',
)
mobile_css = '''
<style id="idm-mobile-viewport">
:root {
  --idm-safe-top: env(safe-area-inset-top, 0px);
  --idm-safe-right: env(safe-area-inset-right, 0px);
  --idm-safe-bottom: env(safe-area-inset-bottom, 0px);
  --idm-safe-left: env(safe-area-inset-left, 0px);
  background: #081722;
}
html, body {
  position: fixed;
  inset: 0;
  width: 100%;
  height: 100%;
  height: 100dvh;
  min-height: 100%;
  margin: 0;
  overflow: hidden;
  overscroll-behavior: none;
  background: #081722;
  touch-action: none;
}
#canvas {
  position: fixed;
  inset: 0;
  z-index: 1;
  width: 100vw !important;
  height: 100vh !important;
  height: 100dvh !important;
  max-width: 100%;
  max-height: 100%;
  display: block;
  touch-action: none;
}
</style>
'''
html = html.replace('</head>', mobile_css + '\n\t</head>')
html = html.replace(
    '</head>',
    '<link rel="stylesheet" href="./vendor/maplibre-gl.css">\n'
    '<link rel="stylesheet" href="./maplibre_bridge.css">\n</head>'
)
html = html.replace(
    '<canvas id="canvas">',
    '<canvas id="canvas">',
)
html = html.replace(
    '</canvas>',
    '</canvas>\n\t\t<div id="idm-map-root" aria-label="OpenStreetMap geographic basemap"></div>',
    1,
)
html = html.replace(
    '<script src="index.js"></script>',
    '<script src="./vendor/maplibre-gl.js"></script>\n'
    '\t\t<script src="./maplibre_bridge.js"></script>\n'
    '\t\t<script src="index.js"></script>',
)
html_path.write_text(html)
PY
grep -q 'viewport-fit=cover' "$staging/index.html"
grep -q 'env(safe-area-inset-bottom' "$staging/index.html"
touch "$staging/.nojekyll"
rm -f "$staging/import.log" "$staging/export.log"
rm -rf -- "$output"
mv -- "$staging" "$output"
