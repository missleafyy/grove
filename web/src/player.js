// Sprig, the player character: third-person platformer controller with procedural animation,
// plus the follow camera rig (port of player.lua).
import * as THREE from 'three';
import { Col, V, euler, fromY, rng, clamp, damp, lerp, lerpAngle, lookRotation, TAU } from './core.js';
import * as Art from './art.js';
import * as Props from './props.js';
import { mi, node } from './props.js';
import { Character, raycast } from './physics.js';
import { G, add, after } from './game.js';
import { Input } from './input.js';
import { Audio } from './audio.js';
import { SFX } from './sfx.js';

export const WATER_LEVEL = 0;

export class Player {
  constructor(parent, pos, M) {
    this.parent = parent;
    this.radius = 0.42; this.height = 1.25;
    this.speed = 7; this.sprintSpeed = 11.5; this.accel = 70; this.airAccel = 22;
    this.jumpVelocity = 10.5; this.gravity = 28; this.coyoteTime = 0.12; this.bufferTime = 0.15;
    this.locked = true;
    this.coyote = 0; this.buffer = 0; this.canDouble = true;
    this.walk = 0; this.squash = 0; this.squashV = 0; this.yaw = 0;
    this.leaf = 0; this.leafV = 0; this.blink = 3; this.shootCd = 0;
    this.wasFloor = true; this.fallSpeed = 0; this.lastSpeed = 0; this.safeTimer = 0;
    this.velocity = V(0, 0, 0);
    this.wish = V(0, 0, 0);
    this.char = new Character(pos, this.radius, this.height, 0.3, 48);
    this.safePosition = pos.clone();

    const parts = Art.playerParts();
    this.visual = add(parent, node(pos));
    this.bodyPivot = add(this.visual, node(V(0, 0.62, 0)));
    add(this.bodyPivot, mi(parts.body, M.player));
    const face = add(this.bodyPivot, node());
    this.eyes = [];
    for (const side of [-1, 1]) {
      const eye = add(face, mi(parts.eye, M.eye, { position: V(side * 0.17, 0.08, -0.43), rotation: euler(0, side * 0.32, 0) }));
      add(eye, mi(parts.shine, M.eye_shine, { position: V(0.02, 0.04, -0.04), cast_shadow: false }));
      this.eyes.push(eye);
      add(face, mi(parts.cheek, M.player, { position: V(side * 0.3, -0.06, -0.37), rotation: euler(0, side * 0.6, 0), cast_shadow: false }));
    }
    this.sprout = add(this.bodyPivot, mi(parts.sprout, M.player, { position: V(0, 0.42, 0.02) }));
    this.feet = [-1, 1].map((side) => add(this.visual, mi(parts.foot, M.player, { position: V(side * 0.2, 0.09, 0) })));
  }
  get position() { return this.char.position; }
  isOnFloor() { return this.char.grounded; }
  teleport(p) { this.char.teleport(p); this.velocity.set(0, 0, 0); this.visual.position.copy(p); }

  // Called by jump pads.
  launch(strength) {
    this.velocity.y = strength;
    this.launched = true;
    this.canDouble = true;
    this.coyote = 0;
    this.char.grounded = false;
    this.kickSquash(-0.35);
  }
  kickSquash(a) { this.squashV += a * 12; }

