// Physics server built on Jolt: shapes, bodies, characters, queries and contact events.
#include <Jolt/Jolt.h>
#include <Jolt/RegisterTypes.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Physics/PhysicsSettings.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/CylinderShape.h>
#include <Jolt/Physics/Collision/Shape/ConvexHullShape.h>
#include <Jolt/Physics/Collision/Shape/MeshShape.h>
#include <Jolt/Physics/Collision/Shape/RotatedTranslatedShape.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/CollideShape.h>
#include <Jolt/Physics/Collision/CollisionCollectorImpl.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Character/CharacterVirtual.h>
#include <mutex>
#include <thread>
#include <algorithm>
#include "core.hpp"

using namespace JPH;

namespace Layers {
static constexpr ObjectLayer STATIC = 0, MOVING = 1, SENSOR = 2, COUNT = 3;
}

class ObjPairFilter : public ObjectLayerPairFilter {
 public:
  bool ShouldCollide(ObjectLayer a, ObjectLayer b) const override {
    if (a == Layers::SENSOR || b == Layers::SENSOR) return false;
    if (a == Layers::STATIC) return b == Layers::MOVING;
    return true;
  }
};

class BPInterface : public BroadPhaseLayerInterface {
 public:
  uint GetNumBroadPhaseLayers() const override { return 3; }
  BroadPhaseLayer GetBroadPhaseLayer(ObjectLayer l) const override { return BroadPhaseLayer((uint8)l); }
#if defined(JPH_EXTERNAL_PROFILE) || defined(JPH_PROFILE_ENABLED)
  const char* GetBroadPhaseLayerName(BroadPhaseLayer l) const override { return "layer"; }
#endif
};

class ObjVsBPFilter : public ObjectVsBroadPhaseLayerFilter {
 public:
  bool ShouldCollide(ObjectLayer a, BroadPhaseLayer b) const override {
    uint8 bl = (uint8)b;
    if (a == Layers::SENSOR || bl == Layers::SENSOR) return false;
    if (a == Layers::STATIC) return bl == Layers::MOVING;
    return true;
  }
};

// Queries (raycasts) see everything except sensors.
class QueryBPFilter : public BroadPhaseLayerFilter {
 public:
  bool ShouldCollide(BroadPhaseLayer l) const override { return (uint8)l != Layers::SENSOR; }
};
class QueryObjFilter : public ObjectLayerFilter {
 public:
  bool ShouldCollide(ObjectLayer l) const override { return l != Layers::SENSOR; }
};

static std::mutex contact_mutex;
static std::vector<GrContact> contacts;

class Listener : public ContactListener {
 public:
  void OnContactAdded(const Body& b1, const Body& b2, const ContactManifold& m, ContactSettings&) override {
    if (b1.IsSensor() || b2.IsSensor()) return;
    GrContact c;
    c.a = (int)b1.GetUserData();
    c.b = (int)b2.GetUserData();
    RVec3 p = m.GetWorldSpaceContactPointOn1(0);
    c.point[0] = (float)p.GetX(); c.point[1] = (float)p.GetY(); c.point[2] = (float)p.GetZ();
    Vec3 n = m.mWorldSpaceNormal;
    c.normal[0] = n.GetX(); c.normal[1] = n.GetY(); c.normal[2] = n.GetZ();
    Vec3 rel = b1.GetLinearVelocity() - b2.GetLinearVelocity();
    c.speed = std::fabs(rel.Dot(n));
    std::lock_guard<std::mutex> lock(contact_mutex);
    if (contacts.size() < 4096) contacts.push_back(c);
  }
};

struct Char {
  Ref<CharacterVirtual> cv;
  int body = 0;
  float step = 0.3f;
};

static TempAllocatorImpl* temp_alloc;
static JobSystemThreadPool* jobs;
static PhysicsSystem* phys;
static BPInterface bp_iface;
static ObjVsBPFilter obj_bp_filter;
static ObjPairFilter obj_pair_filter;
static Listener listener;
static Pool<ShapeRefC> shapes;
static Pool<BodyID> bodies;
static Pool<Char> chars;
static size_t contact_read = 0;

static void create_system() {
  phys = new PhysicsSystem();
  phys->Init(16384, 0, 16384, 16384, bp_iface, obj_bp_filter, obj_pair_filter);
  phys->SetContactListener(&listener);
  phys->SetGravity(Vec3(0, -9.81f, 0));
}

