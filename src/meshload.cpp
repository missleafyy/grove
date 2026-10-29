// Model loading: glTF 2.0 (.gltf/.glb, static meshes) and Wavefront OBJ.
#include "core.hpp"
#include "cgltf.h"
#include <fstream>
#include <sstream>
#include <map>

static std::string dir_of(const std::string& p) {
  size_t s = p.find_last_of('/');
  return s == std::string::npos ? "." : p.substr(0, s);
}

static GrMaterial default_material() {
  GrMaterial m{};
  m.albedo[0] = m.albedo[1] = m.albedo[2] = m.albedo[3] = 1;
  m.roughness = 0.8f;
  m.uv_scale[0] = m.uv_scale[1] = 1;
  m.vertex_color = 1;
  return m;
}

static float to_srgb(float c) { return std::pow(std::max(c, 0.0f), 1.0f / 2.2f); }

static bool load_gltf(const std::string& path, std::vector<std::vector<GrVertex>>& pv, std::vector<std::vector<unsigned>>& pi,
                      std::vector<GrMaterial>& mats, std::vector<std::string>& texs) {
  cgltf_options opt{};
  cgltf_data* data = nullptr;
  if (cgltf_parse_file(&opt, path.c_str(), &data) != cgltf_result_success) return false;
  if (cgltf_load_buffers(&opt, data, path.c_str()) != cgltf_result_success) { cgltf_free(data); return false; }
  std::map<const cgltf_material*, int> part_of;
  auto part_for = [&](const cgltf_material* m) {
    auto it = part_of.find(m);
    if (it != part_of.end()) return it->second;
    int idx = (int)pv.size();
    pv.emplace_back(); pi.emplace_back();
    GrMaterial gm = default_material();
    std::string tex;
    if (m) {
      const cgltf_pbr_metallic_roughness& pbr = m->pbr_metallic_roughness;
      // glTF factors are linear; the engine expects sRGB-space colours.
      for (int i = 0; i < 3; i++) gm.albedo[i] = to_srgb(pbr.base_color_factor[i]);
      gm.albedo[3] = pbr.base_color_factor[3];
      gm.roughness = pbr.roughness_factor;
      gm.metallic = pbr.metallic_factor;
      for (int i = 0; i < 3; i++) gm.emission[i] = to_srgb(m->emissive_factor[i]);
      gm.emission_energy = (m->emissive_factor[0] + m->emissive_factor[1] + m->emissive_factor[2]) > 0 ? 1.0f : 0.0f;
      gm.double_sided = m->double_sided;
      if (m->alpha_mode == cgltf_alpha_mode_blend) gm.transparent = 1;
      if (m->alpha_mode == cgltf_alpha_mode_mask) gm.alpha_cutoff = m->alpha_cutoff;
      if (pbr.base_color_texture.texture && pbr.base_color_texture.texture->image && pbr.base_color_texture.texture->image->uri)
        tex = dir_of(path) + "/" + pbr.base_color_texture.texture->image->uri;
    }
    mats.push_back(gm);
    texs.push_back(tex);
    part_of[m] = idx;
    return idx;
  };

  for (cgltf_size ni = 0; ni < data->nodes_count; ni++) {
    cgltf_node* node = &data->nodes[ni];
    if (!node->mesh) continue;
    M4 world;
    cgltf_node_transform_world(node, world.m);
    M4 nmat = m4_inverse(world);  // transpose used below for normals
    for (cgltf_size p = 0; p < node->mesh->primitives_count; p++) {
      cgltf_primitive* prim = &node->mesh->primitives[p];
      if (prim->type != cgltf_primitive_type_triangles) continue;
      int part = part_for(prim->material);
      auto& V = pv[part];
      auto& I = pi[part];
      cgltf_accessor *pos = nullptr, *nrm = nullptr, *uv = nullptr, *col = nullptr;
      for (cgltf_size a = 0; a < prim->attributes_count; a++) {
        cgltf_attribute& at = prim->attributes[a];
        if (at.type == cgltf_attribute_type_position) pos = at.data;
        else if (at.type == cgltf_attribute_type_normal) nrm = at.data;
        else if (at.type == cgltf_attribute_type_texcoord && at.index == 0) uv = at.data;
        else if (at.type == cgltf_attribute_type_color && at.index == 0) col = at.data;
      }
      if (!pos) continue;
      unsigned base = (unsigned)V.size();
      for (cgltf_size i = 0; i < pos->count; i++) {
        float p3[3] = {0, 0, 0}, n3[3] = {0, 1, 0}, t2[2] = {0, 0}, c4[4] = {1, 1, 1, 1};
        cgltf_accessor_read_float(pos, i, p3, 3);
        if (nrm) cgltf_accessor_read_float(nrm, i, n3, 3);
        if (uv) cgltf_accessor_read_float(uv, i, t2, 2);
        if (col) { cgltf_accessor_read_float(col, i, c4, col->type == cgltf_type_vec3 ? 3 : 4); for (int k = 0; k < 3; k++) c4[k] = to_srgb(c4[k]); }
        V3 wp = world.point(V3(p3[0], p3[1], p3[2]));
        V3 wn(nmat.m[0] * n3[0] + nmat.m[1] * n3[1] + nmat.m[2] * n3[2],
              nmat.m[4] * n3[0] + nmat.m[5] * n3[1] + nmat.m[6] * n3[2],
              nmat.m[8] * n3[0] + nmat.m[9] * n3[1] + nmat.m[10] * n3[2]);
        wn = normalize(wn);
        V.push_back({wp.x, wp.y, wp.z, wn.x, wn.y, wn.z, t2[0], t2[1], c4[0], c4[1], c4[2], c4[3]});
      }
      if (prim->indices) {
        for (cgltf_size i = 0; i < prim->indices->count; i++) I.push_back(base + (unsigned)cgltf_accessor_read_index(prim->indices, i));
      } else {
        for (cgltf_size i = 0; i < pos->count; i++) I.push_back(base + (unsigned)i);
      }
    }
  }
  cgltf_free(data);
  return !pv.empty();
}

