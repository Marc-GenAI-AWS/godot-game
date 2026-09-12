# Paint swimwear variants for the crowd onto the Quaternius female and male
# skin textures, in UV space, by body height bands (same method as the player).
import json, numpy as np, os
from PIL import Image, ImageFilter
SRC = "/home/marc/dev/graphics-gen/assets/ubc/pack/base/"
OUT = "/home/marc/dev/graphics-gen/game/segments/characters/assets/"
W = 1024

def load(gltf, bin_):
    g = json.load(open(gltf)); b = open(bin_, "rb").read()
    def acc(i):
        a = g["accessors"][i]; bv = g["bufferViews"][a["bufferView"]]; off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        ct = {5126: ("f4", 4), 5123: ("u2", 2), 5121: ("u1", 1), 5125: ("u4", 4)}[a["componentType"]]; n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        stride = bv.get("byteStride", ct[1] * n)
        if stride == ct[1] * n: arr = np.frombuffer(b, dtype=ct[0], count=a["count"] * n, offset=off)
        else: arr = np.array([np.frombuffer(b, dtype=ct[0], count=n, offset=off + k * stride) for k in range(a["count"])]).reshape(-1)
        return arr.reshape(a["count"], n)
    return g, acc

def rasterise(g, acc, mesh_name):
    m = [m for m in g["meshes"] if m["name"] == mesh_name][0]; p = m["primitives"][0]
    pos = acc(p["attributes"]["POSITION"]).astype(np.float64); uv = acc(p["attributes"]["TEXCOORD_0"]).astype(np.float64)
    j = acc(p["attributes"]["JOINTS_0"]); w = acc(p["attributes"]["WEIGHTS_0"]); idx = acc(p["indices"]).reshape(-1, 3)
    names = [g["nodes"][x]["name"] for x in g["skins"][0]["joints"]]
    dom = np.array([names[k] for k in j[np.arange(len(j)), w.argmax(1)]])
    rid = {"pelvis": 1, "thigh_l": 2, "thigh_r": 3, "spine_01": 4, "spine_02": 5, "spine_03": 6, "calf_l": 7, "calf_r": 8, "upperarm_l": 9, "upperarm_r": 10, "lowerarm_l": 11, "lowerarm_r": 12, "clavicle_l": 13, "clavicle_r": 14}
    ymap = np.full((W, W), np.nan); region = np.zeros((W, W), dtype=np.int16)
    for tri in idx:
        uvs = uv[tri] * W; ys = pos[tri, 1]
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
        ymap[y0:y1 + 1, x0:x1 + 1][inside] = (l0 * ys[0] + l1 * ys[1] + l2 * ys[2])[inside]
        doms = [dom[v] for v in tri]; region[y0:y1 + 1, x0:x1 + 1][inside] = rid.get(max(set(doms), key=doms.count), 0)
    return np.where(np.isfinite(ymap), ymap, -10), region, pos[:, 1].max()

def clean(mask, blur=2.0):
    im = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(blur))
    return (np.asarray(im).astype(np.float32) / 255.0 > 0.5).astype(np.float32)

def grey_mask(base):
    hsv = np.asarray(base.convert("HSV")).astype(np.float32) / 255.0
    return (hsv[..., 1] < 0.12) & (hsv[..., 2] > 0.45)

