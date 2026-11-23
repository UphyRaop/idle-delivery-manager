const assert = require("node:assert/strict");
const fs = require("node:fs");

const bridge = fs.readFileSync("web/maplibre_bridge.js", "utf8");
const css = fs.readFileSync("web/maplibre_bridge.css", "utf8");

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
assert.match(bridge, /attributionElement\.id = "idm-map-attribution"/);
assert.match(bridge, /document\.body\.appendChild\(attributionElement\)/);
assert.match(bridge, /function isAttributionControlEvent\(event\)/);

console.log("MAP ATTRIBUTION: 17 assertions passed");
