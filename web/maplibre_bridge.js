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
 * - The OSMF Shortbread style URLs are public services, not an SLA or a promise
 *   of unlimited traffic. Review OSMF vector-tile terms/capacity before scaling
 *   production traffic and retain visible OSM attribution.
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

  let map = null;
  let mapRoot = null;
  let ready = false;
  let themeMode = "dark";
  let appliedTheme = "dark";
  let roadsRestyled = false;
  let blockRects = [];
  let mapLoadAttempts = 0;
  let followTarget = null;
  let followFrame = 0;
  let lastFollowTime = 0;
  const blockedPointers = new Set();
  const activePointers = new Map();
  const activeTouches = new Map();
  let lastTouchTap = null;
  let touchDoubleTapPending = false;
  let canvasEventsBound = false;

  function ensureRoot() {
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
        // from this production origin. Keep its required source attribution
        // expanded so it remains legible on mobile.
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
      map.addControl(new window.maplibregl.AttributionControl({ compact: false }), "top-left");
      appliedTheme = themeMode;

      map.touchZoomRotate.disableRotation();
      map.on("load", function () {
        ready = true;
        emit("idm-map-ready", getCamera());
      });
      map.on("style.load", function () {
        roadsRestyled = false;
        if (map) {
          ready = true;
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
    canvas.addEventListener("pointerdown", function (event) { forwardPointerEvent(event); }, { capture: true, passive: true });
    window.addEventListener("pointermove", function (event) { forwardPointerEvent(event); }, { capture: true, passive: true });
    window.addEventListener("pointerup", function (event) { forwardPointerEvent(event); }, { capture: true, passive: true });
    window.addEventListener("pointercancel", function (event) { forwardPointerEvent(event); }, { capture: true, passive: true });
    canvas.addEventListener("dblclick", function (event) { forwardPointerEvent(event); }, { capture: true });
    canvas.addEventListener("wheel", function (event) {
      const handled = forwardPointerEvent(event);
      if (handled) event.preventDefault();
    }, { capture: true, passive: false });
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
    map.setStyle(STYLE_URLS[mode], { diff: false });
    appliedTheme = mode;
    return true;
  }

  function setVisible(visible) {
    const root = ensureRoot();
    const display = visible ? "block" : "none";
    const changed = root.style.display !== display;
    if (!changed) return true;
    root.style.display = display;
    if (visible && map) {
      window.requestAnimationFrame(function () {
        if (!map || root.style.display === "none") return;
        map.resize();
        if (map.isStyleLoaded()) ready = true;
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