def fabric(color, rng, pattern=None):
    yy, xx = np.mgrid[0:W, 0:W]
    col = np.tile(np.array(color, dtype=np.float32), (W, W, 1))
    if pattern == "stripes":
        col = np.where(((xx // 12) % 2 == 0)[..., None], col, col * 0.7 + 0.25)
    elif pattern == "floral":
        n2 = np.asarray(Image.fromarray((rng.random((W // 12, W // 12)) * 255).astype(np.uint8)).resize((W, W), Image.BICUBIC)).astype(np.float32) / 255.0
        col = np.where((n2 > 0.6)[..., None], np.array([0.98, 0.85, 0.3]), col)
        col = np.where((n2 < 0.32)[..., None], np.array([0.95, 0.95, 0.9]), col)
    return col

def paint(base_arr, masks_cols, tint):
    out = np.clip(base_arr * np.array(tint, dtype=np.float32), 0, 1)
    for m, col in masks_cols:
        edge = m - np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5))).astype(np.float32) / 255.0
        c = np.where((edge > 0.5)[..., None], col * 0.75, col)
        out = out * (1 - m[..., None]) + c * m[..., None]
    return out

rng = np.random.default_rng(11)
# ---------------- female ----------------
g, acc = load(SRC + "godot/Superhero_Female_FullBody.gltf", SRC + "godot/Superhero_Female_FullBody.bin")
y, region, H = rasterise(g, acc, "Superhero_Female")
base = Image.open(SRC + "Textures/T_Superhero_Female_Light_BaseColor.png").convert("RGB").resize((W, W), Image.LANCZOS)
arr = np.asarray(base).astype(np.float32) / 255.0
yy, xx = np.mgrid[0:W, 0:W]
grey = grey_mask(base)
grey_top = grey & (xx < W * 0.54) & (yy < W * 0.93)
grey_bot = grey & ~grey_top
top_band = (np.isin(region, [5, 6]) & (y > 0.705 * H) & (y < 0.77 * H)) | grey_top
bot_band = (np.isin(region, [1, 2, 3]) & (y > 0.455 * H) & (y < 0.545 * H)) | grey_bot
one_piece = (np.isin(region, [1, 4, 5, 6]) & (y > 0.455 * H) & (y < 0.79 * H)) | grey
mt, mb, mo = clean(top_band), clean(bot_band), clean(one_piece)
variants = [
    ("F_bikini_pink", [(mt, fabric([0.95, 0.35, 0.55], rng)), (mb, fabric([0.95, 0.35, 0.55], rng))]),
    ("F_bikini_teal", [(mt, fabric([0.15, 0.65, 0.65], rng)), (mb, fabric([0.15, 0.65, 0.65], rng))]),
    ("F_bikini_black", [(mt, fabric([0.08, 0.08, 0.1], rng)), (mb, fabric([0.08, 0.08, 0.1], rng))]),
    ("F_bikini_floral", [(mt, fabric([0.2, 0.4, 0.8], rng, "floral")), (mb, fabric([0.2, 0.4, 0.8], rng, "floral"))]),
    ("F_onepiece_red", [(mo, fabric([0.85, 0.15, 0.2], rng))]),
    ("F_onepiece_navy", [(mo, fabric([0.1, 0.18, 0.45], rng, "stripes"))]),
]
for name, mc in variants:
    Image.fromarray((paint(arr, mc, [1.0, 0.97, 0.93]) * 255).astype(np.uint8)).resize((512, 512), Image.LANCZOS).save(OUT + "T_%s.png" % name)
    print("wrote", name)
# ---------------- male ----------------
g, acc = load(SRC + "godot/Superhero_Male_FullBody.gltf", SRC + "godot/Superhero_Male_FullBody.bin")
body_name = [m["name"] for m in g["meshes"] if "Retopology" in m["name"] or "Male" in m["name"]][0]
y, region, H = rasterise(g, acc, body_name)
base = Image.open(SRC + "Textures/T_Superhero_Male_Ligh.png").convert("RGB").resize((W, W), Image.LANCZOS)
arr = np.asarray(base).astype(np.float32) / 255.0
grey = grey_mask(base)
trunks = (np.isin(region, [1, 2, 3]) & (y > 0.42 * H) & (y < 0.555 * H)) | grey
mtr = clean(trunks)
for name, col, pat in [("M_trunks_blue", [0.15, 0.3, 0.75], None), ("M_trunks_red", [0.8, 0.15, 0.15], None), ("M_trunks_floral", [0.1, 0.45, 0.4], "floral"), ("M_trunks_black", [0.08, 0.08, 0.1], "stripes")]:
    Image.fromarray((paint(arr, [(mtr, fabric(col, rng, pat))], [1.0, 0.97, 0.93]) * 255).astype(np.uint8)).resize((512, 512), Image.LANCZOS).save(OUT + "T_%s.png" % name)
    print("wrote", name, "body mesh", body_name, "H", round(H, 2))


# ---------------- casual clothes (street pedestrians) ----------------
def casual_masks(y, region, H):
    tee = (np.isin(region, [4, 5, 6, 13, 14]) & (y > 0.55 * H) & (y < 0.86 * H)) | (np.isin(region, [9, 10]) & (y > 0.72 * H))
    shorts = np.isin(region, [1, 2, 3]) & (y > 0.34 * H) & (y < 0.6 * H)
    jeans = (np.isin(region, [1, 2, 3, 7, 8]) & (y > 0.06 * H) & (y < 0.6 * H))
    return clean(tee), clean(shorts), clean(jeans)

for sex, gltf, bin_, mesh_name, tex in [
    ("F", "godot/Superhero_Female_FullBody.gltf", "godot/Superhero_Female_FullBody.bin", "Superhero_Female", "Textures/T_Superhero_Female_Light_BaseColor.png"),
    ("M", "godot/Superhero_Male_FullBody.gltf", "godot/Superhero_Male_FullBody.bin", None, "Textures/T_Superhero_Male_Ligh.png")]:
    g, acc = load(SRC + gltf, SRC + bin_)
    if mesh_name is None:
        mesh_name = [m["name"] for m in g["meshes"] if "Retopology" in m["name"]][0]
    y, region, H = rasterise(g, acc, mesh_name)
    base = Image.open(SRC + tex).convert("RGB").resize((W, W), Image.LANCZOS)
    arr = np.asarray(base).astype(np.float32) / 255.0
    grey = grey_mask(base)
    tee, shorts, jeans = casual_masks(y, region, H)
    jeans = np.clip(jeans + grey, 0, 1); shorts = np.clip(shorts + grey, 0, 1)
    sets = [
        ("tee_white_jeans", [(jeans, fabric([0.2, 0.28, 0.45], rng)), (tee, fabric([0.93, 0.93, 0.9], rng))]),
        ("tee_red_shorts", [(shorts, fabric([0.35, 0.33, 0.3], rng)), (tee, fabric([0.75, 0.15, 0.15], rng))]),
        ("tee_navy_chinos", [(jeans, fabric([0.7, 0.62, 0.48], rng)), (tee, fabric([0.12, 0.18, 0.4], rng))]),
        ("tee_green_shorts", [(shorts, fabric([0.16, 0.2, 0.3], rng)), (tee, fabric([0.2, 0.5, 0.35], rng, "stripes"))]),
        ("tee_black_jeans", [(jeans, fabric([0.1, 0.1, 0.12], rng)), (tee, fabric([0.5, 0.2, 0.55], rng))]),
    ]
    for name, mc in sets:
        Image.fromarray((paint(arr, mc, [1.0, 0.97, 0.93]) * 255).astype(np.uint8)).resize((512, 512), Image.LANCZOS).save(OUT + "T_%s_%s.png" % (sex, name))
        print("wrote", sex, name)
