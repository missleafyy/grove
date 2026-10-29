// HUD, title screen, pause menu and victory panel (port of hud.lua, as an HTML overlay).
import { Ease, damp } from './core.js';
import { G } from './game.js';
import { Input } from './input.js';
import { Audio } from './audio.js';
import { SFX } from './sfx.js';

const $ = (id) => document.getElementById(id);

export function createHud(ctl) {
  const hud = { hintAlpha: 1, pop: 0, toasts: [] };

  // Title letters, each waving on its own phase.
  const logo = $('logo');
  const letters = [...'GROVE'].map((ch) => { const s = document.createElement('span'); s.textContent = ch; logo.appendChild(s); return s; });

  for (const b of document.querySelectorAll('button.gb')) {
    b.addEventListener('mouseenter', () => Audio.play(SFX.hover, { volume: 0.5 }));
    b.addEventListener('click', () => { Audio.play(SFX.click, { volume: 0.6 }); b.blur(); });
  }
  const toggleFull = () => {
    if (document.fullscreenElement) document.exitFullscreen();
    else document.documentElement.requestFullscreen?.().catch(() => {});
  };
  $('b-play').onclick = () => ctl.startPlay();
  $('b-full').onclick = toggleFull;
  $('b-full2').onclick = toggleFull;
  $('b-resume').onclick = () => ctl.resume();
  $('b-keep').onclick = () => ctl.closeVictory();
  const label = (name, on) => `${name}:  ${on ? 'On' : 'Off'}`;
  $('b-fast').onclick = () => { ctl.daynight.fast = !ctl.daynight.fast; $('b-fast').textContent = label('Time-lapse', ctl.daynight.fast); };
  $('b-shadows').onclick = () => { ctl.shadows = !ctl.shadows; ctl.daynight.light.castShadow = ctl.shadows; $('b-shadows').textContent = label('Shadows', ctl.shadows); };
  $('b-bloom').onclick = () => { ctl.daynight.bloomEnabled = !ctl.daynight.bloomEnabled; $('b-bloom').textContent = label('Bloom', ctl.daynight.bloomEnabled); };
  $('total').textContent = '/ ' + ctl.total;

  hud.toast = (text, sub) => {
    const el = document.createElement('div');
    el.className = 'toast panel';
    el.innerHTML = '<b class="shadow"></b>' + (sub ? '<small></small>' : '');
    el.querySelector('b').textContent = text;
    if (sub) el.querySelector('small').textContent = sub;
    $('toasts').prepend(el);
    hud.toasts.push({ el, t: 0 });
  };
  hud.popCounter = () => { hud.pop = 1; };
  hud.show = (on) => { $('hud').style.opacity = on ? 1 : 0; };
  hud.hideTitle = () => { $('title').style.opacity = 0; setTimeout(() => { $('title').style.display = 'none'; }, 450); };
  hud.showPause = (on) => { $('pause').style.display = on ? 'block' : 'none'; };
  hud.showVictory = (on, timeText) => {
    const v = $('victory');
    if (on) {
      $('v-time').textContent = timeText;
      v.style.display = 'flex';
      requestAnimationFrame(() => { v.style.opacity = 1; });
    } else {
      v.style.opacity = 0;
      setTimeout(() => { v.style.display = 'none'; }, 350);
    }
  };

  let statsOn = false, fpsAcc = 0, fpsN = 0, fps = 0;
  hud.update = (dt, info) => {
    const t = G.realTime;
    if (ctl.state === 'title') {
      letters.forEach((s, i) => {
        const k = (Math.sin(t + i + 1) + 1) * 0.25;
        s.style.transform = `translateY(${(Math.sin(t * 2 + (i + 1) * 0.6) * 5 + Math.sin(t * 1.3) * 4).toFixed(2)}px)`;
        s.style.color = `rgb(${Math.round(255 + (126 - 255) * k)},${Math.round(246 + (224 - 246) * k)},${Math.round(224 + (180 - 224) * k)})`;
      });
      return;
    }
    // Crystal counter.
    hud.pop = Math.max(0, hud.pop - dt * 2.5);
    $('count').textContent = ctl.collected;
    $('count').style.transform = `scale(${1 + hud.pop * 0.2}) translateY(${-hud.pop * 3}px)`;

    // Clock.
    $('time').textContent = ctl.daynight.clockText();
    $('sun').className = ctl.daynight.night > 0.5 ? 'moon' : '';
    $('lapse').style.display = ctl.daynight.timeLapse() ? 'block' : 'none';

    $('crosshair').style.display = Input.isMouseCaptured() ? 'block' : 'none';
    $('clickhint').style.display = ctl.state === 'play' && !Input.isMouseCaptured() && !Input.hasPad() && !ctl.victoryOpen ? 'block' : 'none';

    // Controls hint, fades out after a while (H to show again).
    if (Input.keyPressed('KeyH')) ctl.hintTime = G.realTime;
    const age = G.realTime - (ctl.hintTime || 0);
    hud.hintAlpha = damp(hud.hintAlpha, age < 18 ? 1 : 0, 3, dt);
    $('hints').style.opacity = hud.hintAlpha.toFixed(3);

    // Toasts, newest on top, slide in from above.
    for (let i = hud.toasts.length - 1; i >= 0; i--) {
      const ts = hud.toasts[i];
      ts.t += dt;
      if (ts.t > 3.2) { ts.el.remove(); hud.toasts.splice(i, 1); continue; }
      const a = Math.min(1, ts.t * 5) * Math.min(1, (3.2 - ts.t) * 2);
      const slide = (1 - Ease.out_cubic(Math.min(1, ts.t * 4))) * -30;
      ts.el.style.opacity = a.toFixed(3);
      ts.el.style.transform = `translateY(${slide.toFixed(1)}px)`;
    }

    // F3: engine stats.
    if (Input.keyPressed('F3')) statsOn = !statsOn;
    fpsAcc += dt; fpsN++;
    if (fpsAcc > 0.5) { fps = fpsN / fpsAcc; fpsAcc = 0; fpsN = 0; }
    $('stats').style.display = statsOn ? 'block' : 'none';
    if (statsOn) $('stats').textContent = `${fps.toFixed(0)} fps\n${info.calls} draw calls\n${info.tris} triangles\n${info.bodies} physics bodies\n${info.particles} particles`;
  };
  return hud;
}
