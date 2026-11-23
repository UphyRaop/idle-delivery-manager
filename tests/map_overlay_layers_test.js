const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const context = { window: {} };
vm.runInNewContext(fs.readFileSync("web/map_overlay_layers.js", "utf8"), context);
const layering = context.window.IDMMapLayering;
const style = [
  { id: "background", type: "background" },
  { id: "roads", type: "line" },
  { id: "game-marker", type: "symbol" },
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

assert.equal(layering.areMarkersAboveLabels(style, "game-marker"), false);
assert.equal(layering.promote(map, ["game-marker"]), true);
assert.equal(layering.areMarkersAboveLabels(style, "game-marker"), true);
assert.equal(style.at(-1).id, "game-marker");
// Repair a basemap style that adds labels after the gameplay overlay.
style.push({ id: "late-label", type: "symbol" });
assert.equal(layering.areMarkersAboveLabels(style, "game-marker"), false);
layering.promote(map, ["game-marker"]);
assert.equal(layering.areMarkersAboveLabels(style, "game-marker"), true);
assert.equal(layering.promote({}, ["game-marker"]), false);
console.log("MAP MARKER LAYERING: 6 assertions passed");
