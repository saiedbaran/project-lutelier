const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
// Exercise the shipped viewport handlers against a lightweight geometry fixture.
// This does not drive a browser or claim touch-device validation.
const source = fs.readFileSync(__dirname + '/editor-refinements.js', 'utf8');
const start = source.indexOf('const photoPointers='), end = source.indexOf('// A single glass', start);
const handlers = {}, captures = new Set(), layer = {style: {}};
let rect = {left: 0, top: 0, width: 300, height: 300}, resize;
const photo = {getBoundingClientRect: () => rect,
  addEventListener: (name, fn) => handlers[name] = fn,
  setPointerCapture: id => captures.add(id), hasPointerCapture: id => captures.has(id),
  releasePointerCapture: id => captures.delete(id)};
const image = {naturalWidth: 200, naturalHeight: 400, addEventListener() {}};
const fixture = {photo, $: () => image, $$: () => [layer], zoom: 1, panX: 0, panY: 0, compare: false,
  boxSelecting: false, selectionBox: {style: {}, hidden: true}, depthSelection: null,
  paint() {}, performance: {now: () => 1000}, window: {addEventListener() {}},
  ResizeObserver: class {constructor(fn) {resize = fn;} observe() {}}};
vm.createContext(fixture); vm.runInContext(source.slice(start, end), fixture);
const run = code => vm.runInContext(code, fixture);
const event = (id, x, y) => ({pointerId: id, clientX: x, clientY: y, button: 0});
function covered() {
  const g = run('photoGeometry()');
  assert.ok(g.left + fixture.panX <= 1e-6);
  assert.ok(g.top + fixture.panY <= 1e-6);
  assert.ok(g.left + fixture.panX + g.iw >= g.w - 1e-6);
  assert.ok(g.top + fixture.panY + g.ih >= g.h - 1e-6);
}
handlers.pointerdown(event(1, 150, 100)); handlers.pointermove(event(1, 150, 200));
assert.equal(fixture.zoom, 1); assert.equal(fixture.panY, 100); covered();
assert.equal(layer.style.height, "600px"); // Full image, rather than a pre-cropped 300px element.
assert.equal(layer.style.transform, "translate(0px,100px)");
handlers.pointermove(event(1, 150, 300)); assert.equal(fixture.panY, 135); covered();
handlers.pointercancel(event(1, 150, 300)); assert.equal(captures.size, 0);
fixture.panY = 0;
handlers.pointerdown(event(1, 100, 150)); handlers.pointerdown(event(2, 200, 150));
handlers.pointermove(event(1, 50, 150)); handlers.pointermove(event(2, 250, 150));
assert.equal(fixture.zoom, 2); covered();
assert.ok(Math.abs(run('(150-photoGeometry().top-panY)/photoGeometry().ih') - 0.475) < 1e-6);
handlers.pointerup(event(2, 250, 150)); const oldPan = fixture.panY;
handlers.pointermove(event(1, 50, 190)); assert.equal(fixture.panY, oldPan + 40);
handlers.pointerup(event(1, 50, 190));
fixture.paint(); const before = run('(photoGeometry().h/2-photoGeometry().top-panY)/photoGeometry().ih');
rect = {...rect, height: 220}; resize(); covered();
assert.ok(Math.abs(run('(photoGeometry().h/2-photoGeometry().top-panY)/photoGeometry().ih') - before) < 1e-6);
image.naturalWidth = 600; image.naturalHeight = 200; fixture.zoom = 1; fixture.panX = 10000; fixture.panY = -10000;
run('clampPhotoPan()'); covered();
console.log('Viewport regression checks passed: 1x crop pan, bounds, pinch anchor, pinch-to-pan, cancellation, resize continuity.');
