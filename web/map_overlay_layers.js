/* Small, testable MapLibre style-layer ordering helpers for gameplay markers. */
(function (root) {
  "use strict";

  function promote(map, layerIds) {
    if (!map || typeof map.getLayer !== "function" || typeof map.moveLayer !== "function") return false;
    const layers = map.getStyle && map.getStyle() && map.getStyle().layers;
    if (layerIds.length >= 2 && areMarkersAboveLabels(layers, layerIds[0], layerIds[1])) return true;
    layerIds.forEach(function (id) {
      if (map.getLayer(id)) map.moveLayer(id);
    });
    return true;
  }

  function areMarkersAboveLabels(layers, markerId, markerLabelId) {
    if (!Array.isArray(layers)) return false;
    const markerIndex = layers.findIndex(function (layer) { return layer.id === markerId; });
    const markerLabelIndex = layers.findIndex(function (layer) { return layer.id === markerLabelId; });
    const highestBasemapLabelIndex = layers.reduce(function (highest, layer, index) {
      return layer.type === "symbol" && layer.id !== markerLabelId ? Math.max(highest, index) : highest;
    }, -1);
    return markerIndex > highestBasemapLabelIndex && markerLabelIndex > markerIndex;
  }

  root.IDMMapLayering = { promote: promote, areMarkersAboveLabels: areMarkersAboveLabels };
})(window);
