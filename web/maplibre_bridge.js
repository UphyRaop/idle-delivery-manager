/*
 * IDM MapLibre bridge.
 *
 * Integration assumptions:
 * - `maplibregl` is loaded from the repository's vendored MapLibre GL JS build;
 *   this file deliberately makes no CDN request.
 * - The map root is inserted immediately before Godot's `#canvas`. The game
 *   canvas must use an alpha-capable WebGL context and transparent viewport
 *   clear color for the basemap to show through it.
 * - The Godot layer may forward normalized pointer objects using
 *   {type, pointerId, pointerType, clientX, clientY, button, buttons, deltaY}.
 *   A native PointerEvent can also be passed directly. Coordinates are CSS
 *   pixels relative to the browser viewport.
 * - OpenFreeMap public style/tiles are used without an API key. Retain its
 *   required OpenMapTiles and OpenStreetMap attribution and review the public
 *   instance terms and availability before scaling traffic.
 */
(function (window, document) {
  "use strict";

  const STYLE_URLS = {
    dark: "https://tiles.openfreemap.org/styles/dark",
    light: "https://tiles.openfreemap.org/styles/positron",
  };
  const START_CENTER = [101.6869, 3.1390]; // Kuala Lumpur, WGS84 lon/lat.
  const START_ZOOM = 10.6;
  const MIN_ZOOM = 4;
  const MAX_ZOOM = 19;
  const MAP_ROOT_ID = "idm-map-root";
  const GODOT_CANVAS_ID = "canvas";
  const GAME_ROUTES_SOURCE = "idm-game-routes";
  const GAME_MARKERS_SOURCE = "idm-game-markers";
  const GAME_ROUTE_CASING_LAYER = "idm-game-route-casing";
  const GAME_ROUTE_LAYER = "idm-game-routes-line";
  const GAME_MARKER_LAYER = "idm-game-markers-circle";

  let map = null;
  let mapRoot = null;
  let attributionControlElement = null;
  let mapVisibilityRequested = false;
  let ready = false;
  let styleReady = false;
  let themeMode = "dark";
  let appliedTheme = "dark";
  let roadsRestyled = false;
  let blockRects = [];
  let mapLoadAttempts = 0;
  let followTarget = null;
  let followFrame = 0;
  let lastFollowTime = 0;
  const blockedPointers = new Set();
  const attributionPointers = new Map();
  const activePointers = new Map();
  const activeTouches = new Map();
  let lastTouchTap = null;
  let touchDoubleTapPending = false;
  let canvasEventsBound = false;
  let gameplayRoutes = emptyFeatureCollection();
  let gameplayMarkers = emptyFeatureCollection();
  let gameplayRiders = new Map();
  const renderedRiderMarkers = new Map();
  let gameplayRouteSignature = "";
  let gameplayMarkerSignature = "";
  let gameplayIconsReady = false;
  let iconInstallGeneration = 0;

  function ensureRoot() {
    if (typeof window.IDM_MAP_VISIBLE === "boolean") mapVisibilityRequested = window.IDM_MAP_VISIBLE;
    let root = document.getElementById(MAP_ROOT_ID);
    if (!root) {
      root = document.createElement("div");
      root.id = MAP_ROOT_ID;
      root.setAttribute("aria-label", "Interactive OpenStreetMap basemap");
      const canvas = document.getElementById(GODOT_CANVAS_ID);
      if (canvas && canvas.parentNode) {
        // Keep the Godot canvas first in document canvas order. Godot's web
        // bootstrap resolves its GL canvas from the first canvas element.
        canvas.parentNode.insertBefore(root, canvas.nextSibling);
      } else {
        document.body.appendChild(root);
      }
    }
    mapRoot = root;
    root.style.visibility = mapVisibilityRequested ? "visible" : "hidden";
    return root;
  }

  function emit(name, detail) {
    try {
      window.dispatchEvent(new CustomEvent(name, { detail: detail || {} }));
    } catch (_) {
      // Status events are diagnostic only; the public API remains usable.
    }
  }

  function initMap() {
    if (map || !document.body) return;
    const root = ensureRoot();
    if (!window.maplibregl || typeof window.maplibregl.Map !== "function") {
      mapLoadAttempts += 1;
      if (mapLoadAttempts < 300) {
        window.setTimeout(initMap, 100);
      } else {
        emit("idm-map-error", { message: "The bundled MapLibre library did not load." });
      }
      return;
    }

    try {
      bindCanvasEvents();
      map = new window.maplibregl.Map({
        container: root,
        style: STYLE_URLS[themeMode],
        center: START_CENTER,
        zoom: START_ZOOM,
        minZoom: MIN_ZOOM,
        maxZoom: MAX_ZOOM,
        // OpenFreeMap serves CORS-enabled styles and tiles suitable for use
        // from this production origin. Keep the required source attribution
        // collapsed to a small corner control; MapLibre expands its linked
        // provider credits when the player opens it.
        attributionControl: false,
        logoPosition: "bottom-left",
        pitch: 0,
        bearing: 0,
        dragPan: true,
        dragRotate: false,
        touchPitch: false,
        touchZoomRotate: true,
        // Touch double-taps are handled explicitly below. This avoids relying
        // on browser-generated dblclick events, which mobile Safari does not
        // consistently emit for a canvas.
        doubleClickZoom: false,
        scrollZoom: true,
        boxZoom: false,
        keyboard: false,
        cooperativeGestures: false,
        clickTolerance: 8,
        trackResize: true,
      });
      const attributionControl = new window.maplibregl.AttributionControl({ compact: true });
      map.addControl(attributionControl, "top-left");
      attributionControlElement = root.querySelector(".maplibregl-ctrl-attrib");
      if (!attributionControlElement) throw new Error("MapLibre attribution control was not created.");
      attributionControlElement.id = "idm-map-attribution";
      // Escape the basemap's z-index layer so the credit button is visible and
      // natively interactive above the full-screen Godot canvas.
      attributionControlElement.style.display = mapVisibilityRequested ? "block" : "none";
      document.body.appendChild(attributionControlElement);
      appliedTheme = themeMode;

      map.touchZoomRotate.disableRotation();
      map.on("load", function () {
        ready = true;
        // Compact mode is applied on MapLibre's first measured resize. Collapse
        // its initial credits panel after that pass, leaving a corner toggle.
        window.requestAnimationFrame(function () {
          const attributionToggle = attributionControlElement.querySelector(".maplibregl-ctrl-attrib-button");
          if (attributionToggle && attributionControlElement.classList.contains("maplibregl-compact-show")) attributionToggle.click();
        });
        emit("idm-map-ready", getCamera());
      });
      map.on("style.load", function () {
        roadsRestyled = false;
        if (map) {
          // Style layers can be installed at style.load, even while vector
          // tile requests are still outstanding. isStyleLoaded() stays false
          // during that period and must not suppress gameplay overlays.
          styleReady = true;
          ready = true;
          gameplayIconsReady = false;
          installGameplayIconSprites().then(function (installed) {
            if (!installed || !map || !styleReady) return;
            ensureGameplayOverlays();
            syncDynamicRiderMarkers();
          });
          emit("idm-map-style-ready", { theme: themeMode });
          window.setTimeout(applyRoadHierarchy, 700);
        }
      });
      map.on("idle", applyRoadHierarchy);
      map.on("error", function (event) {
        const message = event && event.error ? String(event.error.message || event.error) : "Map style or tile request failed.";
        emit("idm-map-error", { message: message });
      });

      // Any genuine map gesture cancels partner following. Synthetic gestures
      // forwarded by Godot reach the same handlers, while blocked UI gestures do not.
      ["dragstart", "rotatestart", "pitchstart", "wheel"].forEach(function (name) {
        map.on(name, stopFollow);
      });
      map.on("touchstart", function (event) {
        if (event && event.originalEvent && event.originalEvent.touches) stopFollow();
      });
      window.addEventListener("resize", function () {
        if (map) map.resize();
      }, { passive: true });
    } catch (error) {
      map = null;
      ready = false;
      emit("idm-map-error", { message: String(error && error.message ? error.message : error) });
    }
  }

  function bindCanvasEvents() {
    if (canvasEventsBound) return;
    const canvas = document.getElementById(GODOT_CANVAS_ID);
    if (!canvas) {
      window.setTimeout(bindCanvasEvents, 50);
      return;
    }
    canvasEventsBound = true;
    canvas.addEventListener("pointerdown", function (event) {
      if (isAttributionControlEvent(event)) return;
      if (!forwardAttributionPointer(event)) forwardPointerEvent(event);
    }, { capture: true, passive: false });
    window.addEventListener("pointermove", function (event) {
      if (isAttributionControlEvent(event)) return;
      if (!forwardAttributionPointer(event)) forwardPointerEvent(event);
    }, { capture: true, passive: false });
    window.addEventListener("pointerup", function (event) {
      if (isAttributionControlEvent(event)) return;
      if (!forwardAttributionPointer(event)) forwardPointerEvent(event);
    }, { capture: true, passive: false });
    window.addEventListener("pointercancel", function (event) {
      if (isAttributionControlEvent(event)) return;
      if (!forwardAttributionPointer(event)) forwardPointerEvent(event);
    }, { capture: true, passive: false });
    canvas.addEventListener("dblclick", function (event) { forwardPointerEvent(event); }, { capture: true });
    canvas.addEventListener("wheel", function (event) {
      const handled = forwardPointerEvent(event);
      if (handled) event.preventDefault();
    }, { capture: true, passive: false });
  }

  function isAttributionControlEvent(event) {
    const target = event && event.target;
    return Boolean(target && typeof target.closest === "function" && target.closest("#idm-map-attribution"));
  }

  // Godot's canvas is composited above the MapLibre DOM controls. Route taps
  // in the compact credit affordance to MapLibre and keep them out of game/map
  // gestures, otherwise a visible attribution control cannot be opened.
  function forwardAttributionPointer(event) {
    if (!event || !event.isTrusted || !mapRoot) return false;
    const id = pointerId(event);
    const type = eventType(event);
    const point = eventPoint(event);
    const active = attributionPointers.get(id);
    const button = document.querySelector("#idm-map-attribution .maplibregl-ctrl-attrib-button");
    const rect = button ? button.getBoundingClientRect() : null;
    const insideButton = Boolean(rect && point.x >= rect.left && point.x <= rect.right && point.y >= rect.top && point.y <= rect.bottom);

    if (!active && type === "pointerdown" && event.button === 0 && insideButton) {
      attributionPointers.set(id, { x: point.x, y: point.y, moved: false });
      event.preventDefault();
      event.stopImmediatePropagation();
      return true;
    }
    if (!active) return false;

    if (type === "pointermove") {
      if (Math.hypot(point.x - active.x, point.y - active.y) > 8) active.moved = true;
      event.preventDefault();
      event.stopImmediatePropagation();
      return true;
    }
    if (type === "pointerup" || type === "pointercancel") {
      attributionPointers.delete(id);
      event.preventDefault();
      event.stopImmediatePropagation();
      if (type === "pointerup" && !active.moved && insideButton && button) button.click();
      return true;
    }
    return false;
  }

  function applyRoadHierarchy() {
    if (!map || roadsRestyled || !map.getStyle() || !map.getStyle().layers) return;
    roadsRestyled = true;
    map.getStyle().layers.forEach(function (layer) {
      const layerId = layer.id.toLowerCase();
      if (themeMode === "dark") {
        if (layer.type === "background") {
          try { map.setPaintProperty(layer.id, "background-color", "#101a24"); } catch (_) { /* style-specific */ }
        } else if (layer.type === "fill") {
          let fill = null;
          if (layerId.startsWith("water-")) fill = "#102b3d";
          else if (/park|garden|forest|grass|wood|wetland|vegetation/.test(layerId)) fill = "#18372f";
          else if (/residential/.test(layerId)) fill = "#172530";
          else if (/commercial/.test(layerId)) fill = "#1c2b37";
          else if (/industrial/.test(layerId)) fill = "#192832";
          else if (layerId.startsWith("building")) fill = layerId.includes("outline") ? "#304450" : "#20323e";
          if (fill) {
            try { map.setPaintProperty(layer.id, "fill-color", fill); } catch (_) { /* style-specific */ }
          }
        }
      }
      if (layer.type !== "line" || !/(street|road|highway_)/i.test(layer.id)) return;
      const id = layer.id.toLowerCase();
      let width;
      if (/(motorway|trunk)/.test(id)) {
        width = ["interpolate", ["linear"], ["zoom"], 5, 0.55, 9, 0.8, 12, 1.25, 14, 1.8, 18, 3.8];
      } else if (/highway_major/.test(id)) {
        width = ["interpolate", ["linear"], ["zoom"], 7, 0.35, 10, 0.65, 13, 1.05, 16, 2.1, 18, 2.8];
      } else if (/highway_minor|highway_path/.test(id)) {
        width = ["interpolate", ["linear"], ["zoom"], 10, 0.25, 12, 0.4, 14, 0.7, 16, 1.2, 18, 1.6];
      } else if (/(primary|secondary)/.test(id)) {
        width = ["interpolate", ["linear"], ["zoom"], 8, 0.35, 11, 0.7, 14, 1.15, 18, 2.7];
      } else if (/tertiary/.test(id)) {
        width = ["interpolate", ["linear"], ["zoom"], 11, 0.3, 14, 0.75, 18, 1.8];
      } else {
        width = ["interpolate", ["linear"], ["zoom"], 11, 0.28, 12, 0.45, 14, 0.75, 18, 1.8];
      }
      if (/(casing|:bridge$|:tunnel$|:bridge:|:outline|outline:)/.test(id)) {
        width = ["interpolate", ["linear"], ["zoom"], 8, 0.45, 12, 0.75, 14, 1.15, 18, 2.2];
      }
      try { map.setPaintProperty(layer.id, "line-width", width); }
      catch (error) { emit("idm-map-style-warning", { layer: layer.id, message: String(error && error.message ? error.message : error) }); }
      if (themeMode === "dark") {
        const isOutline = /outline|casing/.test(id) || /:bridge|:tunnel/.test(id);
        const major = /(motorway|trunk|primary)/.test(id);
        const secondary = /secondary|highway_major/.test(id);
        const color = isOutline ? "#2b3e4b" : major ? "#718e9e" : secondary ? "#5c7585" : "#49616f";
        try { map.setPaintProperty(layer.id, "line-color", color); } catch (_) { /* Skip style-specific unsupported paint. */ }
      }
    });
    map.getStyle().layers.forEach(function (layer) {
      if (layer.type !== "symbol") return;
      const id = layer.id.toLowerCase();
      if (id === "label-place-suburb" || id === "label-place-village" || id === "place_suburb" || id === "place_village") {
        try { map.setLayerZoomRange(layer.id, 12.5, layer.maxzoom || 24); } catch (_) { /* Keep provider defaults if unavailable. */ }
      }
    });
  }

  function validCoordinate(lon, lat) {
    return Number.isFinite(lon) && Number.isFinite(lat) && lon >= -180 && lon <= 180 && lat >= -85.051129 && lat <= 85.051129;
  }

  function emptyFeatureCollection() {
    return { type: "FeatureCollection", features: [] };
  }

  function cleanCoordinates(value, minimumCount) {
    if (!Array.isArray(value) || value.length < minimumCount) return null;
    const coordinates = [];
    for (const pair of value) {
      if (!Array.isArray(pair) || pair.length < 2) return null;
      const longitude = Number(pair[0]);
      const latitude = Number(pair[1]);
      if (!validCoordinate(longitude, latitude)) return null;
      coordinates.push([longitude, latitude]);
    }
    return coordinates;
  }

  function routeFeatureCollection(routes) {
    const features = [];
    const ids = new Set();
    (Array.isArray(routes) ? routes : []).forEach(function (route) {
      if (!route || typeof route !== "object") return;
      const id = String(route.id === undefined ? "" : route.id).trim();
      const phase = route.phase === "pickup" ? "pickup" : route.phase === "delivery" ? "delivery" : "";
      const service = String(route.service === undefined ? "" : route.service).trim();
      const coordinates = cleanCoordinates(route.coordinates, 2);
      if (!id || ids.has(id) || !phase || !coordinates) return;
      ids.add(id);
      features.push({
        type: "Feature",
        id: "route:" + id,
        properties: {
          route_id: id,
          phase: phase,
          service: service,
          route_color: window.IDMMapIcons ? window.IDMMapIcons.routeColorForService(service) : "#22C55E",
          selected: Boolean(route.selected),
        },
        geometry: { type: "LineString", coordinates: coordinates },
      });
    });
    return { type: "FeatureCollection", features: features };
  }

  function markerFeatureCollection(markers) {
    const features = [];
    const ids = new Set();
    (Array.isArray(markers) ? markers : []).forEach(function (marker) {
      if (!marker || typeof marker !== "object") return;
      const id = String(marker.id === undefined ? "" : marker.id).trim();
      const kind = String(marker.kind === undefined ? "" : marker.kind).trim();
      if (isRiderKind(kind)) return;
      const status = String(marker.status === undefined ? "" : marker.status).trim();
      const service = String(marker.service === undefined ? "" : marker.service).trim();
      const coordinates = cleanCoordinates([marker.coordinates], 1);
      if (!id || ids.has(id) || !kind || !coordinates) return;
      ids.add(id);
      features.push({
        type: "Feature",
        id: "marker:" + id,
        properties: {
          marker_id: id,
          booking_id: String(marker.bookingId === undefined ? "" : marker.bookingId),
          kind: kind,
          status: status,
          service: service,
          icon: window.IDMMapIcons ? window.IDMMapIcons.iconIdFor(kind, service) : "parcel",
          accessible_label: String(marker.accessibleLabel || marker.label || "").slice(0, 80),
          selected: Boolean(marker.selected),
        },
        geometry: { type: "Point", coordinates: coordinates[0] },
      });
    });
    return { type: "FeatureCollection", features: features };
  }

  function isRiderKind(kind) {
    return kind === "rider" || kind === "rider_available" || kind === "rider_active" || kind === "driver_car" || kind === "express_truck";
  }

  function riderMarkerMap(markers) {
    const result = new Map();
    (Array.isArray(markers) ? markers : []).forEach(function (marker) {
      if (!marker || typeof marker !== "object") return;
      const id = String(marker.id === undefined ? "" : marker.id).trim();
      const kind = String(marker.kind === undefined ? "" : marker.kind).trim();
      const coordinates = cleanCoordinates([marker.coordinates], 1);
      if (!id || !isRiderKind(kind) || !coordinates || result.has(id)) return;
      result.set(id, {
        coordinates: coordinates[0],
        kind: kind,
        status: String(marker.status === undefined ? "ready" : marker.status),
        service: String(marker.service === undefined ? "" : marker.service).trim(),
        accessibleLabel: String(marker.accessibleLabel || marker.label || "").slice(0, 80),
        iconId: window.IDMMapIcons ? window.IDMMapIcons.iconIdFor(kind, marker.service) : "rider_bicycle",
        selected: Boolean(marker.selected),
      });
    });
    return result;
  }

  function syncDynamicRiderMarkers() {
    if (!map || !window.maplibregl || typeof window.maplibregl.Marker !== "function" || !window.IDMMapIcons) return false;
    const wanted = new Set();
    gameplayRiders.forEach(function (rider, id) {
      wanted.add(id);
      let rendered = renderedRiderMarkers.get(id);
      if (!rendered) {
        const element = document.createElement("div");
        element.className = "idm-map-rider-marker";
        element.setAttribute("role", "img");
        // The outer marker button area remains 48×48 while the shared SVG
        // draws a 36px solid category circle. This keeps touch targets
        // consistent with the static GeoJSON symbols below.
        element.style.width = "48px";
        element.style.height = "48px";
        element.style.boxSizing = "border-box";
        element.style.display = "block";
        element.style.background = "transparent";
        element.style.border = "0";
        element.style.pointerEvents = "none";
        element.style.userSelect = "none";
        element.style.willChange = "transform";
        element.style.zIndex = "10";
        const marker = new window.maplibregl.Marker({ element: element, anchor: "center" }).setLngLat(rider.coordinates).addTo(map);
        rendered = { marker: marker, element: element, coordinates: null };
        renderedRiderMarkers.set(id, rendered);
      }
      const active = rider.status === "busy" || rider.kind === "rider_active";
      rendered.element.innerHTML = window.IDMMapIcons.svgFor(rider.iconId, { active: active, selected: rider.selected });
      rendered.element.setAttribute("aria-label", (active ? "Active partner " : "Available partner ") + id + (rider.service ? " · " + rider.service.replaceAll("_", " ") : ""));
      if (!rendered.coordinates || rendered.coordinates[0] !== rider.coordinates[0] || rendered.coordinates[1] !== rider.coordinates[1]) {
        rendered.marker.setLngLat(rider.coordinates);
        rendered.coordinates = rider.coordinates.slice();
      }
    });
    renderedRiderMarkers.forEach(function (rendered, id) {
      if (wanted.has(id)) return;
      rendered.marker.remove();
      renderedRiderMarkers.delete(id);
    });
    return true;
  }

  function firstSymbolLayerId() {
    const layers = map && map.getStyle() ? map.getStyle().layers : [];
    const firstSymbol = Array.isArray(layers) ? layers.find(function (layer) { return layer.type === "symbol"; }) : null;
    return firstSymbol ? firstSymbol.id : undefined;
  }

  function addLayerBeforeLabels(layer) {
    if (map.getLayer(layer.id)) return;
    const before = firstSymbolLayerId();
    if (before) map.addLayer(layer, before);
    else map.addLayer(layer);
  }

  // Base style labels are MapLibre symbol layers and can be drawn after an
  // overlay inserted before the first symbol. Keep markers above every
  // basemap label regardless of provider style ordering or reloads.
  function placeGameplayMarkersAboveBasemap() {
    if (!map) return false;
    if (window.IDMMapLayering) return window.IDMMapLayering.promote(map, [GAME_MARKER_LAYER]);
    if (map.getLayer(GAME_MARKER_LAYER)) map.moveLayer(GAME_MARKER_LAYER);
    return true;
  }

  function installGameplayIconSprites() {
    if (!map || !styleReady || !window.IDMMapIcons || typeof window.Image !== "function") return Promise.resolve(false);
    const generation = ++iconInstallGeneration;
    const iconIds = window.IDMMapIcons.iconIds;
    return Promise.all(iconIds.map(function (iconId) {
      if (map.hasImage(iconId)) return Promise.resolve([iconId, null]);
      return new Promise(function (resolve) {
        const image = new window.Image();
        image.onload = function () { resolve([iconId, image]); };
        image.onerror = function () { resolve([iconId, null]); };
        image.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(window.IDMMapIcons.svgFor(iconId));
      });
    })).then(function (images) {
      if (!map || !styleReady || generation !== iconInstallGeneration) return false;
      let complete = true;
      images.forEach(function (entry) {
        const iconId = entry[0];
        const image = entry[1];
        if (map.hasImage(iconId)) return;
        if (!image) {
          complete = false;
          emit("idm-map-error", { message: "Map icon could not load: " + iconId });
          return;
        }
        // The SVG is already authored at 48×48. Register at 1× so icon-size
        // remains expressed in the intended CSS-pixel scale on every DPR.
        try { map.addImage(iconId, image, { pixelRatio: 1 }); }
        catch (error) {
          complete = false;
          emit("idm-map-error", { message: "Map icon could not be registered: " + iconId + " · " + String(error && error.message ? error.message : error) });
        }
      });
      gameplayIconsReady = complete;
      return complete;
    });
  }

  function ensureGameplayOverlays() {
    if (!map || !styleReady || !gameplayIconsReady || !map.getStyle() || !Array.isArray(map.getStyle().layers)) return false;
    try {
      if (!map.getSource(GAME_ROUTES_SOURCE)) {
        map.addSource(GAME_ROUTES_SOURCE, { type: "geojson", data: gameplayRoutes });
      }
      if (!map.getSource(GAME_MARKERS_SOURCE)) {
        map.addSource(GAME_MARKERS_SOURCE, { type: "geojson", data: gameplayMarkers });
      }
      addLayerBeforeLabels({
        id: GAME_ROUTE_CASING_LAYER,
        type: "line",
        source: GAME_ROUTES_SOURCE,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": "#07151f",
          "line-opacity": 0.88,
          "line-width": ["interpolate", ["linear"], ["zoom"], 8, ["case", ["get", "selected"], 5.2, 4.2], 14, ["case", ["get", "selected"], 8, 6], 19, ["case", ["get", "selected"], 11, 8]],
        },
      });
      addLayerBeforeLabels({
        id: GAME_ROUTE_LAYER,
        type: "line",
        source: GAME_ROUTES_SOURCE,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": ["get", "route_color"],
          "line-opacity": 0.97,
          "line-width": ["interpolate", ["linear"], ["zoom"], 8, ["case", ["get", "selected"], 3.2, 2.2], 14, ["case", ["get", "selected"], 5.2, 3.6], 19, ["case", ["get", "selected"], 7.2, 5]],
        },
      });
      addLayerBeforeLabels({
        id: GAME_MARKER_LAYER,
        type: "symbol",
        source: GAME_MARKERS_SOURCE,
        layout: {
          "icon-image": ["get", "icon"],
          // A 48px transparent SVG viewport is the hit box. The colored
          // circle inside remains 36px at all zoom levels.
          "icon-size": 1,
          "icon-anchor": "center",
          "icon-allow-overlap": true,
          "icon-ignore-placement": true,
          "icon-rotation-alignment": "viewport",
          "icon-pitch-alignment": "viewport",
        },
        paint: {
          "icon-opacity": 0.98,
        },
      });
      setSourceDataIfChanged(GAME_ROUTES_SOURCE, gameplayRoutes, "routes");
      setSourceDataIfChanged(GAME_MARKERS_SOURCE, gameplayMarkers, "markers");
      placeGameplayMarkersAboveBasemap();
      return true;
    } catch (error) {
      emit("idm-map-error", { message: "Could not install gameplay overlays: " + String(error && error.message ? error.message : error) });
      return false;
    }
  }

  function setSourceDataIfChanged(sourceId, collection, kind) {
    const signature = JSON.stringify(collection);
    if (kind === "routes") {
      if (signature === gameplayRouteSignature) return;
      gameplayRouteSignature = signature;
    } else {
      if (signature === gameplayMarkerSignature) return;
      gameplayMarkerSignature = signature;
    }
    const source = map && map.getSource(sourceId);
    if (source && typeof source.setData === "function") source.setData(collection);
  }

  // Replace the complete gameplay overlay state. Coordinates are WGS84 arrays
  // in [longitude, latitude] order. Omitted IDs are removed on this update.
  function setGameplayOverlays(payload) {
    const value = payload && typeof payload === "object" ? payload : {};
    const nextRoutes = routeFeatureCollection(value.routes);
    const nextMarkers = markerFeatureCollection(value.markers);
    const nextRiders = riderMarkerMap(value.markers);
    const nextRouteSignature = JSON.stringify(nextRoutes);
    const nextMarkerSignature = JSON.stringify(nextMarkers);
    const routesChanged = nextRouteSignature !== gameplayRouteSignature;
    const markersChanged = nextMarkerSignature !== gameplayMarkerSignature;
    gameplayRoutes = nextRoutes;
    gameplayMarkers = nextMarkers;
    gameplayRiders = nextRiders;
    if (map && styleReady) {
      if (!ensureGameplayOverlays()) return false;
      if (routesChanged) setSourceDataIfChanged(GAME_ROUTES_SOURCE, gameplayRoutes, "routes");
      if (markersChanged) setSourceDataIfChanged(GAME_MARKERS_SOURCE, gameplayMarkers, "markers");
    }
    if (map) syncDynamicRiderMarkers();
    return true;
  }

  function clearGameplayOverlays() {
    return setGameplayOverlays({ routes: [], markers: [] });
  }

  // High-frequency simulation updates contain only moving partner positions.
  // Keep route GeoJSON out of the per-frame bridge payload so vehicle tracking
  // stays responsive without repeatedly serializing road geometry.
  function setRiderPositions(markers) {
    gameplayRiders = riderMarkerMap(markers);
    if (map) syncDynamicRiderMarkers();
    return true;
  }

  // Hit-test the rendered geographic marker layer rather than the Godot HUD
  // canvas. CSS viewport coordinates are passed through to MapLibre.
  // MapLibre returns overlapping features topmost-first; retain that ordering
  // so one tap resolves predictably while still skipping pickup/decorative
  // features that do not represent a selectable booking.
  function bookingHitFromFeatures(features) {
    for (const feature of Array.isArray(features) ? features : []) {
      const properties = feature && feature.properties || {};
      const kind = String(properties.kind || "");
      const bookingId = String(properties.booking_id || "");
      const selectableBooking = kind === "booking" || kind.startsWith("booking_") || bookingId !== "";
      if (!selectableBooking) continue;
      const coordinates = feature.geometry && Array.isArray(feature.geometry.coordinates) ? feature.geometry.coordinates : [];
      return {
        id: String(properties.marker_id || ""),
        bookingId: bookingId,
        kind: kind,
        label: String(properties.label || ""),
        coordinates: coordinates.slice(0, 2).map(Number),
        selected: Boolean(properties.selected),
      };
    }
    return null;
  }

  function riderHitFromEntries(x, y, entries) {
    const pointX = Number(x);
    const pointY = Number(y);
    for (const entry of Array.isArray(entries) ? entries : []) {
      const rect = entry && entry.rect;
      if (!rect || pointX < rect.left || pointX >= rect.right || pointY < rect.top || pointY >= rect.bottom) continue;
      const rider = entry.rider || {};
      const rawRiderId = String(entry.id || "").replace(/^rider-/, "");
      return {
        kind: "rider",
        riderId: rawRiderId,
        label: rider.accessibleLabel || (rider.status === "busy" ? "Active partner" : "Available partner"),
        coordinates: Array.isArray(rider.coordinates) ? rider.coordinates.slice(0, 2) : [],
        status: rider.status || "ready",
        service: rider.service || "",
        selected: Boolean(rider.selected),
      };
    }
    return null;
  }

  function pickRiderAt(x, y) {
    const entries = [];
    Array.from(renderedRiderMarkers.entries()).reverse().forEach(function (entry) {
      const rendered = entry[1];
      const rect = rendered.element.getBoundingClientRect();
      entries.push({ id: entry[0], rider: gameplayRiders.get(entry[0]), rect: { left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom } });
    });
    return riderHitFromEntries(x, y, entries);
  }

  function pickBookingAt(x, y) {
    const pointX = Number(x);
    const pointY = Number(y);
    if (!map || !styleReady || ![pointX, pointY].every(Number.isFinite) || !map.getLayer(GAME_MARKER_LAYER)) return null;
    const riderHit = pickRiderAt(pointX, pointY);
    if (riderHit) return riderHit;
    const features = map.queryRenderedFeatures([pointX, pointY], { layers: [GAME_MARKER_LAYER] });
    return bookingHitFromFeatures(features);
  }

  function projectCoordinate(coordinates) {
    if (!map || !styleReady || !Array.isArray(coordinates) || coordinates.length < 2) return null;
    const longitude = Number(coordinates[0]);
    const latitude = Number(coordinates[1]);
    if (!validCoordinate(longitude, latitude)) return null;
    const point = map.project([longitude, latitude]);
    return [point.x, point.y];
  }

  function gameplayOverlayState() {
    const layers = map && map.getStyle() && Array.isArray(map.getStyle().layers) ? map.getStyle().layers : [];
    return {
      routeCount: gameplayRoutes.features.length,
      markerCount: gameplayMarkers.features.length + gameplayRiders.size,
      dynamicRiderCount: renderedRiderMarkers.size,
      sourcesReady: Boolean(map && map.getSource(GAME_ROUTES_SOURCE) && map.getSource(GAME_MARKERS_SOURCE)),
      layersReady: Boolean(map && map.getLayer(GAME_ROUTE_LAYER) && map.getLayer(GAME_MARKER_LAYER)),
      markerLayersAboveBasemapLabels: window.IDMMapLayering ? window.IDMMapLayering.areMarkersAboveLabels(layers, GAME_MARKER_LAYER) : false,
    };
  }

  function gameplayOverlaySnapshot() {
    return {
      routes: gameplayRoutes.features.map(function (feature) {
        return { id: feature.id, properties: Object.assign({}, feature.properties), coordinates: feature.geometry.coordinates.map(function (point) { return point.slice(); }) };
      }),
      markers: gameplayMarkers.features.map(function (feature) {
        return { id: feature.id, properties: Object.assign({}, feature.properties), coordinates: feature.geometry.coordinates.slice() };
      }),
      riders: Array.from(gameplayRiders.entries()).map(function (entry) {
        return { id: entry[0], kind: entry[1].kind, status: entry[1].status, coordinates: entry[1].coordinates.slice() };
      }),
    };
  }

  function overlayRenderDiagnostics() {
    if (!map) return { riders: [], routeLayerReady: false };
    const riders = [];
    renderedRiderMarkers.forEach(function (rendered, id) {
      const rect = rendered.element.getBoundingClientRect();
      const projected = map.project(rendered.marker.getLngLat());
      riders.push({
        id: id,
        longitude: rendered.marker.getLngLat().lng,
        latitude: rendered.marker.getLngLat().lat,
        projected: [projected.x, projected.y],
        rendered: [rect.left + rect.width / 2, rect.top + rect.height / 2],
      });
    });
    return { riders: riders, routeLayerReady: Boolean(map.getLayer(GAME_ROUTE_LAYER)) };
  }

  function routeRenderedAt(coordinates) {
    if (!map || !map.getLayer(GAME_ROUTE_LAYER) || !Array.isArray(coordinates) || coordinates.length < 2) return false;
    const point = map.project([Number(coordinates[0]), Number(coordinates[1])]);
    return map.queryRenderedFeatures(point, { layers: [GAME_ROUTE_LAYER] }).length > 0;
  }

  function getCamera() {
    if (!map) return null;
    const center = map.getCenter();
    return {
      center: [center.lng, center.lat],
      zoom: map.getZoom(),
      bearing: map.getBearing(),
      pitch: map.getPitch(),
    };
  }

  function zoomBy(factor, point, duration) {
    if (!map || !Number.isFinite(Number(factor)) || Number(factor) <= 0) return false;
    const current = map.getZoom();
    const next = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, current + Math.log2(Number(factor))));
    const options = { zoom: next, duration: Number.isFinite(Number(duration)) ? Math.max(0, Number(duration)) : 180, essential: true };
    if (Array.isArray(point) && point.length >= 2 && point.every(Number.isFinite)) options.around = map.unproject(point);
    stopFollow();
    map.easeTo(options);
    return true;
  }

  function setView(center, zoom, duration) {
    if (!map || !Array.isArray(center) || center.length < 2) return false;
    const lon = Number(center[0]);
    const lat = Number(center[1]);
    const targetZoom = Number(zoom);
    if (!validCoordinate(lon, lat) || !Number.isFinite(targetZoom)) return false;
    stopFollow();
    const ms = Number.isFinite(Number(duration)) ? Math.max(0, Number(duration)) : 600;
    if (ms === 0) map.jumpTo({ center: [lon, lat], zoom: targetZoom, bearing: 0, pitch: 0 });
    else map.easeTo({ center: [lon, lat], zoom: targetZoom, bearing: 0, pitch: 0, duration: ms, essential: true });
    return true;
  }

  function setTheme(mode) {
    if (mode !== "dark" && mode !== "light") return false;
    themeMode = mode;
    if (!map) return true;
    if (appliedTheme === mode) return true;
    // MapLibre preserves its current camera when replacing the style.
    styleReady = false;
    gameplayIconsReady = false;
    iconInstallGeneration += 1;
    map.setStyle(STYLE_URLS[mode], { diff: false });
    appliedTheme = mode;
    return true;
  }

  function setVisible(visible) {
    const root = ensureRoot();
    mapVisibilityRequested = Boolean(visible);
    window.IDM_MAP_VISIBLE = mapVisibilityRequested;
    const display = mapVisibilityRequested ? "block" : "none";
    root.style.visibility = mapVisibilityRequested ? "visible" : "hidden";
    if (attributionControlElement) attributionControlElement.style.display = display;
    if (attributionControlElement) attributionControlElement.style.visibility = display === "block" ? "visible" : "hidden";
    const changed = root.style.display !== display;
    if (!changed) return true;
    root.style.display = display;
    if (visible && map) {
      window.requestAnimationFrame(function () {
        if (!map || root.style.display === "none") return;
        map.resize();
        if (map.isStyleLoaded()) ready = true;
        syncDynamicRiderMarkers();
      });
    }
    return true;
  }

  function normalizeRect(rect) {
    if (!rect || typeof rect !== "object") return null;
    let x = Number(rect.x !== undefined ? rect.x : rect.left);
    let y = Number(rect.y !== undefined ? rect.y : rect.top);
    let width = Number(rect.width);
    let height = Number(rect.height);
    if (!Number.isFinite(width) && Number.isFinite(Number(rect.right))) width = Number(rect.right) - x;
    if (!Number.isFinite(height) && Number.isFinite(Number(rect.bottom))) height = Number(rect.bottom) - y;
    if (![x, y, width, height].every(Number.isFinite) || width <= 0 || height <= 0) return null;
    return { x: x, y: y, width: width, height: height };
  }

  function setBlockRects(rects) {
    blockRects = Array.isArray(rects) ? rects.map(normalizeRect).filter(Boolean) : [];
    return blockRects.length;
  }

  function pointIsBlocked(x, y) {
    if (!Number.isFinite(x) || !Number.isFinite(y)) return true;
    return blockRects.some(function (rect) {
      return x >= rect.x && x <= rect.x + rect.width && y >= rect.y && y <= rect.y + rect.height;
    });
  }

  function eventType(event) {
    const raw = String(event.type || event.phase || event.action || "").toLowerCase();
    if (raw === "screen_touch" || raw === "touch") {
      if (event.pressed === true) return "pointerdown";
      if (event.pressed === false) return "pointerup";
    }
    if (raw === "screen_drag") return "pointermove";
    if (raw === "down" || raw === "start" || raw === "press") return "pointerdown";
    if (raw === "move" || raw === "drag") return "pointermove";
    if (raw === "up" || raw === "end" || raw === "release") return "pointerup";
    if (raw === "cancel") return "pointercancel";
    return raw;
  }

  function eventPoint(event) {
    let x = event.clientX;
    let y = event.clientY;
    if (!Number.isFinite(Number(x))) x = event.x;
    if (!Number.isFinite(Number(y))) y = event.y;
    if (!Number.isFinite(Number(x)) && Number.isFinite(Number(event.positionX))) x = event.positionX;
    if (!Number.isFinite(Number(y)) && Number.isFinite(Number(event.positionY))) y = event.positionY;
    return { x: Number(x), y: Number(y) };
  }

  function pointerId(event) {
    const value = event.pointerId !== undefined ? event.pointerId : (event.pointer_id !== undefined ? event.pointer_id : (event.index !== undefined ? event.index : 1));
    return String(value);
  }

  function pointerType(event) {
    const value = String(event.pointerType || event.pointer_type || "mouse").toLowerCase();
    return value === "touch" || value === "pen" ? "touch" : "mouse";
  }

  function canvasTarget() {
    return map ? map.getCanvas() : null;
  }

  function dispatchMouse(name, event, point, id) {
    const target = canvasTarget();
    if (!target) return;
    const buttons = Number.isFinite(Number(event.buttons)) ? Number(event.buttons) : (name === "mouseup" ? 0 : (name === "mousemove" ? (activePointers.has(id) ? 1 : 0) : 1));
    const button = Number.isFinite(Number(event.button)) ? Number(event.button) : 0;
    const detail = Number.isFinite(Number(event.detail)) ? Number(event.detail) : 0;
    let forwarded;
    if (name === "wheel" && typeof WheelEvent !== "undefined") {
      forwarded = new WheelEvent("wheel", {
        bubbles: true, cancelable: true, clientX: point.x, clientY: point.y,
        deltaX: Number(event.deltaX || 0), deltaY: Number(event.deltaY || event.delta_y || 0),
        deltaMode: Number(event.deltaMode || 0), ctrlKey: Boolean(event.ctrlKey),
      });
    } else if (name === "dblclick") {
      forwarded = new MouseEvent("dblclick", { bubbles: true, cancelable: true, clientX: point.x, clientY: point.y, button: 0, detail: 2 });
    } else {
      forwarded = new MouseEvent(name, {
        bubbles: true, cancelable: true, view: window,
        clientX: point.x, clientY: point.y,
        screenX: Number(event.screenX || point.x), screenY: Number(event.screenY || point.y),
        button: button, buttons: buttons, detail: detail,
        ctrlKey: Boolean(event.ctrlKey), shiftKey: Boolean(event.shiftKey), altKey: Boolean(event.altKey),
      });
    }
    target.dispatchEvent(forwarded);
  }

  function makeTouch(record, target) {
    if (typeof Touch === "undefined") return null;
    return new Touch({
      identifier: Number(record.id), target: target,
      clientX: record.x, clientY: record.y,
      screenX: record.screenX, screenY: record.screenY,
      pageX: record.x + window.scrollX, pageY: record.y + window.scrollY,
      radiusX: 2, radiusY: 2, rotationAngle: 0, force: 0.5,
    });
  }

  function dispatchTouch(name, record) {
    const target = canvasTarget();
    if (!target) return;
    if (typeof Touch === "undefined" || typeof TouchEvent === "undefined") {
      // Older WebKit fallback: this preserves one-finger pan but not pinch.
      const mouseName = name === "touchstart" ? "mousedown" : name === "touchend" || name === "touchcancel" ? "mouseup" : "mousemove";
      dispatchMouse(mouseName, { button: 0, buttons: mouseName === "mouseup" ? 0 : 1 }, record, record.id);
      return;
    }
    const touches = Array.from(activeTouches.values()).map(function (touch) { return makeTouch(touch, target); }).filter(Boolean);
    const changed = makeTouch(record, target);
    target.dispatchEvent(new TouchEvent(name, {
      bubbles: true, cancelable: true,
      touches: touches, targetTouches: touches, changedTouches: changed ? [changed] : [],
    }));
  }

  function cancelForwardedPointer(id, record) {
    const active = activePointers.get(id);
    if (!active) return;
    if (active.kind === "touch") {
      const stored = activeTouches.get(id) || record || active;
      activeTouches.delete(id);
      dispatchTouch("touchcancel", stored);
    } else {
      dispatchMouse("mouseup", { button: 0, buttons: 0 }, record || active, id);
    }
    activePointers.delete(id);
  }

  function forwardPointerEvent(input) {
    if (!map || !input || typeof input !== "object") return false;
    const event = input;
    const type = eventType(event);
    const id = pointerId(event);
    const kind = pointerType(event);
    const point = eventPoint(event);
    const ending = type === "pointerup" || type === "pointercancel" || type === "touchend" || type === "touchcancel" || type === "mouseup";
    const beginning = type === "pointerdown" || type === "touchstart" || type === "mousedown";
    const moving = type === "pointermove" || type === "touchmove" || type === "mousemove";

    // Godot also forwards the same browser touch stream from its input callback.
    // The captured native PointerEvents are authoritative; do not replay their
    // compatibility copy into MapLibre or overwrite the tap recognizer state.
    if (!event.isTrusted && activePointers.has(id) && activePointers.get(id).native && (kind === "touch" || type.indexOf("touch") === 0 || type === "pointerup" || type === "pointermove")) return true;

    if (beginning) {
      if (pointIsBlocked(point.x, point.y)) {
        blockedPointers.add(id);
        return false;
      }
      blockedPointers.delete(id);
      const record = { id: id, kind: kind, x: point.x, y: point.y, startX: point.x, startY: point.y, moved: false, startedAt: performance.now(), native: Boolean(event.isTrusted), screenX: Number(event.screenX || point.x), screenY: Number(event.screenY || point.y) };
      activePointers.set(id, record);
      if (kind === "touch" || type === "touchstart") {
        activePointers.get(id).kind = "touch";
        activeTouches.set(id, record);
        dispatchTouch("touchstart", record);
      } else {
        dispatchMouse("mousedown", event, point, id);
      }
      return true;
    }

    if (moving) {
      if (blockedPointers.has(id)) return false;
      const active = activePointers.get(id);
      if (active && active.kind === "touch" && Math.hypot(point.x - active.startX, point.y - active.startY) > 12) active.moved = true;
      // A forwarded stream that enters an overlay is cancelled at the map and
      // remains blocked until its matching release, so it cannot drag behind UI.
      if (pointIsBlocked(point.x, point.y)) {
        cancelForwardedPointer(id, { id: id, kind: active ? active.kind : kind, x: point.x, y: point.y, screenX: point.x, screenY: point.y });
        blockedPointers.add(id);
        return false;
      }
      if (active && active.kind === "touch") {
        const record = Object.assign({}, active, { x: point.x, y: point.y, screenX: Number(event.screenX || point.x), screenY: Number(event.screenY || point.y) });
        activePointers.set(id, record);
        activeTouches.set(id, record);
        dispatchTouch("touchmove", record);
      } else {
        dispatchMouse("mousemove", event, point, id);
      }
      return true;
    }

    if (ending) {
      if (blockedPointers.has(id)) {
        blockedPointers.delete(id);
        return false;
      }
      const active = activePointers.get(id);
      const record = active || { id: id, kind: kind, x: point.x, y: point.y, screenX: point.x, screenY: point.y };
      if (active && active.kind === "touch" && active.native && active.moved !== true && type !== "pointercancel" && type !== "touchcancel") {
        const now = performance.now();
        const closeToPrevious = lastTouchTap && now - lastTouchTap.at <= 360 && Math.hypot(point.x - lastTouchTap.x, point.y - lastTouchTap.y) <= 40;
        if (closeToPrevious) {
          touchDoubleTapPending = true;
          lastTouchTap = null;
          zoomBy(1.5, [point.x, point.y], 200);
        } else {
          lastTouchTap = { at: now, x: point.x, y: point.y };
        }
      }
      if (record.kind === "touch" || type === "touchend" || type === "touchcancel") {
        activeTouches.delete(id);
        record.x = point.x; record.y = point.y;
        dispatchTouch(type === "pointercancel" || type === "touchcancel" ? "touchcancel" : "touchend", record);
      } else {
        dispatchMouse("mouseup", event, point, id);
      }
      activePointers.delete(id);
      return Boolean(active);
    }

    if (type === "wheel") {
      if (pointIsBlocked(point.x, point.y)) return false;
      dispatchMouse("wheel", event, point, id);
      return true;
    }
    if (type === "dblclick" || type === "doubleclick") {
      if (pointIsBlocked(point.x, point.y)) return false;
      return zoomBy(1.5, [point.x, point.y], 200);
    }
    return false;
  }

  function fitPadding() {
    const width = window.innerWidth;
    const height = window.innerHeight;
    const pad = { top: 48, right: 32, bottom: 48, left: 32 };
    blockRects.forEach(function (rect) {
      if (rect.y < height * 0.25) pad.top = Math.max(pad.top, rect.y + rect.height + 12);
      if (rect.y + rect.height > height * 0.75) pad.bottom = Math.max(pad.bottom, height - rect.y + 12);
      if (rect.x < width * 0.2) pad.left = Math.max(pad.left, rect.x + rect.width + 12);
      if (rect.x + rect.width > width * 0.8) pad.right = Math.max(pad.right, width - rect.x + 12);
    });
    pad.top = Math.min(pad.top, height * 0.45);
    pad.bottom = Math.min(pad.bottom, height * 0.45);
    pad.left = Math.min(pad.left, width * 0.45);
    pad.right = Math.min(pad.right, width * 0.45);
    return pad;
  }

  function fitRoute(coords, duration) {
    if (!map || !Array.isArray(coords) || coords.length < 2) return false;
    const valid = coords.filter(function (coord) {
      return Array.isArray(coord) && coord.length >= 2 && validCoordinate(Number(coord[0]), Number(coord[1]));
    });
    if (valid.length < 2) return false;
    const bounds = new window.maplibregl.LngLatBounds(valid[0], valid[0]);
    valid.forEach(function (coord) { bounds.extend([Number(coord[0]), Number(coord[1])]); });
    stopFollow();
    map.fitBounds(bounds, {
      padding: fitPadding(), maxZoom: MAX_ZOOM, duration: Number.isFinite(Number(duration)) ? Math.max(0, Number(duration)) : 650,
      essential: true,
    });
    return true;
  }

  function followStep(timestamp) {
    followFrame = 0;
    if (!map || !followTarget) return;
    const elapsed = lastFollowTime ? Math.min(0.1, (timestamp - lastFollowTime) / 1000) : 1 / 60;
    lastFollowTime = timestamp;
    const current = map.getCenter();
    let longitudeDelta = followTarget[0] - current.lng;
    longitudeDelta = ((longitudeDelta + 540) % 360) - 180;
    const blend = 1 - Math.exp(-6.5 * Math.max(0.001, elapsed));
    const next = [current.lng + longitudeDelta * blend, current.lat + (followTarget[1] - current.lat) * blend];
    if (Math.abs(longitudeDelta) < 0.00001 && Math.abs(followTarget[1] - current.lat) < 0.00001) {
      map.jumpTo({ center: followTarget });
      return;
    }
    map.jumpTo({ center: next });
    followFrame = window.requestAnimationFrame(followStep);
  }

  function setFollowTarget(lon, lat) {
    const longitude = Number(lon);
    const latitude = Number(lat);
    if (!map || !validCoordinate(longitude, latitude)) return false;
    followTarget = [longitude, latitude];
    if (!followFrame) {
      lastFollowTime = 0;
      followFrame = window.requestAnimationFrame(followStep);
    }
    return true;
  }

  function stopFollow() {
    followTarget = null;
    lastFollowTime = 0;
    if (followFrame) window.cancelAnimationFrame(followFrame);
    followFrame = 0;
  }

  window.IDMMap = {
    isReady: function () { return ready && Boolean(map); },
    setVisible: setVisible,
    getCamera: getCamera,
    getRoadLayerWidths: function () {
      if (!map) return [];
      return map.getStyle().layers.filter(function (layer) { return layer.type === "line" && /(street|road)/i.test(layer.id); }).map(function (layer) { return { id: layer.id, width: map.getPaintProperty(layer.id, "line-width") }; }).slice(0, 50);
    },
    setView: setView,
    zoomBy: zoomBy,
    setTheme: setTheme,
    restyleRoads: applyRoadHierarchy,
    setBlockRects: setBlockRects,
    fitRoute: fitRoute,
    // GeoJSON overlay contract. Data is WGS84 [longitude, latitude]. Every
    // call replaces the whole set; stable IDs enable explicit feature identity.
    setGameplayOverlays: setGameplayOverlays,
    setRiderPositions: setRiderPositions,
    clearGameplayOverlays: clearGameplayOverlays,
    pickBookingAt: pickBookingAt,
    resolveBookingHit: bookingHitFromFeatures,
    resolveRiderHit: riderHitFromEntries,
    projectCoordinate: projectCoordinate,
    getGameplayOverlayState: gameplayOverlayState,
    getGameplayOverlaySnapshot: gameplayOverlaySnapshot,
    getOverlayRenderDiagnostics: overlayRenderDiagnostics,
    isRouteRenderedAt: routeRenderedAt,
    forwardPointerEvent: forwardPointerEvent,
    consumeTouchDoubleTap: function () { const pending = touchDoubleTapPending; touchDoubleTapPending = false; return pending; },
    setFollowTarget: setFollowTarget,
    isFollowing: function () { return Boolean(followTarget); },
    stopFollow: stopFollow,
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initMap, { once: true });
  } else {
    initMap();
  }
})(window, document);
