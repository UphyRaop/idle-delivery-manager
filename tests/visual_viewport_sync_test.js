const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const htmlPath = process.argv[2] || 'build/web/index.html';
const html = fs.readFileSync(htmlPath, 'utf8');
const scriptMatch = html.match(/<script id="idm-visual-viewport">([\s\S]*?)<\/script>/);
assert.ok(scriptMatch, 'export includes the visual viewport synchronizer');
assert.match(html, /viewport-fit=cover/, 'viewport allows edge-to-edge safe-area rendering');
assert.match(html, /--idm-viewport-height, 100dvh/, 'canvas and map use the synchronized height with a dynamic viewport fallback');
assert.match(html, /--idm-safe-bottom:\s*env\(safe-area-inset-bottom/, 'safe-area inset remains independently available to Godot UI');

function harness() {
  const rootStyle = new Map();
  const listeners = new Map();
  const vvListeners = new Map();
  const documentListeners = new Map();
  const queue = [];
  let resizeEvents = 0;
  const viewport = { width: 390, height: 760, offsetLeft: 0, offsetTop: 20, scale: 1,
    addEventListener(type, fn) { vvListeners.set(type, fn); } };
  const root = { style: {
    setProperty(key, value) { rootStyle.set(key, value); },
    removeProperty(key) { rootStyle.delete(key); },
  } };
  const window = {
    innerWidth: 390, innerHeight: 844, visualViewport: viewport,
    addEventListener(type, fn) { listeners.set(type, fn); },
    dispatchEvent() { resizeEvents++; },
  };
  const document = { documentElement: root, hidden: false,
    addEventListener(type, fn) { documentListeners.set(type, fn); } };
  const context = {
    window, document, Event: class {},
    requestAnimationFrame(fn) { queue.push(fn); return queue.length; },
    cancelAnimationFrame() {},
  };
  vm.runInNewContext(scriptMatch[1], context);
  const flush = () => { while (queue.length) queue.shift()(); };
  flush();
  return { window, viewport, rootStyle, listeners, vvListeners, documentListeners, flush, get resizeEvents() { return resizeEvents; } };
}

const test = harness();
assert.equal(test.window.innerHeight, 760, 'initial reduced Safari viewport is reflected to Godot');
assert.equal(test.rootStyle.get('--idm-viewport-top'), '20px', 'visual viewport top offset is applied');
assert.equal(test.rootStyle.get('--idm-viewport-height'), '760px', 'canvas and map are sized to the visible viewport');
assert.ok(test.resizeEvents > 0, 'initial viewport correction notifies Godot and MapLibre');

test.viewport.height = 800;
test.vvListeners.get('resize')();
test.flush();
assert.equal(test.window.innerHeight, 800, 'browser toolbar resizing updates the Godot viewport');
assert.equal(test.rootStyle.get('--idm-viewport-height'), '800px', 'map follows the resized viewport');

test.viewport.height = 844;
test.viewport.offsetTop = 0;
test.vvListeners.get('resize')();
test.flush();
assert.equal(test.window.innerHeight, 844, 'full viewport restores the original browser dimension');
assert.equal(test.rootStyle.has('--idm-viewport-height'), false, 'temporary viewport sizing is removed when no longer needed');

test.viewport.width = 844;
test.viewport.height = 390;
test.listeners.get('orientationchange')();
test.flush();
assert.equal(test.window.innerWidth, 844, 'orientation change updates Godot viewport width');
assert.equal(test.window.innerHeight, 390, 'orientation change updates Godot viewport height');
assert.equal(test.rootStyle.get('--idm-viewport-height'), '390px', 'map follows the landscape visual viewport');

// Home Screen resume may change the visible size without a normal resize event.
test.viewport.width = 430;
test.viewport.height = 932;
test.listeners.get('pageshow')();
test.flush();
assert.equal(test.rootStyle.has('--idm-viewport-width'), false, 'a full standalone viewport restores the natural full-screen layout');
assert.equal(test.window.innerWidth, 390, 'resume restores the original browser width descriptor');
assert.equal(test.window.innerHeight, 844, 'resume restores the original browser height descriptor');
console.log('VISUAL VIEWPORT SYNC RESULT: 18 passed, 0 failed');
