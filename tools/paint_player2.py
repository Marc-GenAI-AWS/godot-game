import json, numpy as np
from PIL import Image, ImageFilter
src = "/home/marc/dev/graphics-gen/assets/ubc/pack/base/godot/"
g = json.load(open(src + "Superhero_Female_FullBody.gltf")); b = open(src + "Superhero_Female_FullBody.bin", "rb").read()
def acc(i):
    a = g["accessors"][i]; bv = g["bufferViews"][a["bufferView"]]; off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    ct = {5126: ("f4", 4), 5123: ("u2", 2), 5121: ("u1", 1), 5125: ("u4", 4)}[a["componentType"]]; n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    stride = bv.get("byteStride", ct[1] * n)
    if stride == ct[1] * n: arr = np.frombuffer(b, dtype=ct[0], count=a["count"] * n, offset=off)
    else: arr = np.array([np.frombuffer(b, dtype=ct[0], count=n, offset=off + k * stride) for k in range(a["count"])]).reshape(-1)
    return arr.reshape(a["count"], n)
m = [m for m in g["meshes"] if m["name"] == "Superhero_Female"][0]; p = m["primitives"][0]
pos = acc(p["attributes"]["POSITION"]).astype(np.float64); uv = acc(p["attributes"]["TEXCOORD_0"]).astype(np.float64); nrm = acc(p["attributes"]["NORMAL"]).astype(np.float64)
j = acc(p["attributes"]["JOINTS_0"]); w = acc(p["attributes"]["WEIGHTS_0"]); idx = acc(p["indices"]).reshape(-1, 3)
names = [g["nodes"][x]["name"] for x in g["skins"][0]["joints"]]
dom = np.array([names[k] for k in j[np.arange(len(j)), w.argmax(1)]])
W = 2048
ymap = np.full((W, W), np.nan); zn = np.zeros((W, W)); region = np.zeros((W, W), dtype=np.int16)
rid = {"pelvis": 1, "thigh_l": 2, "thigh_r": 3, "spine_01": 4, "spine_02": 5, "spine_03": 6}
# Rasterise per-pixel body height (y), normal z and bone region by barycentric interpolation.
for tri in idx:
    uvs = uv[tri] * W; ys = pos[tri, 1]; nz = nrm[tri, 2]
    x0, y0 = np.floor(uvs.min(0)).astype(int); x1, y1 = np.ceil(uvs.max(0)).astype(int)
    x0, y0 = max(x0 - 1, 0), max(y0 - 1, 0); x1, y1 = min(x1 + 1, W - 1), min(y1 + 1, W - 1)
    if x1 <= x0 or y1 <= y0: continue
    gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    (ax, ay), (bx, by), (cx, cy) = uvs
    det = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
    if abs(det) < 1e-9: continue
    l1 = ((bx - gx) * (cy - gy) - (cx - gx) * (by - gy)) / det
    l2 = ((cx - gx) * (ay - gy) - (ax - gx) * (cy - gy)) / det
    l0 = 1 - l1 - l2
    inside = (l0 >= -0.02) & (l1 >= -0.02) & (l2 >= -0.02)
    if not inside.any(): continue
    yy = l0 * ys[0] + l1 * ys[1] + l2 * ys[2]
    zz = l0 * nz[0] + l1 * nz[1] + l2 * nz[2]
    sub = ymap[y0:y1 + 1, x0:x1 + 1]; sub[inside] = yy[inside]
    subz = zn[y0:y1 + 1, x0:x1 + 1]; subz[inside] = zz[inside]
    doms = [dom[v] for v in tri]; r = rid.get(max(set(doms), key=doms.count), 0)
    subr = region[y0:y1 + 1, x0:x1 + 1]; subr[inside] = r
np.save("/home/marc/dev/graphics-gen/assets/ymap.npy", ymap); np.save("/home/marc/dev/graphics-gen/assets/region.npy", region); np.save("/home/marc/dev/graphics-gen/assets/zn.npy", zn)
print("rasterised", np.isfinite(ymap).sum(), "px")
