const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

let passed = 0;
const check = (condition, message) => { assert.ok(condition, message); passed++; };
const equal = (actual, expected, message) => { assert.equal(actual, expected, message); passed++; };
const htmlPath = process.argv[2] || 'build/web/index.html';
const html = fs.readFileSync(htmlPath, 'utf8');
const scriptMatch = html.match(/<script id="idm-visual-viewport">([\s\S]*?)<\/script>/);
check(!!scriptMatch, 'export includes the visual viewport synchronizer');
check(/viewport-fit=cover/.test(html), 'viewport allows edge-to-edge safe-area rendering');
check(/html, body\s*\{[^}]*height:\s*100%/s.test(html), 'shell uses the full-height OBT layout baseline');
check(/#canvas\s*\{[^}]*position:\s*absolute;[^}]*inset:\s*0;[^}]*height:\s*100%/s.test(html), 'Godot canvas fills the shell without excluding system areas');
check(/height < layoutHeight - 80/.test(html), 'visual viewport resizing is limited to substantial obstructions as in OBT');
check(/html\.idm-uses-visual-viewport #canvas/.test(html), 'reduced dimensions apply only when an obstruction is detected');
check(/--idm-safe-bottom:\s*env\(safe-area-inset-bottom/.test(html), 'safe-area inset remains independently available to Godot UI');
const bridgeCss = fs.readFileSync('web/maplibre_bridge.css', 'utf8');
check(/#idm-map-root\s*\{[^}]*position:\s*fixed;[^}]*inset:\s*0;/s.test(bridgeCss), 'map background extends to all viewport edges');
check(!/#idm-map-root\s*\{[^}]*height:\s*100dvh/s.test(bridgeCss), 'map does not use a second dynamic viewport height rule');

function harness() {
  const rootStyle = new Map();
  const listeners = new Map();
  const vvListeners = new Map();
  const queue = [];
  let resizeEvents = 0;
  const viewport = { width: 390, height: 800, offsetLeft: 0, offsetTop: 0, scale: 1,
    addEventListener(type, fn) { vvListeners.set(type, fn); } };
  const root = { style: {
    setProperty(key, value) { rootStyle.set(key, value); },
    removeProperty(key) { rootStyle.delete(key); },
  }, classList: {
    values: new Set(),
    add(value) { this.values.add(value); },
    remove(value) { this.values.delete(value); },
  } };
  const window = {
    innerWidth: 390, innerHeight: 844, visualViewport: viewport,
    addEventListener(type, fn) { listeners.set(type, fn); },
    dispatchEvent() { resizeEvents++; },
  };
  const document = { documentElement: root, hidden: false,
    addEventListener(type, fn) { listeners.set(`document:${type}`, fn); } };
  const context = { window, document, Event: class {},
    requestAnimationFrame(fn) { queue.push(fn); return queue.length; },
    cancelAnimationFrame() {} };
  vm.runInNewContext(scriptMatch[1], context);
  const flush = () => { while (queue.length) queue.shift()(); };
  flush();
  return { window, viewport, rootStyle, root, listeners, vvListeners, flush, get resizeEvents() { return resizeEvents; } };
}

const test = harness();
equal(test.window.innerHeight, 844, 'small browser-chrome/safe-area differences do not shrink the full-height game');
equal(test.rootStyle.has('--idm-viewport-height'), false, 'small viewport differences do not add another content inset');
check(test.resizeEvents > 0, 'initial viewport check notifies Godot and MapLibre');

test.viewport.height = 700;
test.vvListeners.get('resize')();
test.flush();
equal(test.window.innerHeight, 700, 'substantial browser obstruction updates Godot viewport');
equal(test.rootStyle.get('--idm-viewport-height'), '700px', 'map follows the reduced visual viewport during an obstruction');
check(test.root.classList.values.has('idm-uses-visual-viewport'), 'canvas and map enter the shared reduced viewport mode');

test.viewport.height = 790;
test.vvListeners.get('resize')();
test.flush();
equal(test.window.innerHeight, 844, 'viewport restoration restores Godot dimensions');
equal(test.rootStyle.has('--idm-viewport-height'), false, 'temporary viewport sizing is removed after obstruction');
equal(test.root.classList.values.has('idm-uses-visual-viewport'), false, 'full-height shell becomes active after restoration');

test.viewport.width = 844;
test.viewport.height = 390;
test.listeners.get('orientationchange')();
test.flush();
equal(test.window.innerWidth, 844, 'orientation changes update Godot viewport width');
equal(test.window.innerHeight, 390, 'orientation changes update Godot viewport height');
equal(test.rootStyle.get('--idm-viewport-height'), '390px', 'map follows landscape visual viewport');

test.viewport.width = 390;
test.viewport.height = 844;
test.viewport.offsetTop = 20;
test.vvListeners.get('scroll')();
test.flush();
equal(test.rootStyle.get('--idm-viewport-top'), '20px', 'shifted visual viewport offset is applied');
equal(test.window.innerHeight, 844, 'offset-only sync does not shorten game height');
test.viewport.offsetTop = 0;
test.vvListeners.get('scroll')();
test.flush();
equal(test.rootStyle.has('--idm-viewport-top'), false, 'temporary offset is removed when viewport returns');

test.viewport.width = 430;
test.viewport.height = 932;
test.listeners.get('pageshow')();
test.flush();
equal(test.rootStyle.has('--idm-viewport-width'), false, 'standalone resume restores natural full-screen layout');
equal(test.window.innerWidth, 390, 'resume restores original browser width descriptor');
equal(test.window.innerHeight, 844, 'resume restores original browser height descriptor');
console.log(`VISUAL VIEWPORT SYNC RESULT: ${passed} passed, 0 failed`);
