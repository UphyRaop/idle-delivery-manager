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
cp manifest.webmanifest "$staging/manifest.webmanifest"
mkdir -p "$staging/brand/icons"
cp assets/branding/idm-logo.svg assets/branding/idm-app-icon.svg "$staging/brand/"
cp assets/branding/icons/* "$staging/brand/icons/"
mkdir -p "$staging/vendor"
cp web/vendor/maplibre-gl.js web/vendor/maplibre-gl.css web/vendor/MAPLIBRE-LICENSE.txt "$staging/vendor/"
cp web/map_overlay_layers.js web/maplibre_bridge.js web/maplibre_bridge.css "$staging/"
python3 - "$staging/index.html" <<'PY'
from pathlib import Path
import sys

html_path = Path(sys.argv[1])
html = html_path.read_text()
html = html.replace(
    '<head>',
    '<head>'
    '<link rel="icon" type="image/svg+xml" href="./favicon.svg">'
    '<link rel="icon" type="image/png" sizes="32x32" href="./brand/icons/idm-icon-32.png">'
    '<link rel="icon" type="image/png" sizes="16x16" href="./brand/icons/idm-icon-16.png">'
    '<link rel="shortcut icon" href="./brand/icons/favicon.ico">'
    '<link rel="apple-touch-icon" sizes="180x180" href="./brand/icons/idm-icon-180.png">'
    '<link rel="manifest" href="./manifest.webmanifest">'
    '<meta name="theme-color" content="#113B48">'
    '<meta name="apple-mobile-web-app-capable" content="yes">'
    '<meta name="apple-mobile-web-app-title" content="IDM">'
    '<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">',
    1,
)
if 'rel="manifest" href="./manifest.webmanifest"' not in html:
    raise SystemExit('Failed to add PWA and touch icon metadata.')
html_path.write_text(html)
PY
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
orientation_css = '''
<style id="idm-phone-orientation">
#idm-rotate-screen[hidden] { display: none !important; }
#idm-rotate-screen:not([hidden]) {
  position: fixed; z-index: 1000; inset: 0; display: grid; place-items: center;
  box-sizing: border-box; width: 100vw; height: 100vh; height: 100dvh;
  padding: calc(24px + env(safe-area-inset-top, 0px)) calc(24px + env(safe-area-inset-right, 0px)) calc(24px + env(safe-area-inset-bottom, 0px)) calc(24px + env(safe-area-inset-left, 0px));
  overflow: auto; background: #081722; color: #f1f6fa;
  font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
.idm-rotate-card { width: min(100%, 420px); box-sizing: border-box; padding: clamp(24px, 6vw, 40px); border: 1px solid #234253; border-radius: 24px; background: #102433; text-align: center; box-shadow: 0 22px 70px rgba(0,0,0,.3); }
.idm-rotate-icon { width: 64px; height: 64px; margin: 0 auto 20px; display: grid; place-items: center; border: 1px solid #28798a; border-radius: 20px; color: #55d9e8; background: #113b48; }
.idm-rotate-card h1 { margin: 0; font-size: clamp(20px, 5vw, 26px); line-height: 1.25; }
.idm-rotate-card p { margin: 12px 0 0; color: #a8bac8; font-size: 15px; line-height: 1.5; }
.idm-rotate-card .idm-rotate-brand { margin-top: 24px; color: #55d9e8; font-size: 13px; }
html.idm-phone-landscape, html.idm-phone-landscape body { overflow: hidden !important; }
html.idm-phone-landscape #canvas, html.idm-phone-landscape #idm-map-root, html.idm-phone-landscape #status { visibility: hidden !important; pointer-events: none !important; }
@media (prefers-reduced-motion: reduce) { #idm-rotate-screen *, #idm-rotate-screen *::before, #idm-rotate-screen *::after { animation: none !important; transition: none !important; } }
</style>
'''
html = html.replace('</head>', orientation_css + '\n</head>')
loader_css = '''
<style id="idm-branded-loader">
#status {
  position: fixed; z-index: 20; inset: 0; width: 100vw; height: 100vh; height: 100dvh;
  box-sizing: border-box; padding: calc(20px + env(safe-area-inset-top, 0px)) calc(20px + env(safe-area-inset-right, 0px)) calc(20px + env(safe-area-inset-bottom, 0px)) calc(20px + env(safe-area-inset-left, 0px));
  overflow: auto; visibility: visible; background: radial-gradient(ellipse at 50% 40%, #132e3b 0%, #081722 68%);
  color: #f1f6fa; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
#status-splash { display: none !important; }
.idm-loader-card { width: min(100%, 390px); box-sizing: border-box; padding: clamp(24px, 7vw, 38px); border: 1px solid #234253; border-radius: 24px; background: rgba(14, 34, 47, .96); box-shadow: 0 22px 70px rgba(0, 0, 0, .3); text-align: center; }
.idm-loader-mark { display: block; width: 58px; height: 58px; margin: 0 auto 20px; border: 1px solid #28798a; border-radius: 18px; background: #113b48; object-fit: cover; }
.idm-loader-title { margin: 0; font-size: clamp(18px, 5vw, 22px); line-height: 1.25; letter-spacing: .045em; font-weight: 750; }
.idm-loader-subtitle { margin: 10px 0 0; color: #55d9e8; font-size: 14px; }
.idm-loader-creator { margin: 25px 0 0; color: #b1c3cd; font-size: 12px; }
.idm-loader-copyright { margin: 6px 0 0; color: #839ba9; font-size: 10px; line-height: 1.4; }
.idm-progress-track { position: relative; height: 8px; margin: 28px 0 0; overflow: hidden; border-radius: 99px; background: #233b49; }
.idm-progress-fill { position: absolute; inset: 0 auto 0 0; width: 0; border-radius: inherit; background: linear-gradient(90deg, #25b5c9, #65e5ed); transition: width .16s ease-out; }
#status[data-progress-mode="indeterminate"] .idm-progress-fill { left: 0; width: 36%; animation: idm-loader-sweep 1.3s ease-in-out infinite alternate; }
#status[data-progress-mode="determinate"] .idm-progress-fill { animation: none; }
.idm-progress-accessible { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0; }
.idm-loader-status { min-height: 18px; margin: 12px 0 0; color: #a8bac8; font-size: 12px; line-height: 1.45; }
#status-notice { display: none; max-width: 100%; max-height: 38vh; box-sizing: border-box; overflow: auto; margin: 18px 0 0; padding: 12px; border: 1px solid #72515a; border-radius: 12px; background: #30242c; color: #f6dfe2; font-size: 13px; line-height: 1.45; text-align: left; }
#idm-loading-retry { display: none; min-height: 48px; margin: 14px auto 0; padding: 0 22px; border: 0; border-radius: 14px; background: #55d9e8; color: #06232b; font: 700 14px system-ui, sans-serif; cursor: pointer; }
#idm-loading-retry:focus-visible { outline: 3px solid #e3fbff; outline-offset: 3px; }
#status[data-status-mode="notice"] .idm-progress-track, #status[data-status-mode="notice"] .idm-loader-status { display: none; }
#status[data-status-mode="notice"] #idm-loading-retry { display: inline-flex; align-items: center; justify-content: center; }
@keyframes idm-loader-sweep { from { transform: translateX(-12%); } to { transform: translateX(205%); } }
@media (prefers-reduced-motion: reduce) {
  #status *, #status *::before, #status *::after { animation: none !important; scroll-behavior: auto !important; transition: none !important; }
  #status[data-progress-mode="indeterminate"] .idm-progress-fill { left: 0; width: 100%; opacity: .72; transform: none; }
}
</style>
'''
html = html.replace('</head>', loader_css + '\n</head>')
html = html.replace('<title>Idle Delivery Manager</title>', '<title>IDLE DELIVERY MANAGER</title>')
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
    '</canvas>\n\t\t<div id="idm-map-root" aria-label="OpenStreetMap geographic basemap"></div>\n'
    '\t\t<div id="idm-rotate-screen" hidden role="status" aria-live="polite">'
    '<section class="idm-rotate-card" aria-label="Rotate your device to portrait">'
    '<div class="idm-rotate-icon" aria-hidden="true">'
    '<svg width="38" height="38" viewBox="0 0 38 38" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<rect x="12" y="5" width="15" height="27" rx="3" stroke="currentColor" stroke-width="2.2"/>'
    '<path d="M17 9h5M18 28h3M6 17a13 13 0 0 1 5-9M5 12l1 5 5-1M32 21a13 13 0 0 1-5 9m6-4-1-5-5 1" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'
    '</svg></div><h1>Rotate your device to portrait</h1>'
    '<p>IDLE DELIVERY MANAGER is designed for mobile portrait play.</p>'
    '<p class="idm-rotate-brand">UR Trade Network</p></section></div>',
    1,
)
default_status = '''\t\t<div id="status">
\t\t\t<img id="status-splash" class="show-image--true fullsize--true use-filter--true" src="index.png" alt="">
\t\t\t<progress id="status-progress"></progress>
\t\t\t<div id="status-notice"></div>
\t\t</div>'''
branded_status = '''\t\t<div id="status" data-progress-mode="indeterminate" data-status-mode="progress" role="status" aria-live="polite">
\t\t\t<section class="idm-loader-card" aria-label="IDLE DELIVERY MANAGER loading">
\t\t\t\t<img class="idm-loader-mark" src="./brand/idm-app-icon.svg" width="58" height="58" alt="" aria-hidden="true">
\t\t\t\t<h1 class="idm-loader-title">IDLE DELIVERY MANAGER</h1>
\t\t\t\t<p class="idm-loader-subtitle">Build Your Logistics Empire</p>
\t\t\t\t<div class="idm-progress-track" aria-hidden="true"><div class="idm-progress-fill" id="idm-progress-fill"></div></div>
\t\t\t\t<progress id="status-progress" class="idm-progress-accessible" aria-label="Game download progress"></progress>
\t\t\t\t<p class="idm-loader-status" id="idm-loader-status">Preparing game files</p>
\t\t\t\t<div id="status-notice" role="alert"></div>
\t\t\t\t<button id="idm-loading-retry" type="button">Retry</button>
\t\t\t\t<p class="idm-loader-creator">Created by UphyRaop</p>
\t\t\t\t<p class="idm-loader-copyright">© 2026 UR Trade Network. All rights reserved.</p>
\t\t\t</section>
\t\t</div>'''
if default_status not in html:
    raise SystemExit('Godot Web status markup changed; branded loader patch needs review.')
html = html.replace(default_status, branded_status, 1)
html = html.replace(
    '<script src="index.js"></script>',
    '<script src="./vendor/maplibre-gl.js"></script>\n'
    '\t\t<script src="./map_overlay_layers.js"></script>\n'
    '\t\t<script src="./maplibre_bridge.js"></script>\n'
    '\t\t<script src="index.js"></script>',
)
loader_bootstrap = """\tconst statusNotice = document.getElementById('status-notice');
\tconst progressFill = document.getElementById('idm-progress-fill');
\tconst loaderStatus = document.getElementById('idm-loader-status');
\tconst retryButton = document.getElementById('idm-loading-retry');
\tretryButton.addEventListener('click', () => window.location.reload());"""
if loader_bootstrap.splitlines()[0] not in html:
    raise SystemExit('Godot Web loader bootstrap changed; custom loading callbacks need review.')
html = html.replace(
    loader_bootstrap.splitlines()[0],
    loader_bootstrap,
    1,
)
html = html.replace(
    "\t\tstatusOverlay.style.visibility = 'visible';",
    "\t\tstatusOverlay.style.visibility = 'visible';\n\t\tstatusOverlay.dataset.statusMode = mode;",
    1,
)
html = html.replace(
    "\t\tsetStatusMode('notice');\n\t\tinitializing = false;",
    "\t\tsetStatusMode('notice');\n\t\tstatusNotice.setAttribute('role', 'alert');\n\t\tloaderStatus.textContent = 'The game could not start. Review the message and retry.';\n\t\tinitializing = false;",
    1,
)
html = html.replace(
    '\t\t\t\tif (current > 0 && total > 0) {',
    '\t\t\t\tif (Number.isFinite(current) && Number.isFinite(total) && current >= 0 && total > 0) {',
    1,
)
html = html.replace(
    '\t\t\t\t\tstatusProgress.value = current;',
    '\t\t\t\t\tconst completed = Math.max(0, Math.min(total, current));\n\t\t\t\t\tstatusProgress.value = completed;',
    1,
)
html = html.replace(
    "\t\t\t\t\tstatusProgress.max = total;",
    "\t\t\t\t\tstatusProgress.max = total;\n\t\t\t\t\tstatusOverlay.dataset.progressMode = 'determinate';\n\t\t\t\t\tprogressFill.style.width = (completed / total * 100) + '%';\n\t\t\t\t\tstatusProgress.setAttribute('aria-valuetext', Math.round(completed / total * 100) + '% downloaded');\n\t\t\t\t\tloaderStatus.textContent = 'Loading game files';",
    1,
)
html = html.replace(
    "\t\t\t\t\tstatusProgress.removeAttribute('max');",
    "\t\t\t\t\tstatusProgress.removeAttribute('max');\n\t\t\t\t\tstatusProgress.removeAttribute('aria-valuetext');\n\t\t\t\t\tstatusOverlay.dataset.progressMode = 'indeterminate';\n\t\t\t\t\tprogressFill.style.width = '';\n\t\t\t\t\tloaderStatus.textContent = 'Loading game files';",
    1,
)
orientation_script = '''
<script id="idm-orientation-controller">
(() => {
  const screenEl = document.getElementById('idm-rotate-screen');
  const root = document.documentElement;
  const isTouchDevice = () => navigator.maxTouchPoints > 0 || window.matchMedia('(pointer: coarse)').matches;
  const screenDimensions = () => ({
    width: Number(window.screen && window.screen.width) || window.innerWidth,
    height: Number(window.screen && window.screen.height) || window.innerHeight,
  });
  const isPhone = () => {
    const size = screenDimensions();
    return isTouchDevice() && Math.min(size.width, size.height) <= 600;
  };
  const isLandscape = () => {
    const orientation = window.screen && window.screen.orientation && window.screen.orientation.type;
    if (orientation && orientation !== 'undefined') return orientation.startsWith('landscape');
    return window.matchMedia('(orientation: landscape)').matches;
  };
  const update = () => {
    const blocked = isPhone() && isLandscape();
    screenEl.hidden = !blocked;
    root.classList.toggle('idm-phone-landscape', blocked);
  };
  window.addEventListener('resize', update, { passive: true });
  window.addEventListener('orientationchange', update, { passive: true });
  window.addEventListener('pageshow', update, { passive: true });
  if (window.visualViewport) window.visualViewport.addEventListener('resize', update, { passive: true });
  if (window.screen && window.screen.orientation && typeof window.screen.orientation.addEventListener === 'function') {
    window.screen.orientation.addEventListener('change', update);
  }
  update();
})();
</script>
'''
html = html.replace('</body>', orientation_script + '\n</body>')
required_loader_tokens = [
    'IDLE DELIVERY MANAGER',
    'Build Your Logistics Empire',
    'UR Trade Network',
    'Created by UphyRaop',
    'data-progress-mode="indeterminate"',
    'idm-loader-sweep',
    "statusOverlay.dataset.progressMode = 'determinate'",
    "statusOverlay.dataset.progressMode = 'indeterminate'",
    'idm-loading-retry',
    '© 2026 UR Trade Network. All rights reserved.',
    'prefers-reduced-motion: reduce',
    'Rotate your device to portrait',
    'screen.orientation',
    'visualViewport',
    'idm-phone-landscape',
]
for token in required_loader_tokens:
    if token not in html:
        raise SystemExit(f'Missing required branded loading behavior: {token}')
if 'idm-loader-company' in html:
    raise SystemExit('The loading footer must not add a publisher line above the creator credit.')
html_path.write_text(html)
PY
grep -q 'viewport-fit=cover' "$staging/index.html"
grep -q 'env(safe-area-inset-bottom' "$staging/index.html"
touch "$staging/.nojekyll"
rm -f "$staging/import.log" "$staging/export.log"
rm -rf -- "$output"
mv -- "$staging" "$output"
