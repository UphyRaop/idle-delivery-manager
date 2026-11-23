const assert = require("node:assert/strict");
const fs = require("node:fs");

const bridge = fs.readFileSync("web/maplibre_bridge.js", "utf8");
const css = fs.readFileSync("web/maplibre_bridge.css", "utf8");
const game = fs.readFileSync("scripts/game.gd", "utf8");

assert.match(bridge, /new window\.maplibregl\.AttributionControl\(\{\s*compact:\s*true\s*\}\)/);
assert.match(bridge, /map\.addControl\(attributionControl,\s*"top-left"\)/);
assert.match(bridge, /map\.on\("load", function \(\)[\s\S]*?attributionToggle\.click\(\)/);
assert.match(bridge, /OpenFreeMap public style\/tiles/);
assert.match(bridge, /required OpenMapTiles and OpenStreetMap attribution/);
assert.match(css, /#idm-map-attribution\.maplibregl-compact\s*\{[^}]*width:\s*40px/s);
assert.match(css, /#idm-map-attribution\.maplibregl-compact-show\s*\{[^}]*max-width:\s*min\(258px,\s*calc\(100vw - 24px\)\)/s);
assert.match(css, /#idm-map-attribution \.maplibregl-ctrl-attrib-button\s*\{[^}]*background-color:\s*transparent !important/s);
assert.match(css, /#idm-map-attribution \.maplibregl-ctrl-attrib-button\s*\{[^}]*stroke='%23e5edf2'/s);
assert.match(css, /#idm-map-attribution a\s*\{[^}]*color:\s*#b7e8ef[^}]*text-decoration:\s*underline/s);
assert.match(css, /env\(safe-area-inset-top,\s*0px\)/);
assert.match(bridge, /function forwardAttributionPointer\(event\)/);
assert.match(bridge, /event\.stopImmediatePropagation\(\)/);
assert.match(bridge, /button\.click\(\)/);
assert.match(bridge, /attributionControlElement\.id = "idm-map-attribution"/);
assert.match(bridge, /document\.body\.appendChild\(attributionControlElement\)/);
assert.match(bridge, /function isAttributionControlEvent\(event\)/);
assert.match(bridge, /let mapVisibilityRequested = false/);
assert.match(bridge, /window\.IDM_MAP_VISIBLE = mapVisibilityRequested/);
assert.match(bridge, /attributionControlElement\.style\.display = mapVisibilityRequested \? "block" : "none"/);
assert.match(bridge, /if \(attributionControlElement\) attributionControlElement\.style\.display = display/);
assert.match(game, /func _update_browser_map\(delta: float\) -> void:[\s\S]*?if selected_tab != "Map" or waiting_bookings_page_open:[\s\S]*?_maplibre_call\("window\.IDMMap\.setVisible\(false\)"\)[\s\S]*?return/);
assert.match(game, /window\.IDM_MAP_VISIBLE=%s;const e=document\.getElementById\('idm-map-root'\);if\(e\)e\.style\.visibility=%s;const a=document\.getElementById\('idm-map-attribution'\);if\(a\)a\.style\.visibility=%s/);

console.log("MAP ATTRIBUTION: 23 assertions passed");
