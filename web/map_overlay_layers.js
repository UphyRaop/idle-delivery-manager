/* Shared MapLibre overlay layering and geographic icon/color contracts. */
(function (root) {
  "use strict";

  const icons = Object.freeze({
    rider_bicycle: Object.freeze({ color: "#22C55E", label: "Rider / bicycle", glyph: '<circle cx="15" cy="35" r="7"/><circle cx="37" cy="35" r="7"/><path d="m15 35 8-14 8 14H15l7-12h9m-4-4h5m-9 0h-4m5-4h1"/>' }),
    driver_car: Object.freeze({ color: "#3B82F6", label: "E-hailing driver / car", glyph: '<path d="m10 30 3-9a4 4 0 0 1 4-3h14a5 5 0 0 1 4 3l4 9v8H9v-8Z"/><path d="m15 27 2-6h14l3 6M9 31h30M15 38v3m18-3v3"/><circle cx="16" cy="34" r="2"/><circle cx="32" cy="34" r="2"/>' }),
    passenger: Object.freeze({ color: "#A855F7", label: "Passenger / person", glyph: '<circle cx="24" cy="15" r="6"/><path d="M13 39v-5a11 11 0 0 1 22 0v5m-11-9v10m-10-8h20"/>' }),
    restaurant: Object.freeze({ color: "#F97316", label: "Restaurant / utensils", glyph: '<path d="M15 10v13m-4-13v8a4 4 0 0 0 8 0v-8m-4 13v16m16-29v29m0-29c-4 4-5 10-5 15h5"/>' }),
    merchant: Object.freeze({ color: "#EAB308", label: "Merchant / store", glyph: '<path d="M11 22h26v18H11zM9 22l4-11h22l4 11m-30 0a5 5 0 0 0 10 0 5 5 0 0 0 10 0 5 5 0 0 0 10 0M18 40V29h9v11"/>' }),
    parcel: Object.freeze({ color: "#A16207", label: "Parcel / package", glyph: '<path d="m24 10 14 7v15l-14 7-14-7V17l14-7Z"/><path d="m10 17 14 8 14-8M24 25v14m-7-25 14 8"/>' }),
    pickup: Object.freeze({ color: "#06B6D4", label: "Pickup / pin", glyph: '<path d="M24 41s13-13 13-23a13 13 0 1 0-26 0c0 10 13 23 13 23Z"/><circle cx="24" cy="18" r="4"/>' }),
    dropoff: Object.freeze({ color: "#EF4444", label: "Drop-off / flag", glyph: '<path d="M14 40V10m1 2h20l-5 7 5 7H15"/><path d="M11 40h9"/>' }),
    hub: Object.freeze({ color: "#64748B", label: "Hub / warehouse", glyph: '<path d="m8 20 16-10 16 10v20H8V20Z"/><path d="M16 25h16v15H16zM16 30h16m-8-5v15M8 20h32"/>' }),
    express: Object.freeze({ color: "#EC4899", label: "Express / truck", glyph: '<path d="M7 15h22v20H7zM29 23h8l5 7v5H29z"/><path d="M33 24v6h8M7 20h22"/><circle cx="15" cy="36" r="3"/><circle cx="35" cy="36" r="3"/>' }),
  });

  const kindToIcon = Object.freeze({
    rider: "rider_bicycle", rider_available: "rider_bicycle", rider_active: "rider_bicycle",
    driver_car: "driver_car", passenger: "passenger", booking_passenger: "passenger",
    restaurant: "restaurant", booking_food: "restaurant", merchant: "merchant",
    parcel: "parcel", booking_parcel: "parcel", pickup: "pickup", dropoff: "dropoff",
    destination: "dropoff", hub: "hub", express: "express", express_truck: "express",
    booking_express: "express",
  });

  const serviceToIcon = Object.freeze({
    food_delivery: "restaurant",
    parcel_logistics: "parcel",
    e_hailing: "passenger",
    express_logistics: "express",
  });

  const serviceToRouteIcon = Object.freeze({
    food_delivery: "restaurant",
    parcel_logistics: "parcel",
    e_hailing: "driver_car",
    express_logistics: "express",
  });

  function iconIdFor(kind, service) {
    const markerKind = String(kind || "");
    if (markerKind === "booking") return serviceToIcon[String(service || "")] || "parcel";
    return kindToIcon[markerKind] || serviceToIcon[String(service || "")] || "parcel";
  }

  function routeColorForService(service) {
    const iconId = serviceToRouteIcon[String(service || "")] || "rider_bicycle";
    return icons[iconId].color;
  }

  function svgFor(iconId, options) {
    const icon = icons[String(iconId || "")];
    if (!icon) return "";
    const settings = options || {};
    const statusRing = settings.active ? '<circle cx="39" cy="9" r="5" fill="#fff" stroke="#07151f" stroke-width="2"/>' : "";
    const selectedRing = settings.selected ? '<circle cx="24" cy="24" r="22" fill="none" stroke="#fff" stroke-width="2"/>' : "";
    return '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">' +
      '<circle cx="24" cy="24" r="21" fill="' + icon.color + '" stroke="#07151f" stroke-width="3"/>' +
      '<g fill="none" stroke="#fff" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round">' + icon.glyph + '</g>' +
      selectedRing + statusRing + '</svg>';
  }

  function promote(map, layerIds) {
    if (!map || typeof map.getLayer !== "function" || typeof map.moveLayer !== "function") return false;
    (Array.isArray(layerIds) ? layerIds : []).forEach(function (id) {
      if (map.getLayer(id)) map.moveLayer(id);
    });
    return true;
  }

  function areMarkersAboveLabels(layers, markerId) {
    if (!Array.isArray(layers)) return false;
    const markerIndex = layers.findIndex(function (layer) { return layer.id === markerId; });
    if (markerIndex < 0) return false;
    const highestBasemapLabelIndex = layers.reduce(function (highest, layer, index) {
      return layer.type === "symbol" && layer.id !== markerId ? Math.max(highest, index) : highest;
    }, -1);
    return markerIndex > highestBasemapLabelIndex;
  }

  root.IDMMapIcons = Object.freeze({
    registry: icons,
    iconIds: Object.freeze(Object.keys(icons)),
    iconIdFor: iconIdFor,
    routeColorForService: routeColorForService,
    svgFor: svgFor,
  });
  root.IDMMapLayering = { promote: promote, areMarkersAboveLabels: areMarkersAboveLabels };
})(window);