  physics(dt) {
    const rig = this.rig;
    let ix = 0, iy = 0;
    const controllable = !this.locked && !this.respawning;
    if (controllable) [ix, iy] = Input.vector('move_left', 'move_right', 'move_forward', 'move_back');
    const yaw = rig ? rig.yaw : 0;
    const fwd = V(-Math.sin(yaw), 0, -Math.cos(yaw)), right = V(Math.cos(yaw), 0, -Math.sin(yaw));
    const wish = right.multiplyScalar(ix).addScaledVector(fwd, iy);
    this.wish = wish;

    const onFloor = this.isOnFloor();
    const v = this.velocity;
    const sprint = Input.down('sprint');
    const target = wish.clone().multiplyScalar(sprint ? this.sprintSpeed : this.speed);
    const hv = V(v.x, 0, v.z);
    const diff = target.clone().sub(hv), dl = diff.length(), step = (onFloor ? this.accel : this.airAccel) * dt;
    if (dl <= step) hv.copy(target); else hv.addScaledVector(diff, step / dl);
    let vy = v.y;

    if (onFloor) {
      this.coyote = this.coyoteTime;
      this.canDouble = true;
      this.launched = false;
      if (vy < 0) vy = 0;
    } else {
      this.coyote -= dt;
      let g = this.gravity;
      if (vy < 0) g *= 1.5;
      else if (!Input.down('jump') && !this.launched) g *= 2.2;   // short hop when released
      vy = Math.max(vy - g * dt, -45);
    }

    const jumpPressed = controllable && Input.pressed('jump');
    this.buffer = jumpPressed ? this.bufferTime : this.buffer - dt;
    if (this.buffer > 0 && this.coyote > 0) {
      vy = this.jumpVelocity;
      this.buffer = 0; this.coyote = 0;
      Audio.play(SFX.jump, { volume: 0.5, pitch: rng.float(0.95, 1.08) });
      this.kickSquash(-0.3);
    } else if (jumpPressed && !onFloor && this.canDouble && this.coyote <= 0) {
      vy = this.jumpVelocity * 0.92;
      this.canDouble = false;
      this.spin = 1;
      Audio.play(SFX.double_jump, { volume: 0.45 });
      Props.burst(this.parent, this.position.clone().add(V(0, 0.3, 0)), Col.hex('#c8ffe4'), 18, 3);
      this.kickSquash(-0.25);
    }

    this.velocity.set(hv.x, vy, hv.z);
    // Leaving the ground on purpose shouldn't be undone by snap-to-ground.
    if (vy > 0) this.char.cc.disableSnapToGround(); else this.char.cc.enableSnapToGround(0.3);
    this.char.move(this.velocity, dt);
    if (this.char.hitCeiling) this.velocity.y = Math.min(this.velocity.y, 0);
    // Rising after a jump: the controller can still report ground contact for a frame.
    if (vy > 0.01) this.char.grounded = false;

    const nowFloor = this.isOnFloor();
    if (nowFloor && !this.wasFloor) {
      const impact = -this.fallSpeed;
      if (impact > 6) {
        this.kickSquash(Math.min(impact / 30, 0.45));
        Audio.play(SFX.land, { volume: clamp(impact / 25, 0.2, 0.7) });
        Props.dust(this.parent, this.position.clone().add(V(0, 0.1, 0)));
      }
    }
    this.fallSpeed = this.velocity.y;
    this.wasFloor = nowFloor;
    if (nowFloor && this.position.y > WATER_LEVEL + 1 && this.char.floorNormal.y > 0.8) {
      this.safeTimer += dt;
      if (this.safeTimer > 0.5) { this.safePosition.copy(this.position); this.safeTimer = 0; }
    }

    // Fell into the sea or off the world: splash and respawn.
    if (this.position.y < WATER_LEVEL - 0.8 && !this.respawning) {
      this.respawning = true;
      Audio.play(SFX.splash, { volume: 0.7 });
      Props.splash(this.parent, V(this.position.x, WATER_LEVEL, this.position.z));
      after(0.6, () => {
        this.teleport(this.safePosition.clone().add(V(0, 0.5, 0)));
        this.respawning = false;
        Props.burst(this.parent, this.position.clone().add(V(0, 0.6, 0)), Col.hex('#c8ffe4'), 25, 3);
      });
    }

    // Throw spark orbs toward where the camera is aiming.
    this.shootCd -= dt;
    if (controllable && Input.down('fire') && this.shootCd <= 0 && rig) {
      this.shootCd = 0.22;
      const aim = rig.aimForward();
      const flat = V(aim.x, 0, aim.z).normalize();
      const origin = this.position.clone().add(V(0, 1.0, 0)).addScaledVector(flat, 0.7);
      const cam = rig.camera.getWorldPosition(V());
      const hit = raycast(cam, cam.clone().addScaledVector(aim, 120), this.char.col);
      const targetPt = hit ? hit.position : cam.clone().addScaledVector(aim, 120);
      const dir = targetPt.sub(origin).normalize();
      const vel = dir.multiplyScalar(24).add(V(0, 2.5, 0)).addScaledVector(V(this.velocity.x, 0, this.velocity.z), 0.4);
      Props.sparkOrb(this.parent, origin, vel);
      Audio.play(SFX.shoot, { volume: 0.35, pitch: rng.float(0.9, 1.1) });
      this.kickSquash(0.08);
    }
  }