static bool load_obj(const std::string& path, std::vector<std::vector<GrVertex>>& pv, std::vector<std::vector<unsigned>>& pi,
                     std::vector<GrMaterial>& mats, std::vector<std::string>& texs) {
  std::ifstream f(path);
  if (!f) return false;
  std::vector<V3> P, N;
  std::vector<std::pair<float, float>> T;
  pv.emplace_back(); pi.emplace_back();
  mats.push_back(default_material());
  texs.push_back("");
  auto& V = pv[0];
  auto& I = pi[0];
  std::string line;
  while (std::getline(f, line)) {
    std::istringstream ss(line);
    std::string tag;
    ss >> tag;
    if (tag == "v") { V3 p; ss >> p.x >> p.y >> p.z; P.push_back(p); }
    else if (tag == "vn") { V3 n; ss >> n.x >> n.y >> n.z; N.push_back(n); }
    else if (tag == "vt") { float u, v; ss >> u >> v; T.push_back({u, 1 - v}); }
    else if (tag == "f") {
      std::vector<unsigned> face;
      std::string tok;
      while (ss >> tok) {
        int vi = 0, ti = 0, nidx = 0;
        sscanf(tok.c_str(), "%d/%d/%d", &vi, &ti, &nidx);
        if (tok.find("//") != std::string::npos) sscanf(tok.c_str(), "%d//%d", &vi, &nidx);
        auto fix = [](int i, size_t n) { return i < 0 ? (int)n + i : i - 1; };
        vi = fix(vi, P.size()); ti = ti ? fix(ti, T.size()) : -1; nidx = nidx ? fix(nidx, N.size()) : -1;
        GrVertex v{};
        if (vi >= 0 && vi < (int)P.size()) { v.px = P[vi].x; v.py = P[vi].y; v.pz = P[vi].z; }
        if (nidx >= 0 && nidx < (int)N.size()) { v.nx = N[nidx].x; v.ny = N[nidx].y; v.nz = N[nidx].z; } else v.ny = 1;
        if (ti >= 0 && ti < (int)T.size()) { v.u = T[ti].first; v.v = T[ti].second; }
        v.r = v.g = v.b = v.a = 1;
        face.push_back((unsigned)V.size());
        V.push_back(v);
      }
      for (size_t k = 1; k + 1 < face.size(); k++) { I.push_back(face[0]); I.push_back(face[k]); I.push_back(face[k + 1]); }
    }
  }
  if (N.empty()) {
    // No normals in the file: use flat face normals.
    for (size_t k = 0; k + 2 < I.size(); k += 3) {
      GrVertex &a = V[I[k]], &b = V[I[k + 1]], &c = V[I[k + 2]];
      V3 n = normalize(cross(V3(b.px - a.px, b.py - a.py, b.pz - a.pz), V3(c.px - a.px, c.py - a.py, c.pz - a.pz)));
      for (GrVertex* v : {&a, &b, &c}) { v->nx = n.x; v->ny = n.y; v->nz = n.z; }
    }
  }
  return !V.empty();
}

bool meshload(const char* path, std::vector<std::vector<GrVertex>>& pv, std::vector<std::vector<unsigned>>& pi,
              std::vector<GrMaterial>& mats, std::vector<std::string>& texs) {
  std::string p(path);
  std::string ext = p.substr(p.find_last_of('.') + 1);
  for (auto& c : ext) c = (char)tolower(c);
  bool ok = (ext == "obj") ? load_obj(p, pv, pi, mats, texs) : load_gltf(p, pv, pi, mats, texs);
  if (!ok) fprintf(stderr, "[grove] could not load model %s\n", path);
  return ok;
}
