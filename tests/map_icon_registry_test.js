const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const mapContext = { window: {} };
vm.runInNewContext(fs.readFileSync("web/map_overlay_layers.js", "utf8"), mapContext);
const icons = mapContext.window.IDMMapIcons;
assert.equal(icons.markerVisibleDiameter, 36, "marker circles have the approved visible diameter");
assert.equal(icons.markerHitTarget, 48, "marker symbol hit box is a touch-friendly 48 CSS pixels");
const expected = {
  rider_bicycle: "#22C55E",
  driver_car: "#3B82F6",
  passenger: "#A855F7",
  restaurant: "#F97316",
  merchant: "#EAB308",
  parcel: "#A16207",
  pickup: "#06B6D4",
  dropoff: "#EF4444",
  hub: "#64748B",
  express: "#EC4899",
};
assert.equal(icons.iconIds.length, 10, "central registry defines ten marker types");
assert.deepEqual(Object.fromEntries(icons.iconIds.map((id) => [id, icons.registry[id].color])), expected);
assert.equal(new Set(Object.values(expected)).size, 10, "every marker type has a unique requested color");
assert.equal(icons.iconIdFor("rider_available"), "rider_bicycle");
assert.equal(icons.iconIdFor("rider_active"), "rider_bicycle");
assert.equal(icons.iconIdFor("driver_car"), "driver_car");
assert.equal(icons.iconIdFor("booking_passenger"), "passenger");
assert.equal(icons.iconIdFor("booking_food"), "restaurant");
assert.equal(icons.iconIdFor("booking_parcel"), "parcel");
assert.equal(icons.iconIdFor("booking_express"), "express");
assert.equal(icons.iconIdFor("pickup"), "pickup");
assert.equal(icons.iconIdFor("destination"), "dropoff");
assert.equal(icons.iconIdFor("hub"), "hub");
for (const [service, iconId] of Object.entries({
  food_delivery: "restaurant",
  parcel_logistics: "parcel",
  e_hailing: "driver_car",
  express_logistics: "express",
})) {
  assert.equal(icons.routeColorForService(service), expected[iconId], `route color follows ${service} vehicle/service`);
}
for (const [iconId, color] of Object.entries(expected)) {
  const svg = icons.svgFor(iconId);
  assert.match(svg, /width="48" height="48" viewBox="0 0 48 48"/, `${iconId} uses the shared 48px hit viewport`);
  assert.match(svg, new RegExp(`<circle cx="24" cy="24" r="18" fill="${color}" stroke="#07151f" stroke-width="2"`), `${iconId} has the shared 36px solid circle and requested color`);
  assert.match(svg, /transform="translate\(6 6\) scale\(\.75\)"/, `${iconId} keeps its white glyph inside the shared circle`);
}
assert.match(icons.svgFor("rider_bicycle"), /<circle/);
assert.match(icons.svgFor("driver_car"), /<path/);
assert.match(icons.svgFor("passenger"), /<circle/);
assert.match(icons.svgFor("express", { active: true, selected: true }), /cx="39" cy="9"/);
assert.equal(icons.svgFor("unknown"), "");

