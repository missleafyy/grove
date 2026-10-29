// Physics on Rapier, shaped like Grove's API: static/rigid/kinematic bodies, a character controller,
// raycasts and impact callbacks.
import RAPIER from '@dimforge/rapier3d-compat';
import * as THREE from 'three';

export let world = null;
export const bodies = [];              // dynamic + kinematic records synced to their Object3D
const byCollider = new Map();          // collider handle -> record/tag

export async function initPhysics() {
  await RAPIER.init();
  world = new RAPIER.World({ x: 0, y: -9.81, z: 0 });
  world.timestep = 1 / 60;
  return world;
}

// Shape descriptors -> fresh Rapier ColliderDesc (descs are single-use, so shapes are factories).
export const Shape = {
  box: (sx, sy, sz) => () => RAPIER.ColliderDesc.cuboid(sx / 2, sy / 2, sz / 2),
  sphere: (r) => () => RAPIER.ColliderDesc.ball(r),
  cylinder: (r, h) => () => RAPIER.ColliderDesc.cylinder(h / 2, r),
  convex: (md) => () => RAPIER.ColliderDesc.convexHull(new Float32Array(md.p)),
  mesh: (md) => () => RAPIER.ColliderDesc.trimesh(new Float32Array(md.p), new Uint32Array(md.i)),
  offset: (shape, v) => () => shape().setTranslation(v.x, v.y, v.z),
};

const q = (r) => (r ? { x: r.x, y: r.y, z: r.z, w: r.w } : { x: 0, y: 0, z: 0, w: 1 });

export function addStatic(shape, pos, rot, tag = {}) {
  const desc = shape().setFriction(tag.friction ?? 0.5);
  const body = world.createRigidBody(RAPIER.RigidBodyDesc.fixed().setTranslation(pos.x, pos.y, pos.z).setRotation(q(rot)));
  const col = world.createCollider(desc, body);
  byCollider.set(col.handle, tag);
  return col;
}

// opts: shape, position, rotation, mass, friction, bounce, ccd, linear_damp, angular_damp, name, obj
export function addRigid(o) {
  const bd = RAPIER.RigidBodyDesc.dynamic().setTranslation(o.position.x, o.position.y, o.position.z).setRotation(q(o.rotation))
    .setLinearDamping(o.linear_damp ?? 0.05).setAngularDamping(o.angular_damp ?? 0.05).setCcdEnabled(!!o.ccd);
  const body = world.createRigidBody(bd);
  const col = world.createCollider(o.shape().setMass(o.mass ?? 1).setFriction(o.friction ?? 0.5).setRestitution(o.bounce ?? 0), body);
  const rec = { body, col, obj: o.obj, name: o.name, dynamic: true, prevVel: new THREE.Vector3(), onImpact: null, lastImpact: -1 };
  byCollider.set(col.handle, rec);
  bodies.push(rec);
  return rec;
}

export function addKinematic(o) {
  const body = world.createRigidBody(RAPIER.RigidBodyDesc.kinematicPositionBased().setTranslation(o.position.x, o.position.y, o.position.z));
  const col = world.createCollider(o.shape().setFriction(o.friction ?? 0.8), body);
  const rec = { body, col, obj: o.obj, name: o.name, kinematic: true, delta: new THREE.Vector3(), pos: o.position.clone() };
  byCollider.set(col.handle, rec);
  bodies.push(rec);
  return rec;
}
export function moveKinematic(rec, p) {
  rec.delta.subVectors(p, rec.pos);
  rec.pos.copy(p);
  rec.body.setNextKinematicTranslation({ x: p.x, y: p.y, z: p.z });
}

export function removeBody(rec) {
  const i = bodies.indexOf(rec);
  if (i >= 0) bodies.splice(i, 1);
  byCollider.delete(rec.col.handle);
  world.removeRigidBody(rec.body);
}

export function setVelocity(rec, v) { rec.body.setLinvel({ x: v.x, y: v.y, z: v.z }, true); }
export const tagOf = (col) => byCollider.get(col.handle);

// Physics.raycast(from, to, exclude collider) -> { position, normal, distance, tag } | null
export function raycast(from, to, exclude) {
  const dir = to.clone().sub(from);
  const len = dir.length();
  if (len < 1e-6) return null;
  dir.divideScalar(len);
  const ray = new RAPIER.Ray({ x: from.x, y: from.y, z: from.z }, { x: dir.x, y: dir.y, z: dir.z });
  const hit = world.castRayAndGetNormal(ray, len, true, undefined, undefined, exclude);
  if (!hit) return null;
  return {
    position: from.clone().addScaledVector(dir, hit.timeOfImpact), distance: hit.timeOfImpact,
    normal: new THREE.Vector3(hit.normal.x, hit.normal.y, hit.normal.z), tag: byCollider.get(hit.collider.handle),
  };
}