static void destroy_system() {
  // Characters own their inner bodies; forget those handles before the bulk removal.
  chars.each([](int, Char& c) { if (c.body) bodies.alive[c.body] = 0; });
  chars.clear();
  BodyInterface& bi = phys->GetBodyInterface();
  bodies.each([&](int, BodyID& id) { bi.RemoveBody(id); bi.DestroyBody(id); });
  bodies.clear();
  shapes.clear();
  delete phys;
  phys = nullptr;
  contacts.clear();
  contact_read = 0;
}

bool physics_init() {
  RegisterDefaultAllocator();
  Factory::sInstance = new Factory();
  RegisterTypes();
  temp_alloc = new TempAllocatorImpl(32 * 1024 * 1024);
  int threads = std::max(1, (int)std::thread::hardware_concurrency() - 1);
  jobs = new JobSystemThreadPool(cMaxPhysicsJobs, cMaxPhysicsBarriers, threads);
  create_system();
  return true;
}

void physics_reset() { destroy_system(); create_system(); }

void physics_shutdown() {
  destroy_system();
  delete jobs; delete temp_alloc;
  UnregisterTypes();
  delete Factory::sInstance;
  Factory::sInstance = nullptr;
}

static BodyInterface& BI() { return phys->GetBodyInterface(); }
static BodyID* body_id(int h) { return bodies.get(h); }

static int add_shape(const ShapeSettings& s) {
  auto r = s.Create();
  if (r.HasError()) { fprintf(stderr, "[grove] shape error: %s\n", r.GetError().c_str()); return 0; }
  return shapes.add(r.Get());
}

