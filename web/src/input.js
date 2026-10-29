// Input: keyboard, mouse (pointer lock) and gamepad, with Grove-style named actions.
const down = new Set(), pressed = new Set();
let mdx = 0, mdy = 0, wheel = 0, mouseDown = false, mousePressed = false;
let pad = null, padPrev = {};
let canvas = null;

const bindings = {
  move_left: ['KeyA', 'ArrowLeft'], move_right: ['KeyD', 'ArrowRight'],
  move_forward: ['KeyW', 'ArrowUp'], move_back: ['KeyS', 'ArrowDown'],
  jump: ['Space'], sprint: ['ShiftLeft', 'ShiftRight'], pause: ['Escape', 'KeyP'], ui_accept: ['Enter'],
};
// Standard gamepad mapping.
const padButtons = { jump: [0], sprint: [10, 4], fire: [7], pause: [9], ui_accept: [0] };

export function initInput(c) {
  canvas = c;
  addEventListener('keydown', (e) => {
    if (e.code === 'Space' || e.code === 'F3' || e.code.startsWith('Arrow')) e.preventDefault();
    if (!down.has(e.code)) pressed.add(e.code);
    down.add(e.code);
  });
  addEventListener('keyup', (e) => down.delete(e.code));
  addEventListener('blur', () => { down.clear(); mouseDown = false; });
  addEventListener('mousemove', (e) => { if (document.pointerLockElement) { mdx += e.movementX; mdy += e.movementY; } });
  canvas.addEventListener('mousedown', (e) => { if (e.button === 0) { mouseDown = true; mousePressed = true; } });
  addEventListener('mouseup', (e) => { if (e.button === 0) mouseDown = false; });
  addEventListener('wheel', (e) => { wheel += e.deltaY < 0 ? 1 : e.deltaY > 0 ? -1 : 0; }, { passive: true });
}

function padAxis(i) { const v = pad ? pad.axes[i] || 0 : 0; return Math.abs(v) < 0.18 ? 0 : v; }
function padBtn(i) { return !!(pad && pad.buttons[i] && pad.buttons[i].pressed); }

export const Input = {
  // Call once per frame before game logic.
  poll() {
    pad = null;
    for (const p of (navigator.getGamepads ? navigator.getGamepads() : [])) if (p && p.connected) { pad = p; break; }
  },
  // Call once per frame after game logic.
  endFrame() {
    pressed.clear(); mdx = 0; mdy = 0; wheel = 0; mousePressed = false;
    padPrev = {};
    if (pad) pad.buttons.forEach((b, i) => { padPrev[i] = b.pressed; });
  },
  key(code) { return down.has(code); },
  keyPressed(code) { return pressed.has(code); },
  down(action) {
    if ((bindings[action] || []).some((k) => down.has(k))) return true;
    if (action === 'fire' && mouseDown && document.pointerLockElement) return true;
    return (padButtons[action] || []).some(padBtn);
  },
  pressed(action) {
    if ((bindings[action] || []).some((k) => pressed.has(k))) return true;
    return (padButtons[action] || []).some((i) => padBtn(i) && !padPrev[i]);
  },
  strength(action) {
    if ((bindings[action] || []).some((k) => down.has(k))) return 1;
    const lx = padAxis(0), ly = padAxis(1);
    if (action === 'move_left') return Math.max(0, -lx) || (padBtn(14) ? 1 : 0);
    if (action === 'move_right') return Math.max(0, lx) || (padBtn(15) ? 1 : 0);
    if (action === 'move_forward') return Math.max(0, -ly) || (padBtn(12) ? 1 : 0);
    if (action === 'move_back') return Math.max(0, ly) || (padBtn(13) ? 1 : 0);
    return 0;
  },
  vector(l, r, f, b) {
    let x = Input.strength(r) - Input.strength(l), y = Input.strength(f) - Input.strength(b);
    const len = Math.hypot(x, y);
    if (len > 1) { x /= len; y /= len; }
    return [x, y];
  },
  lookStick() { return [padAxis(2), padAxis(3)]; },
  mouseDelta() { return [mdx, mdy]; },
  mouseWheel() { return wheel; },
  mousePressed() { return mousePressed; },
  hasPad() { return !!pad; },
  captureMouse(on) {
    if (on && !document.pointerLockElement) { const p = canvas.requestPointerLock(); if (p && p.catch) p.catch(() => {}); }
    if (!on && document.pointerLockElement) document.exitPointerLock();
  },
  isMouseCaptured() { return !!document.pointerLockElement; },
};