const _v = new THREE.Vector3();
// Step and copy transforms to visuals; fire impact callbacks on sudden velocity changes.
export function stepPhysics(dt, time) {
  world.timestep = Math.min(dt, 1 / 30);
  world.step();
  for (const r of bodies) {
    const t = r.body.translation(), ro = r.body.rotation();
    if (r.obj) { r.obj.position.set(t.x, t.y, t.z); r.obj.quaternion.set(ro.x, ro.y, ro.z, ro.w); }
    if (r.dynamic && r.onImpact && !r.body.isSleeping()) {
      const lv = r.body.linvel();
      _v.set(lv.x, lv.y, lv.z);
      const dv = _v.distanceTo(r.prevVel) - 9.81 * world.timestep;
      if (dv > 0 && time - r.lastImpact > 0.12) r.onImpact(dv, new THREE.Vector3(t.x, t.y, t.z), time);
      r.prevVel.copy(_v);
    }
  }
}

// ------------------------------------------------------------------ character
// Kinematic capsule with its origin at the feet, like Grove's CharacterBody3D (Jolt CharacterVirtual).
export class Character {
  constructor(pos, radius, height, stepHeight, maxSlopeDeg) {
    const hh = Math.max(height / 2 - radius, 0.001);
    this.body = world.createRigidBody(RAPIER.RigidBodyDesc.kinematicPositionBased().setTranslation(pos.x, pos.y, pos.z));
    this.col = world.createCollider(RAPIER.ColliderDesc.capsule(hh, radius).setTranslation(0, hh + radius, 0), this.body);
    byCollider.set(this.col.handle, { player: true });
    this.cc = world.createCharacterController(0.03);
    this.cc.setUp({ x: 0, y: 1, z: 0 });
    this.cc.setMaxSlopeClimbAngle(maxSlopeDeg * Math.PI / 180);
    this.cc.setMinSlopeSlideAngle((maxSlopeDeg + 4) * Math.PI / 180);
    this.cc.enableAutostep(stepHeight, 0.15, false);
    this.cc.enableSnapToGround(0.3);
    this.cc.setApplyImpulsesToDynamicBodies(true);
    this.cc.setCharacterMass(70);
    this.position = pos.clone();
    this.grounded = false;
    this.floorNormal = new THREE.Vector3(0, 1, 0);
    this.radius = radius;
  }
  // Moves by velocity * dt (+ carry from a platform underneath). Returns the applied movement.
  // Short ray down from just above the feet; returns the floor hit, if any.
  probe(depth) {
    return raycast(this.position.clone().add(new THREE.Vector3(0, 0.3, 0)), this.position.clone().add(new THREE.Vector3(0, -depth, 0)), this.col);
  }
  move(vel, dt) {
    // Standing on a moving platform: its motion this frame is added on top of the collision solve.
    const below = vel.y <= 0 ? this.probe(0.4) : null;
    const carry = below && below.tag && below.tag.kinematic ? below.tag.delta : null;
    const want = { x: vel.x * dt, y: vel.y * dt, z: vel.z * dt };
    this.cc.computeColliderMovement(this.col, want);
    const m = this.cc.computedMovement();
    this.position.x += m.x; this.position.y += m.y; this.position.z += m.z;
    if (carry) this.position.add(carry);
    this.body.setNextKinematicTranslation({ x: this.position.x, y: this.position.y, z: this.position.z });
    this.hitCeiling = vel.y > 0 && m.y < want.y * 0.5 - 0.001;
    // Rapier's grounded flag misses kinematic platforms, so back it up with the probe.
    const floor = vel.y <= 0 ? this.probe(0.2) : null;
    this.grounded = this.cc.computedGrounded() || !!(floor && floor.normal.y > 0.6);
    this.floorNormal.copy(floor ? floor.normal : new THREE.Vector3(0, 1, 0));
    return m;
  }
  teleport(p) {
    this.position.copy(p);
    this.body.setTranslation({ x: p.x, y: p.y, z: p.z }, true);
    this.body.setNextKinematicTranslation({ x: p.x, y: p.y, z: p.z });
  }
}