// Run the public bridge contract with MapLibre absent. Static marker coordinates
// remain GeoJSON points, while road geometry is accepted only as explicit routes.
const bridgeContext = {
  window: {},
  document: { readyState: "loading", addEventListener() {} },
};
vm.runInNewContext(fs.readFileSync("web/map_overlay_layers.js", "utf8"), bridgeContext);
const bridgeSource = fs.readFileSync("web/maplibre_bridge.js", "utf8");
vm.runInNewContext(bridgeSource, bridgeContext);
const routeCoordinates = [[101.70, 3.10], [101.71, 3.11], [101.72, 3.12]];
assert.equal(bridgeContext.window.IDMMap.setGameplayOverlays({
  routes: [
    { id: "route-7", phase: "delivery", service: "e_hailing", coordinates: routeCoordinates },
    { id: "route-food", phase: "pickup", service: "food_delivery", coordinates: routeCoordinates },
    { id: "route-parcel", phase: "delivery", service: "parcel_logistics", coordinates: routeCoordinates },
    { id: "route-express", phase: "pickup", service: "express_logistics", coordinates: routeCoordinates },
  ],
  markers: [
    { id: "passenger-7", kind: "booking_passenger", service: "e_hailing", coordinates: [101.70, 3.10] },
    { id: "pickup-7", kind: "pickup", coordinates: [101.71, 3.11] },
    { id: "dropoff-7", kind: "destination", coordinates: [101.72, 3.12] },
    { id: "driver-2", kind: "driver_car", service: "e_hailing", status: "busy", coordinates: [101.705, 3.105] },
    { id: "hub-1", kind: "hub", coordinates: [101.69, 3.09] },
  ],
}), true);
const snapshot = bridgeContext.window.IDMMap.getGameplayOverlaySnapshot();
assert.deepEqual(JSON.parse(JSON.stringify(snapshot.routes[0].coordinates)), routeCoordinates, "GeoJSON road route geometry is preserved verbatim");
assert.equal(snapshot.routes[0].properties.route_color, expected.driver_car, "E-hailing route uses the car color");
assert.equal(snapshot.routes[1].properties.route_color, expected.restaurant, "Food route uses the restaurant color");
assert.equal(snapshot.routes[2].properties.route_color, expected.parcel, "Parcel route uses the parcel color");
assert.equal(snapshot.routes[3].properties.route_color, expected.express, "Express route uses the truck color");
assert.equal(snapshot.markers.find((marker) => marker.id === "marker:passenger-7").properties.icon, "passenger");
assert.equal(snapshot.markers.find((marker) => marker.id === "marker:pickup-7").properties.icon, "pickup");
assert.equal(snapshot.markers.find((marker) => marker.id === "marker:dropoff-7").properties.icon, "dropoff");
assert.equal(snapshot.markers.find((marker) => marker.id === "marker:hub-1").properties.icon, "hub");
assert.equal(snapshot.riders[0].kind, "driver_car");
const pickedOverlap = bridgeContext.window.IDMMap.resolveBookingHit([
  { properties: { kind: "pickup", marker_id: "pickup-7" }, geometry: { coordinates: [101.71, 3.11] } },
  { properties: { kind: "booking_parcel", marker_id: "booking-top", booking_id: "21", selected: true }, geometry: { coordinates: [101.70, 3.10] } },
  { properties: { kind: "booking_food", marker_id: "booking-bottom", booking_id: "22" }, geometry: { coordinates: [101.70, 3.10] } },
]);
assert.equal(pickedOverlap.id, "booking-top", "overlapping rendered markers resolve using MapLibre's topmost-first order");
assert.equal(pickedOverlap.bookingId, "21");
assert.equal(pickedOverlap.selected, true);
assert.equal(bridgeContext.window.IDMMap.resolveBookingHit([{ properties: { kind: "pickup" } }]), null, "decorative pickup marker cannot mask a selectable booking hit");
const activeDestinationHit = bridgeContext.window.IDMMap.resolveBookingHit([
  { properties: { kind: "destination", marker_id: "booking-33-destination", booking_id: "33" }, geometry: { coordinates: [101.72, 3.12] } },
]);
assert.equal(activeDestinationHit.kind, "destination", "active delivery destination remains selectable");
assert.equal(activeDestinationHit.bookingId, "33");
assert.equal(bridgeContext.window.IDMMap.resolveBookingHit([{ properties: { kind: "pickup", marker_id: "booking-33-pickup", booking_id: "33" }, geometry: { coordinates: [101.71, 3.11] } }]).bookingId, "33", "selected booking pickup remains selectable");
const riderHitEntry = { id: "rider-4", rider: { accessibleLabel: "Available partner 04", status: "ready", coordinates: [101.7, 3.1] }, rect: { left: 100, top: 100, right: 148, bottom: 148 } };
assert.equal(bridgeContext.window.IDMMap.resolveRiderHit(100, 100, [riderHitEntry]).riderId, "4", "top-left of the 48px rider target selects it");
assert.equal(bridgeContext.window.IDMMap.resolveRiderHit(147, 147, [riderHitEntry]).label, "Available partner 04", "bottom-right interior of the 48px rider target selects it");
assert.equal(bridgeContext.window.IDMMap.resolveRiderHit(148, 148, [riderHitEntry]), null, "tap just outside the rider target does not select it");
assert.match(bridgeSource, /"icon-size": 1,/, "48px GeoJSON symbol bounds remain the full touch target at every zoom");
assert.match(bridgeSource, /element\.style\.width = "48px"/, "dynamic rider DOM markers use the same 48px hit viewport");
assert.equal(bridgeContext.window.IDMMap.setGameplayOverlays({ routes: [], markers: [{ id: "stationary", kind: "merchant", coordinates: [101.7, 3.1] }] }), true);
assert.equal(bridgeContext.window.IDMMap.getGameplayOverlaySnapshot().routes.length, 0, "stationary markers never invent route geometry");
console.log("MAP ICON REGISTRY: 79 assertions passed");
