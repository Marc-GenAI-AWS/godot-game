# Paint crop top + denim shorts + tattoo onto the MPFB skin texture, in UV space,
# using per-pixel body height rasterised from the mesh (same approach as route 1).
import struct, json, io, numpy as np
from PIL import Image, ImageFilter
GLB = "/home/marc/dev/graphics-gen/beach/characters/mpfb/mpfb_player.glb"
OUT = "/home/marc/dev/graphics-gen/beach/characters/mpfb/T_MPFB_BaseColor.png"
d = open(GLB, "rb").read(); ln = struct.unpack("<I", d[12:16])[0]; g = json.loads(d[20:20 + ln])
bo = 20 + ln; bl = struct.unpack("<I", d[bo:bo + 4])[0]; b = d[bo + 8:bo + 8 + bl]
def acc(i):
    a = g["accessors"][i]; bv = g["bufferViews"][a["bufferView"]]; off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    ct = {5126: ("f4", 4), 5123: ("u2", 2), 5121: ("u1", 1), 5125: ("u4", 4)}[a["componentType"]]; n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    return np.frombuffer(b, dtype=ct[0], count=a["count"] * n, offset=off).reshape(a["count"], n)
mesh = [m for m in g["meshes"] if m["name"].startswith("base")][0]; p = mesh["primitives"][0]
pos = acc(p["attributes"]["POSITION"]).astype(np.float64); uv = acc(p["attributes"]["TEXCOORD_0"]).astype(np.float64); nrm = acc(p["attributes"]["NORMAL"]).astype(np.float64)
j = acc(p["attributes"]["JOINTS_0"]); w = acc(p["attributes"]["WEIGHTS_0"]); idx = acc(p["indices"]).reshape(-1, 3)
names = [g["nodes"][x]["name"] for x in g["skins"][0]["joints"]]
dom = np.array([names[k] for k in j[np.arange(len(j)), w.argmax(1)]])
for bn in ["pelvis", "thigh_l", "spine_01", "spine_02", "spine_03"]:
    sel = dom == bn; print(bn, "y", pos[sel][:, 1].min().round(2), pos[sel][:, 1].max().round(2))
img_idx = g["materials"][p["material"]]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
im_info = g["images"][g["textures"][img_idx]["source"]]; bv = g["bufferViews"][im_info["bufferView"]]
base = Image.open(io.BytesIO(b[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])).convert("RGB")
W = base.size[0]; print("texture", base.size, "flipV?", uv[:, 1].min().round(2), uv[:, 1].max().round(2))
ymap = np.full((W, W), np.nan); zn = np.zeros((W, W)); region = np.zeros((W, W), dtype=np.int16)
rid = {"pelvis": 1, "thigh_l": 2, "thigh_r": 3, "spine_01": 4, "spine_02": 5, "spine_03": 6}
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
    yy = l0 * ys[0] + l1 * ys[1] + l2 * ys[2]; zz = l0 * nz[0] + l1 * nz[1] + l2 * nz[2]
    ymap[y0:y1 + 1, x0:x1 + 1][inside] = yy[inside]; zn[y0:y1 + 1, x0:x1 + 1][inside] = zz[inside]
    doms = [dom[v] for v in tri]; region[y0:y1 + 1, x0:x1 + 1][inside] = rid.get(max(set(doms), key=doms.count), 0)
valid = np.isfinite(ymap); y = np.where(valid, ymap, -10)
H = pos[:, 1].max()
shorts = np.isin(region, [1, 2, 3, 4]) & (y > 0.425 * H) & (y < 0.595 * H)
top = np.isin(region, [5, 6]) & (y > 0.69 * H) & (y < 0.765 * H)
def clean(mask, blur=2.5):
    im = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(blur))
    return (np.asarray(im).astype(np.float32) / 255.0 > 0.5).astype(np.float32)
ms = clean(shorts); mt = clean(top)
arr = np.asarray(base).astype(np.float32) / 255.0
# warm tan: MakeHuman's light skin is pale; push toward golden tan
tan = np.array([0.80, 0.56, 0.38]); lum = arr.mean(-1, keepdims=True)
arr = np.clip(arr * 0.35 + lum * tan * 0.8, 0, 1)
rng = np.random.default_rng(3); yy, xx = np.mgrid[0:W, 0:W]
grain = np.asarray(Image.fromarray(((rng.normal(0, 1, (W, W)) * 0.5 + 0.5) * 255).clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255.0
denim = np.stack([0.5 + 0.10 * grain, 0.6 + 0.10 * grain, 0.77 + 0.08 * grain], -1)
denim = np.clip(denim + (np.sin(xx * 1.7) * np.sin(yy * 1.7) * 0.04)[..., None], 0, 1)
hem = ms * ((y > 0.425 * H) & (y < 0.443 * H)); waist = ms * ((y > 0.578 * H) & (y < 0.595 * H))
denim = np.where(hem[..., None] > 0.5, denim * 0.7 + 0.28, denim); denim = np.where(waist[..., None] > 0.5, denim * 0.86, denim)
edge = ms - np.asarray(Image.fromarray((ms * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5))).astype(np.float32) / 255.0
denim = np.where((edge > 0.5)[..., None] & (hem < 0.5)[..., None], denim * 0.8, denim)
n1 = np.asarray(Image.fromarray(rng.random((W // 4, W // 4)).astype(np.float32) * 255).resize((W, W), Image.BICUBIC)).astype(np.float32) / 255.0
n2 = np.asarray(Image.fromarray((rng.random((W // 12, W // 12)) * 255).astype(np.uint8)).resize((W, W), Image.BICUBIC)).astype(np.float32) / 255.0
pink = np.array([0.93, 0.5, 0.6]); petal = np.array([0.8, 0.18, 0.32]); leaf = np.array([0.55, 0.62, 0.45]); cream = np.array([0.98, 0.9, 0.9])
top_col = np.tile(pink, (W, W, 1)).astype(np.float32)
top_col = np.where((n2 > 0.62)[..., None], petal, top_col); top_col = np.where((n2 < 0.3)[..., None], leaf, top_col); top_col = np.where((n1 > 0.82)[..., None], cream, top_col)
tedge = mt - np.asarray(Image.fromarray((mt * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(7))).astype(np.float32) / 255.0
top_col = np.where((tedge > 0.5)[..., None], top_col * 0.5 + 0.45, top_col)
out = arr * (1 - ms[..., None]) + denim * ms[..., None]
out = out * (1 - mt[..., None]) + top_col * mt[..., None]
tat = (region == 3) & (y > 0.35 * H) & (y < 0.41 * H) & (zn < -0.3)
if tat.any():
    cy, cx = np.argwhere(tat).mean(0); dd = np.sqrt(((xx - cx) / (W / 80)) ** 2 + ((yy - cy) / (W / 60)) ** 2); ang = np.arctan2(yy - cy, xx - cx)
    motif = (dd < 0.45) | ((dd < 1.0) & (np.sin(ang * 5.0) > 0.55)) | ((dd > 1.05) & (dd < 1.2))
    out = np.where((motif & tat)[..., None], out * 0.25 + np.array([0.05, 0.04, 0.06]), out); print("tattoo at", int(cx), int(cy))
Image.fromarray((out * 255).astype(np.uint8)).save(OUT)
print("shorts px", int(ms.sum()), "top px", int(mt.sum()), "->", OUT)
