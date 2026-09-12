import numpy as np
from PIL import Image, ImageFilter
W = 2048
ymap = np.load("ymap.npy"); region = np.load("region.npy"); zn = np.load("zn.npy")
valid = np.isfinite(ymap); y = np.where(valid, ymap, -10)
src = "/home/marc/dev/graphics-gen/assets/ubc/pack/base/Textures/T_Superhero_Female_Light_BaseColor.png"
base = Image.open(src).convert("RGB"); arr = np.asarray(base).astype(np.float32) / 255.0
arr = np.clip(arr * np.array([1.06, 1.02, 0.97], dtype=np.float32), 0, 1)
lum = arr.mean(-1, keepdims=True)
arr = np.clip(arr * 0.9 + lum * 0.1, 0, 1)   # slightly less saturated
hsv = np.asarray(base.convert("HSV")).astype(np.float32) / 255.0
grey = (hsv[..., 1] < 0.12) & (hsv[..., 2] > 0.45)
yy, xx = np.mgrid[0:W, 0:W]
grey_top = grey & (xx < 1100) & (yy < 1900)
grey_shorts = grey & ~grey_top
# garments by body height, clean edges from the interpolated height map
shorts = (np.isin(region, [1, 2, 3, 4]) & (y > 0.755) & (y < 1.045)) | grey_shorts
top = (np.isin(region, [5, 6]) & (y > 1.215) & (y < 1.40)) | grey_top
def clean(mask, blur=3.0):
    im = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(blur))
    return (np.asarray(im).astype(np.float32) / 255.0 > 0.5).astype(np.float32)
ms = clean(shorts); mt = clean(top)
rng = np.random.default_rng(3)
grain = np.asarray(Image.fromarray(((rng.normal(0, 1, (W, W)) * 0.5 + 0.5) * 255).clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255.0
denim = np.stack([0.5 + 0.10 * grain, 0.6 + 0.10 * grain, 0.77 + 0.08 * grain], -1)
denim = np.clip(denim + (np.sin(xx * 1.7) * np.sin(yy * 1.7) * 0.04)[..., None], 0, 1)
# hem / waistband bands: frayed lighter hem near the bottom edge of the shorts region (by height), darker waistband at the top
hem_band = ms * ((y > 0.755) & (y < 0.785)).astype(np.float32)
waist_band = ms * ((y > 1.015) & (y < 1.045)).astype(np.float32)
denim = np.where(hem_band[..., None] > 0.5, denim * 0.7 + 0.28, denim)
denim = np.where(waist_band[..., None] > 0.5, denim * 0.86, denim)
# seams: darker lines where the mesh normal flips side (left/right seam ≈ |nx| large) approximated by grey edge of mask
edge = ms - np.asarray(Image.fromarray((ms * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(7))).astype(np.float32) / 255.0
denim = np.where((edge > 0.5)[..., None] & (hem_band < 0.5)[..., None], denim * 0.8, denim)
# floral top
n1 = np.asarray(Image.fromarray(rng.random((W // 4, W // 4)).astype(np.float32) * 255).resize((W, W), Image.BICUBIC)).astype(np.float32) / 255.0
n2 = np.asarray(Image.fromarray((rng.random((W // 12, W // 12)) * 255).astype(np.uint8)).resize((W, W), Image.BICUBIC)).astype(np.float32) / 255.0
pink = np.array([0.93, 0.5, 0.6]); petal = np.array([0.8, 0.18, 0.32]); leaf = np.array([0.55, 0.62, 0.45]); cream = np.array([0.98, 0.9, 0.9])
top_col = np.tile(pink, (W, W, 1)).astype(np.float32)
top_col = np.where((n2 > 0.62)[..., None], petal, top_col)
top_col = np.where((n2 < 0.3)[..., None], leaf, top_col)
top_col = np.where((n1 > 0.82)[..., None], cream, top_col)
top_edge = mt - np.asarray(Image.fromarray((mt * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(9))).astype(np.float32) / 255.0
top_col = np.where((top_edge > 0.5)[..., None], top_col * 0.5 + 0.45, top_col)   # lace-ish lighter trim
out = arr * (1 - ms[..., None]) + denim * ms[..., None]
out = out * (1 - mt[..., None]) + top_col * mt[..., None]
# tattoo: small dark motif on the back of the right thigh (region 3, back-facing, just below the shorts)
tat_zone = (region == 3) & (y > 0.62) & (y < 0.72) & (zn < -0.3)
if tat_zone.any():
    cy, cx = np.argwhere(tat_zone).mean(0)
    d = np.sqrt(((xx - cx) / 26.0) ** 2 + ((yy - cy) / 34.0) ** 2)
    ang = np.arctan2(yy - cy, xx - cx)
    motif = (d < 0.45) | ((d < 1.0) & (np.sin(ang * 5.0) > 0.55)) | ((d > 1.05) & (d < 1.2))
    out = np.where((motif & tat_zone)[..., None], out * 0.25 + np.array([0.05, 0.04, 0.06]), out)
    print("tattoo at", int(cx), int(cy))
Image.fromarray((out * 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS).save("/home/marc/dev/graphics-gen/beach/characters/assets/T_Player_BaseColor.png")
print("shorts px", int(ms.sum()), "top px", int(mt.sum()))
