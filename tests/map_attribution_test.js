const assert = require("node:assert/strict");
const fs = require("node:fs");

const bridge = fs.readFileSync("web/maplibre_bridge.js", "utf8");
const css = fs.readFileSync("web/maplibre_bridge.css", "utf8");
const game = fs.readFileSync("scripts/game.gd", "utf8");

assert.match(bridge, /new window\.maplibregl\.AttributionControl\(\{\s*compact:\s*false\s*\}\)/);
assert.match(bridge, /map\.addControl\(attributionControl,\s*"top-left"\)/);
assert.doesNotMatch(bridge, /attributionToggle\.click\(\)/);
assert.match(bridge, /OpenFreeMap public style\/tiles/);
assert.match(bridge, /required OpenMapTiles and OpenStreetMap attribution/);
assert.match(css, /#idm-map-attribution\s*\{[^}]*max-width:\s*min\(272px,\s*calc\(100vw - 116px - env\(safe-area-inset-left,\s*0px\)\)\)/s);
assert.match(css, /#idm-map-attribution\s*\{[^}]*border:\s*0/s);
assert.match(css, /#idm-map-attribution\s*\{[^}]*background:\s*transparent/s);
assert.match(css, /#idm-map-attribution\s*\{[^}]*transform:\s*none !important/s);
assert.match(css, /#idm-map-attribution \.maplibregl-ctrl-attrib-inner\s*\{[^}]*white-space:\s*normal/s);
assert.match(css, /#idm-map-attribution \.maplibregl-ctrl-attrib-inner\s*\{[^}]*text-wrap:\s*balance/s);
assert.match(css, /#idm-map-attribution > summary\s*\{[^}]*display:\s*none/s);
assert.match(css, /#idm-map-attribution a\s*\{[^}]*color:\s*#d7f4f7[^}]*text-decoration:\s*underline/s);
assert.match(css, /#idm-map-attribution a:focus-visible/);
assert.doesNotMatch(css, /#idm-map-attribution\.maplibregl-compact-show/);
assert.doesNotMatch(css, /#idm-map-attribution \.maplibregl-ctrl-attrib-button/);
assert.match(css, /env\(safe-area-inset-top,\s*0px\)/);
assert.match(css, /env\(safe-area-inset-left,\s*0px\)/);
assert.match(bridge, /function isAttributionControlEvent\(event\)/);
assert.match(bridge, /function forwardAttributionPointer\(event\)/);
assert.match(bridge, /attributionControlElement\.querySelectorAll\("a\[href\]"\)/);
assert.match(bridge, /active\.link\.click\(\)/);
assert.match(bridge, /attributionControlElement\.id = "idm-map-attribution"/);
assert.match(bridge, /document\.body\.appendChild\(attributionControlElement\)/);
assert.match(bridge, /let mapVisibilityRequested = false/);
assert.match(bridge, /window\.IDM_MAP_VISIBLE = mapVisibilityRequested/);
assert.match(bridge, /attributionControlElement\.style\.display = mapVisibilityRequested \? "block" : "none"/);
assert.match(bridge, /if \(attributionControlElement\) attributionControlElement\.style\.display = display/);
assert.match(game, /func _update_browser_map\(delta: float\) -> void:[\s\S]*?if selected_tab != "Map" or waiting_bookings_page_open:[\s\S]*?_maplibre_call\("window\.IDMMap\.setVisible\(false\)"\)[\s\S]*?return/);
assert.match(game, /window\.IDM_MAP_VISIBLE=%s;const e=document\.getElementById\('idm-map-root'\);if\(e\)e\.style\.visibility=%s;const a=document\.getElementById\('idm-map-attribution'\);if\(a\)a\.style\.visibility=%s/);

console.log("MAP ATTRIBUTION: 30 assertions passed");
