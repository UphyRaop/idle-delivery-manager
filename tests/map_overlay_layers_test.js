const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const context = { window: {} };
vm.runInNewContext(fs.readFileSync("web/map_overlay_layers.js", "utf8"), context);
const layering = context.window.IDMMapLayering;
const style = [
  { id: "background", type: "background" },
  { id: "roads", type: "line" },
  { id: "game-marker", type: "circle" },
  { id: "game-marker-label", type: "symbol" },
  { id: "place-labels", type: "symbol" },
  { id: "road-labels", type: "symbol" },
];
const map = {
  getStyle() { return { layers: style }; },
  getLayer(id) { return style.find((layer) => layer.id === id); },
  moveLayer(id) {
    const index = style.findIndex((layer) => layer.id === id);
    if (index >= 0) style.push(style.splice(index, 1)[0]);
  },
};

assert.equal(layering.areMarkersAboveLabels(style, "game-marker", "game-marker-label"), false);
assert.equal(layering.promote(map, ["game-marker", "game-marker-label"]), true);
assert.equal(layering.areMarkersAboveLabels(style, "game-marker", "game-marker-label"), true);
assert.deepEqual(style.slice(-2).map((layer) => layer.id), ["game-marker", "game-marker-label"]);
// Re-promoting is idempotent and repairs a basemap style that adds labels later.
style.push({ id: "late-label", type: "symbol" });
assert.equal(layering.areMarkersAboveLabels(style, "game-marker", "game-marker-label"), false);
layering.promote(map, ["game-marker", "game-marker-label"]);
assert.equal(layering.areMarkersAboveLabels(style, "game-marker", "game-marker-label"), true);
assert.equal(layering.promote({}, ["game-marker"]), false);
console.log("MAP MARKER LAYERING: 7 assertions passed");