extern "C" {

int gr_shape_box(float hx, float hy, float hz) {
  float r = std::min(0.05f, std::min(hx, std::min(hy, hz)) * 0.5f);
  return add_shape(BoxShapeSettings(Vec3(hx, hy, hz), r));
}
int gr_shape_sphere(float radius) { return add_shape(SphereShapeSettings(radius)); }
int gr_shape_capsule(float hh, float r) { return add_shape(CapsuleShapeSettings(std::max(hh, 0.001f), r)); }
int gr_shape_cylinder(float hh, float r) { return add_shape(CylinderShapeSettings(hh, r, std::min(0.05f, std::min(hh, r) * 0.5f))); }
int gr_shape_convex(const float* pts, int n) {
  Array<Vec3> v;
  for (int i = 0; i < n; i++) v.push_back(Vec3(pts[i * 3], pts[i * 3 + 1], pts[i * 3 + 2]));
  return add_shape(ConvexHullShapeSettings(v));
}
int gr_shape_mesh(const float* verts, int nv, const unsigned* idx, int ni) {
  VertexList vl;
  for (int i = 0; i < nv; i++) vl.push_back(Float3(verts[i * 3], verts[i * 3 + 1], verts[i * 3 + 2]));
  IndexedTriangleList tl;
  for (int i = 0; i + 2 < ni; i += 3) tl.push_back(IndexedTriangle(idx[i], idx[i + 1], idx[i + 2], 0));
  return add_shape(MeshShapeSettings(vl, tl));
}
int gr_shape_offset(int shape, float x, float y, float z) {
  ShapeRefC* s = shapes.get(shape);
  if (!s) return 0;
  return add_shape(RotatedTranslatedShapeSettings(Vec3(x, y, z), Quat::sIdentity(), *s));
}

int gr_body_create(const GrBodyDesc* d) {
  ShapeRefC* s = shapes.get(d->shape);
  if (!s) return 0;
  EMotionType mt = d->motion == 2 ? EMotionType::Dynamic : d->motion == 1 ? EMotionType::Kinematic : EMotionType::Static;
  ObjectLayer layer = d->sensor ? Layers::SENSOR : (d->motion == 0 ? Layers::STATIC : Layers::MOVING);
  BodyCreationSettings bs(*s, RVec3(d->pos[0], d->pos[1], d->pos[2]), Quat(d->rot[0], d->rot[1], d->rot[2], d->rot[3]).Normalized(), mt, layer);
  bs.mFriction = d->friction;
  bs.mRestitution = d->restitution;
  bs.mLinearDamping = d->linear_damping;
  bs.mAngularDamping = d->angular_damping;
  bs.mGravityFactor = d->gravity_factor;
  bs.mIsSensor = d->sensor != 0;
  if (d->ccd) bs.mMotionQuality = EMotionQuality::LinearCast;
  if (d->motion == 2 && d->mass > 0) {
    bs.mOverrideMassProperties = EOverrideMassProperties::CalculateInertia;
    bs.mMassPropertiesOverride.mMass = d->mass;
  }
  Body* b = BI().CreateBody(bs);
  if (!b) { fprintf(stderr, "[grove] out of physics bodies\n"); return 0; }
  int h = bodies.add(b->GetID());
  b->SetUserData((uint64)h);
  BI().AddBody(b->GetID(), d->motion == 0 ? EActivation::DontActivate : EActivation::Activate);
  return h;
}

void gr_body_destroy(int h) {
  BodyID* id = body_id(h);
  if (!id) return;
  BI().RemoveBody(*id);
  BI().DestroyBody(*id);
  bodies.remove(h);
}

void gr_body_get(int h, float* pos, float* rot) {
  BodyID* id = body_id(h);
  if (!id) return;
  RVec3 p; Quat q;
  BI().GetPositionAndRotation(*id, p, q);
  pos[0] = (float)p.GetX(); pos[1] = (float)p.GetY(); pos[2] = (float)p.GetZ();
  rot[0] = q.GetX(); rot[1] = q.GetY(); rot[2] = q.GetZ(); rot[3] = q.GetW();
}

void gr_body_set(int h, float px, float py, float pz, float qx, float qy, float qz, float qw) {
  BodyID* id = body_id(h);
  if (!id) return;
  BI().SetPositionAndRotation(*id, RVec3(px, py, pz), Quat(qx, qy, qz, qw).Normalized(), EActivation::Activate);
}

void gr_body_move_kinematic(int h, float px, float py, float pz, float qx, float qy, float qz, float qw, float dt) {
  BodyID* id = body_id(h);
  if (!id || dt <= 0) return;
  BI().MoveKinematic(*id, RVec3(px, py, pz), Quat(qx, qy, qz, qw).Normalized(), dt);
}

void gr_body_get_velocity(int h, float* lin, float* ang) {
  BodyID* id = body_id(h);
  if (!id) return;
  Vec3 l, a;
  BI().GetLinearAndAngularVelocity(*id, l, a);
  lin[0] = l.GetX(); lin[1] = l.GetY(); lin[2] = l.GetZ();
  ang[0] = a.GetX(); ang[1] = a.GetY(); ang[2] = a.GetZ();
}

void gr_body_set_velocity(int h, float lx, float ly, float lz, float ax, float ay, float az) {
  BodyID* id = body_id(h);
  if (!id) return;
  BI().SetLinearAndAngularVelocity(*id, Vec3(lx, ly, lz), Vec3(ax, ay, az));
  BI().ActivateBody(*id);
}

void gr_body_impulse(int h, float x, float y, float z, float px, float py, float pz, int at_point) {
  BodyID* id = body_id(h);
  if (!id) return;
  if (at_point) BI().AddImpulse(*id, Vec3(x, y, z), RVec3(px, py, pz));
  else BI().AddImpulse(*id, Vec3(x, y, z));
}

void gr_body_force(int h, float x, float y, float z) {
  if (BodyID* id = body_id(h)) BI().AddForce(*id, Vec3(x, y, z));
}

int gr_body_sleeping(int h) { BodyID* id = body_id(h); return id ? !BI().IsActive(*id) : 1; }
void gr_body_wake(int h) { if (BodyID* id = body_id(h)) BI().ActivateBody(*id); }

int gr_body_overlaps(int h, int* out, int max) {
  BodyID* id = body_id(h);
  if (!id) return 0;
  RefConst<Shape> shape = BI().GetShape(*id);
  RMat44 xf = BI().GetCenterOfMassTransform(*id);
  CollideShapeSettings settings;
  AllHitCollisionCollector<CollideShapeCollector> col;
  IgnoreSingleBodyFilter self(*id);
  phys->GetNarrowPhaseQuery().CollideShape(shape, Vec3::sReplicate(1.0f), xf, settings, RVec3::sZero(), col, {}, {}, self);
  int n = 0;
  for (auto& hit : col.mHits) {
    int other = (int)BI().GetUserData(hit.mBodyID2);
    bool dup = false;
    for (int i = 0; i < n; i++) if (out[i] == other) { dup = true; break; }
    if (!dup && n < max) out[n++] = other;
  }
  return n;
}

void gr_physics_step(float dt) {
  if (dt <= 0) return;
  phys->Update(dt, 1, temp_alloc, jobs);
}

void gr_physics_gravity(float x, float y, float z) { phys->SetGravity(Vec3(x, y, z)); }

int gr_physics_active(int* ids, float* xf, int max) {
  BodyIDVector active;
  phys->GetActiveBodies(EBodyType::RigidBody, active);
  int n = 0;
  for (BodyID& id : active) {
    if (n >= max) break;
    RVec3 p; Quat q;
    BI().GetPositionAndRotation(id, p, q);
    ids[n] = (int)BI().GetUserData(id);
    float* o = &xf[n * 7];
    o[0] = (float)p.GetX(); o[1] = (float)p.GetY(); o[2] = (float)p.GetZ();
    o[3] = q.GetX(); o[4] = q.GetY(); o[5] = q.GetZ(); o[6] = q.GetW();
    n++;
  }
  return n;
}

int gr_physics_raycast(float ox, float oy, float oz, float dx, float dy, float dz, int ignore, GrRayHit* hit) {
  RRayCast ray{RVec3(ox, oy, oz), Vec3(dx, dy, dz)};
  RayCastResult res;
  QueryBPFilter bpf;
  QueryObjFilter of;
  BodyID* ig = body_id(ignore);
  IgnoreSingleBodyFilter ignore_filter(ig ? *ig : BodyID());
  BodyFilter none;
  bool ok = phys->GetNarrowPhaseQuery().CastRay(ray, res, bpf, of, ig ? (const BodyFilter&)ignore_filter : none);
  if (!ok) return 0;
  RVec3 p = ray.GetPointOnRay(res.mFraction);
  hit->body = (int)BI().GetUserData(res.mBodyID);
  hit->fraction = res.mFraction;
  hit->pos[0] = (float)p.GetX(); hit->pos[1] = (float)p.GetY(); hit->pos[2] = (float)p.GetZ();
  BodyLockRead lock(phys->GetBodyLockInterface(), res.mBodyID);
  Vec3 n(0, 1, 0);
  if (lock.Succeeded()) n = lock.GetBody().GetWorldSpaceSurfaceNormal(res.mSubShapeID2, p);
  hit->normal[0] = n.GetX(); hit->normal[1] = n.GetY(); hit->normal[2] = n.GetZ();
  return 1;
}

int gr_physics_sphere_overlap(float x, float y, float z, float radius, int* out, int max) {
  SphereShape sphere(radius);
  sphere.SetEmbedded();
  CollideShapeSettings settings;
  AllHitCollisionCollector<CollideShapeCollector> col;
  phys->GetNarrowPhaseQuery().CollideShape(&sphere, Vec3::sReplicate(1.0f), RMat44::sTranslation(RVec3(x, y, z)), settings, RVec3::sZero(), col);
  int n = 0;
  for (auto& hit : col.mHits) {
    int other = (int)BI().GetUserData(hit.mBodyID2);
    bool dup = false;
    for (int i = 0; i < n; i++) if (out[i] == other) { dup = true; break; }
    if (!dup && n < max) out[n++] = other;
  }
  return n;
}

int gr_physics_poll_contact(GrContact* out) {
  std::lock_guard<std::mutex> lock(contact_mutex);
  if (contact_read >= contacts.size()) { contacts.clear(); contact_read = 0; return 0; }
  *out = contacts[contact_read++];
  return 1;
}

int gr_physics_body_count(void) { return (int)phys->GetNumBodies(); }

// ------------------------------------------------------------ characters
int gr_character_create(float radius, float height, float px, float py, float pz, float max_slope, float step) {
  float hh = std::max(0.01f, height * 0.5f - radius);
  // Origin at the feet: offset the capsule up by half its height.
  ShapeRefC cap = RotatedTranslatedShapeSettings(Vec3(0, hh + radius, 0), Quat::sIdentity(), new CapsuleShape(hh, radius)).Create().Get();
  ShapeRefC inner = RotatedTranslatedShapeSettings(Vec3(0, hh + radius, 0), Quat::sIdentity(), new CapsuleShape(hh * 0.9f, radius * 0.9f)).Create().Get();
  Ref<CharacterVirtualSettings> s = new CharacterVirtualSettings();
  s->mShape = cap;
  s->mInnerBodyShape = inner;
  s->mInnerBodyLayer = Layers::MOVING;
  s->mMaxSlopeAngle = DegreesToRadians(max_slope);
  s->mSupportingVolume = Plane(Vec3::sAxisY(), -radius);
  s->mMass = 70;
  s->mMaxStrength = 300;
  Char c;
  c.cv = new CharacterVirtual(s, RVec3(px, py, pz), Quat::sIdentity(), 0, phys);
  c.step = step;
  int h = chars.add(c);
  BodyID inner_id = c.cv->GetInnerBodyID();
  if (!inner_id.IsInvalid()) {
    int bh = bodies.add(inner_id);
    BI().SetUserData(inner_id, (uint64)bh);
    chars.get(h)->body = bh;
  }
  return h;
}

void gr_character_destroy(int h) {
  Char* c = chars.get(h);
  if (!c) return;
  // The inner body is owned by the character; drop our handle before it goes away.
  if (c->body) { bodies.alive[c->body] = 0; bodies.free_ids.push_back(c->body); }
  chars.remove(h);
}

void gr_character_move(int h, float vx, float vy, float vz, float dt, GrCharState* out) {
  Char* c = chars.get(h);
  if (!c || dt <= 0) return;
  CharacterVirtual* cv = c->cv;
  cv->UpdateGroundVelocity();
  Vec3 ground_v = cv->IsSupported() ? cv->GetGroundVelocity() : Vec3::sZero();
  Vec3 v(vx, vy, vz);
  bool moving_up = vy > 0.1f;
  if (cv->GetGroundState() == CharacterBase::EGroundState::OnGround && !moving_up) v += Vec3(ground_v.GetX(), std::min(ground_v.GetY(), 0.0f), ground_v.GetZ());
  else if (cv->GetGroundState() == CharacterBase::EGroundState::OnGround) v += Vec3(ground_v.GetX(), 0, ground_v.GetZ());
  cv->SetLinearVelocity(v);

  CharacterVirtual::ExtendedUpdateSettings es;
  es.mStickToFloorStepDown = moving_up ? Vec3::sZero() : Vec3(0, -0.4f, 0);
  es.mWalkStairsStepUp = Vec3(0, c->step, 0);
  DefaultBroadPhaseLayerFilter bpf = phys->GetDefaultBroadPhaseLayerFilter(Layers::MOVING);
  DefaultObjectLayerFilter olf = phys->GetDefaultLayerFilter(Layers::MOVING);
  IgnoreSingleBodyFilter bf(cv->GetInnerBodyID());
  ShapeFilter sf;
  cv->ExtendedUpdate(dt, phys->GetGravity(), es, bpf, olf, bf, sf, *temp_alloc);

  RVec3 p = cv->GetPosition();
  Vec3 nv = cv->GetLinearVelocity();
  bool on_floor = cv->GetGroundState() == CharacterBase::EGroundState::OnGround;
  if (on_floor || cv->GetGroundState() == CharacterBase::EGroundState::OnSteepGround) {
    cv->UpdateGroundVelocity();
    Vec3 gv = cv->GetGroundVelocity();
    nv -= Vec3(gv.GetX(), 0, gv.GetZ());
  }
  out->pos[0] = (float)p.GetX(); out->pos[1] = (float)p.GetY(); out->pos[2] = (float)p.GetZ();
  out->vel[0] = nv.GetX(); out->vel[1] = nv.GetY(); out->vel[2] = nv.GetZ();
  out->on_floor = on_floor;
  out->on_wall = 0;
  out->on_ceiling = 0;
  for (const auto& ct : cv->GetActiveContacts()) {
    if (!ct.mHadCollision) continue;
    float ny = ct.mContactNormal.GetY();
    if (ny < -0.5f) out->on_ceiling = 1;
    else if (std::fabs(ny) < 0.3f) out->on_wall = 1;
  }
  Vec3 gn = cv->GetGroundNormal();
  out->floor_normal[0] = gn.GetX(); out->floor_normal[1] = gn.GetY(); out->floor_normal[2] = gn.GetZ();
  BodyID gb = cv->GetGroundBodyID();
  out->floor_body = gb.IsInvalid() ? 0 : (int)BI().GetUserData(gb);
}

void gr_character_teleport(int h, float x, float y, float z) {
  if (Char* c = chars.get(h)) { c->cv->SetPosition(RVec3(x, y, z)); c->cv->SetLinearVelocity(Vec3::sZero()); }
}

int gr_character_body(int h) { Char* c = chars.get(h); return c ? c->body : 0; }

}  // extern "C"
