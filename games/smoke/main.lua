-- Minimal engine smoke test: a lit box on a floor with a rigid body falling.
local floor_mat = Material { albedo = Color(0.5, 0.6, 0.5), roughness = 0.9 }
local box_mat = Material { albedo = Color.hex("#e8a33c"), roughness = 0.5 }
local box = MeshData.box(1, 1, 1):upload()

Game.start(Node3D {
  name = "World",
  DirectionalLight3D { rotation = Quat.euler_deg(-45, 35, 0) },
  Camera3D { position = Vec3(0, 4, 9), rotation = Quat.euler_deg(-20, 0, 0) },
  StaticBody3D { shape = Shape.box(20, 1, 20), position = Vec3(0, -0.5, 0),
    MeshInstance3D { mesh = MeshData.box(20, 1, 20):upload(), material = floor_mat } },
  RigidBody3D { shape = Shape.box(1, 1, 1), position = Vec3(0, 5, 0), rotation = Quat.euler_deg(20, 30, 10),
    MeshInstance3D { mesh = box, material = box_mat } },
  Label { text = "Grove smoke test", x = 20, y = 20, size = 28 },
  OmniLight3D { position = Vec3(2, 1, 2), color = Color(1, 0.4, 0.2), energy = 4 },
})