  process(dt) {
    this.visual.position.copy(this.position);
    const speed = Math.hypot(this.velocity.x, this.velocity.z);
    const onFloor = this.isOnFloor();

    // Face the movement direction.
    if (this.wish.length() > 0.1) this.yaw = lerpAngle(this.yaw, Math.atan2(-this.wish.x, -this.wish.z), 1 - Math.exp(-14 * dt));
    let spin = 0;
    if (this.spin) {
      this.spin -= dt * 2.6;
      if (this.spin <= 0) this.spin = null; else spin = (1 - this.spin) * TAU;
    }
    this.visual.quaternion.copy(fromY(this.yaw + spin));

    // Squash and stretch spring.
    const k = 260, d = 16;
    this.squashV += (-k * this.squash - d * this.squashV) * dt;
    this.squash += this.squashV * dt;
    const airStretch = onFloor ? 0 : clamp(this.velocity.y / 60, -0.12, 0.12);
    const s = this.squash - airStretch;
    const breathe = onFloor && speed < 0.5 ? Math.sin(G.time * 2.6) * 0.015 : 0;
    this.bodyPivot.scale.set(1 + s * 0.6, 1 - s + breathe, 1 + s * 0.6);

    // Walk cycle: feet swing, body bobs and leans into the motion.
    if (onFloor && speed > 0.3) {
      const prev = this.walk;
      this.walk += dt * (4 + speed * 1.15);
      if (Math.floor(prev / Math.PI) !== Math.floor(this.walk / Math.PI)) Audio.play(SFX.step, { volume: 0.18, pitch: rng.float(0.9, 1.15) });
    } else {
      this.walk += (Math.floor(this.walk / Math.PI + 0.5) * Math.PI - this.walk) * Math.min(1, dt * 10);
    }
    const w = this.walk;
    const amp = clamp(speed / 7, 0, 1.3);
    const bob = onFloor ? Math.abs(Math.sin(w)) * 0.07 * amp : 0;
    const lean = clamp(speed / this.sprintSpeed, 0, 1) * 0.18;
    this.bodyPivot.position.set(0, 0.62 + bob, 0);
    this.bodyPivot.quaternion.copy(euler(-lean, 0, Math.sin(w) * 0.05 * amp));
    this.feet.forEach((foot, i) => {
      const ph = w + (i === 0 ? 0 : Math.PI), side = i === 0 ? -1 : 1;
      if (onFloor) foot.position.set(side * 0.2, 0.09 + Math.max(0, Math.sin(ph)) * 0.16 * amp, -Math.cos(ph) * 0.22 * amp);
      else foot.position.set(side * 0.22, 0.2, 0.05);
    });

    // Leaf sprout wobbles with acceleration.
    const acc = (speed - this.lastSpeed) / Math.max(dt, 1e-4);
    this.lastSpeed = speed;
    this.leafV += (-90 * this.leaf - 6 * this.leafV + acc * 0.05 - (onFloor ? 0 : this.velocity.y * 0.4)) * dt;
    this.leaf = clamp(this.leaf + this.leafV * dt, -0.7, 0.7);
    this.sprout.quaternion.copy(euler(this.leaf, 0, Math.sin(G.time * 1.7) * 0.06));

    // Blink.
    this.blink -= dt;
    const eyeY = this.blink < 0.12 ? 0.15 : 1;
    if (this.blink < 0) this.blink = rng.float(2, 5);
    for (const e of this.eyes) e.scale.set(1, eyeY, 1);
  }
}

// ------------------------------------------------------------------ camera rig
export class CameraRig {
  constructor(scene, target, camera) {
    this.target = target;
    this.yaw = 0.4; this.pitch = -0.32;
    this.distance = 7.5; this.targetDistance = 7.5;
    this.mode = 'orbit';
    this.sensitivity = 0.0026;
    this.orbitCenter = V(0, 6, 0);
    this.orbitT = 0;
    this.focus = null;
    this.node = new THREE.Object3D();
    scene.add(this.node);
    this.camera = camera;
    this.node.add(camera);
    camera.position.set(0, 0, this.distance);
    this.shakeAmt = 0;
  }
  get position() { return this.node.position; }
  get rotation() { return this.node.quaternion; }
  aimForward() { return V(0, 0, -1).applyQuaternion(this.camera.getWorldQuaternion(new THREE.Quaternion())); }
  shake(a) { this.shakeAmt = Math.max(this.shakeAmt, a); }

  process(dt) {
    this.shakeAmt = Math.max(0, this.shakeAmt - dt * 1.5);
    if (this.mode === 'fly') return;
    if (this.mode === 'orbit') {
      this.orbitT += dt * 0.05;
      const a = this.orbitT + 2.2;
      const pos = this.orbitCenter.clone().add(V(Math.sin(a) * 70, 32, Math.cos(a) * 70));
      this.node.position.copy(pos);
      this.node.quaternion.copy(lookRotation(this.orbitCenter.clone().add(V(0, -4, 0)).sub(pos)));
      this.camera.position.set(0, 0, 0);
      return;
    }
    const p = this.target;
    if (Input.isMouseCaptured()) {
      const [dx, dy] = Input.mouseDelta();
      this.yaw -= dx * this.sensitivity;
      this.pitch -= dy * this.sensitivity;
    }
    const [sx, sy] = Input.lookStick();
    this.yaw -= sx * 2.6 * dt;
    this.pitch -= sy * 1.8 * dt;
    this.pitch = clamp(this.pitch, -1.25, 0.55);
    const wheel = Input.mouseWheel();
    if (wheel !== 0) this.targetDistance = clamp(this.targetDistance - wheel * 0.8, 3, 16);

    // Follow with softer vertical smoothing so jumps don't jerk the view.
    const goal = p.position.clone().add(V(0, 1.25, 0));
    const f = this.focus || goal;
    const k = 1 - Math.exp(-18 * dt);
    this.focus = V(f.x + (goal.x - f.x) * k, damp(f.y, goal.y, p.isOnFloor() ? 10 : 4, dt), f.z + (goal.z - f.z) * k);

    const rot = fromY(this.yaw).multiply(euler(this.pitch, 0, 0));
    // Spring arm: pull the camera in when terrain or props are in the way.
    let want = this.targetDistance;
    const back = V(0, 0, 1).applyQuaternion(rot);
    const hit = raycast(this.focus, this.focus.clone().addScaledVector(back, want + 0.4), p.char.col);
    if (hit && !(hit.tag && hit.tag.name === 'Orb')) want = Math.max(1.2, hit.distance - 0.4);
    this.distance = damp(this.distance, want, want < this.distance ? 25 : 4, dt);

    this.node.position.copy(this.focus);
    this.node.quaternion.copy(rot);
    this.camera.position.set(0, 0, this.distance);
    if (this.shakeAmt > 0) {
      const s = this.shakeAmt * this.shakeAmt * 0.4;
      this.camera.position.x += (Math.random() * 2 - 1) * s;
      this.camera.position.y += (Math.random() * 2 - 1) * s;
    }
    const sprinting = Input.down('sprint') && Math.hypot(p.velocity.x, p.velocity.z) > 8;
    this.camera.fov = damp(this.camera.fov, sprinting ? 76 : 68, 6, dt);
    this.camera.updateProjectionMatrix();
  }
}
