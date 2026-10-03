"""Downloads the Poly Haven assets the game uses and packs them for Godot.

    python art/polyhaven/fetch.py [--cache DIR] [--only skies|ground]

Everything on Poly Haven (https://polyhaven.com) is CC0: photographed and
scanned by real people, free for any use. Needs numpy and Pillow, and network
access to api.polyhaven.com and dl.polyhaven.org. Downloads are cached (by
default in art/polyhaven/.cache, which git ignores), so re-running only
re-packs.

What it writes:

- Skies (game/assets/skies/<mood>.jpg + game/data/skies.json): a pure-sky
  HDRI per time of day and weather, tone-scaled into an 8-bit panorama with
  its scale, sun position and colours recorded so the sky shader can bring
  back the light levels and the sun can be lined up with the sun in the
  photo.
- Ground (game/assets/textures/ground/<layer>_albedo.jpg and _normal.jpg):
  photo-scanned surfaces for the terrain shader. Ambient occlusion is folded
  into the colour; the normal map carries the surface height in its blue
  channel (Godot rebuilds a normal's Z itself) for height-blended layers.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
GAME = REPO / "game"
API = "https://api.polyhaven.com"

# mood -> HDRI. "overcast" is used in rain and storms, "snow" in snowfall.
SKIES = {
	"day": "kloofendal_48d_partly_cloudy_puresky",
	"dawn": "kloppenheim_06_puresky",
	"dusk": "table_mountain_1_puresky",
	"night": "kloppenheim_02_puresky",
	"overcast": "overcast_soil_puresky",
	"snow": "snow_field_puresky",
}
SKY_WIDTH = 4096

# terrain layer -> texture (its real size comes from the asset's metadata).
GROUND = {
	"grass": "forrest_ground_01",
	"dirt": "forest_ground_04",
	"rock": "rock_face_03",
	"sand": "coast_sand_01",
	"snow": "snow_02",
}
GROUND_ALBEDO = "2k"
GROUND_NORMAL = "1k"
# How much of the scanned ambient occlusion goes into the colour.
AO_STRENGTH = 0.6

IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality={hq}
compress/normal_map=2
mipmaps/generate=true
detect_3d/compress_to=0
"""


def fetch(url: str, dest: Path) -> Path:
	if dest.exists() and dest.stat().st_size > 0:
		return dest
	dest.parent.mkdir(parents=True, exist_ok=True)
	print(f"  downloading {url}")
	req = urllib.request.Request(url, headers={"User-Agent": "projectshinobi-art-pipeline"})
	with urllib.request.urlopen(req) as r:
		data = r.read()
	dest.write_bytes(data)
	return dest


def api(path: str, cache: Path) -> dict:
	dest = cache / "api" / (path.strip("/").replace("/", "_") + ".json")
	fetch(f"{API}/{path}", dest)
	return json.loads(dest.read_text())


# --- Radiance .hdr --------------------------------------------------------------


def read_hdr(path: Path) -> np.ndarray:
	"""Float32 RGB from a Radiance RGBE file (new-style run-length encoding)."""
	data = path.read_bytes()
	i = 0
	while True:
		j = data.index(b"\n", i)
		line = data[i:j]
		i = j + 1
		m = re.match(rb"-Y (\d+) \+X (\d+)", line)
		if m:
			h, w = int(m[1]), int(m[2])
			break
	buf = np.frombuffer(data, np.uint8, offset=i)
	out = np.empty((h, w, 4), np.uint8)
	p = 0
	for y in range(h):
		if not (buf[p] == 2 and buf[p + 1] == 2):
			out[y] = buf[p:p + w * 4].reshape(w, 4)
			p += w * 4
			continue
		p += 4
		for c in range(4):
			x = 0
			row = out[y, :, c]
			while x < w:
				n = int(buf[p])
				p += 1
				if n > 128:
					n -= 128
					row[x:x + n] = buf[p]
					p += 1
				else:
					row[x:x + n] = buf[p:p + n]
					p += n
				x += n
	e = out[..., 3].astype(np.int32)
	scale = np.where(e > 0, np.ldexp(1.0, e - 136), 0.0).astype(np.float32)
	return out[..., :3].astype(np.float32) * scale[..., None]


def luminance(rgb: np.ndarray) -> np.ndarray:
	return rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32)


def to_srgb(lin: np.ndarray) -> np.ndarray:
	lin = np.clip(lin, 0.0, 1.0)
	return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)


def box_blur(img: np.ndarray, r: int) -> np.ndarray:
	"""Separable box blur, wrapping horizontally like a panorama."""
	k = 2 * r + 1
	pad = np.concatenate([img[:, -r:], img, img[:, :r]], axis=1)
	c = np.cumsum(np.pad(pad, ((0, 0), (1, 0)) + ((0, 0),) * (img.ndim - 2)), axis=1)
	img = (c[:, k:] - c[:, :-k]) / k
	pad = np.concatenate([np.repeat(img[:1], r, 0), img, np.repeat(img[-1:], r, 0)], axis=0)
	c = np.cumsum(np.pad(pad, ((1, 0), (0, 0)) + ((0, 0),) * (img.ndim - 2)), axis=0)
	return (c[k:] - c[:-k]) / k


def make_sky(mood: str, asset: str, cache: Path) -> dict:
	print(f"sky {mood}: {asset}")
	files = api(f"files/{asset}", cache)
	url = files["hdri"]["4k"]["hdr"]["url"]
	rgb = read_hdr(fetch(url, cache / "hdri" / Path(url).name))
	h, w, _ = rgb.shape
	lum = luminance(rgb)
	# The sun (or moon): the brightest spot once single hot pixels and
	# stars are blurred away.
	small = box_blur(lum, 3)
	y, x = np.unravel_index(np.argmax(small), small.shape)
	sun_uv = [(x + 0.5) / w, (y + 0.5) / h]
	# Its colour, from the ring just around the disc (the disc itself clips).
	yy, xx = np.mgrid[0:h, 0:w]
	dx = np.minimum(np.abs(xx - x), w - np.abs(xx - x))
	dist = np.hypot(dx, yy - y)
	disc = dist < w * 0.004
	ring = (dist >= w * 0.004) & (dist < w * 0.02)
	sun_rgb = rgb[ring].mean(axis=0)
	sun_rgb = sun_rgb / max(sun_rgb.max(), 1e-6)
	# Brightness: map the brightest sky (sun aside) to just under white, so
	# bright clouds keep their detail in 8 bits; `scale` brings it back.
	sky_lum = lum[(~disc) & (np.arange(h)[:, None] < h // 2)]
	white = float(np.percentile(sky_lum, 99.7))
	a = 0.97 / max(white, 1e-6)
	img = to_srgb(rgb * a)
	out = Image.fromarray((img * 255.0 + 0.5).astype(np.uint8))
	if w != SKY_WIDTH:
		out = out.resize((SKY_WIDTH, SKY_WIDTH // 2), Image.LANCZOS)
	dest = GAME / "assets" / "skies" / f"{mood}.jpg"
	dest.parent.mkdir(parents=True, exist_ok=True)
	out.save(dest, quality=92, subsampling=0)
	write_import(dest, high_quality=True)
	# Reference colours, in the panorama's linear units (times `scale` =
	# the HDRI's own): the horizon (fog), the upper sky and the ground.
	band = lambda v0, v1: (rgb[int(h * v0):int(h * v1)] * a).reshape(-1, 3).mean(axis=0)
	upper = rgb[: h // 2] * a
	# Cosine-weighted light from the upper hemisphere, sun excluded: what the
	# sky alone puts on the ground.
	theta = (np.arange(h // 2) + 0.5) / h * np.pi
	wgt = (np.cos(theta) * np.sin(theta))[:, None]
	no_sun = np.where(disc[: h // 2, :, None], 0.0, upper)
	ambient = (no_sun * wgt[..., None]).sum(axis=(0, 1)) / (wgt.sum() * w)
	info = {
		"asset": asset,
		"name": api(f"info/{asset}", cache)["name"],
		"scale": round(1.0 / a, 5),
		"sun_uv": [round(sun_uv[0], 5), round(sun_uv[1], 5)],
		"sun_elevation": round(90.0 - sun_uv[1] * 180.0, 2),
		"sun_color": [round(float(c), 4) for c in sun_rgb],
		"sun_peak": round(float(lum.max()), 1),
		"horizon": [round(float(c), 4) for c in band(0.46, 0.5)],
		"zenith": [round(float(c), 4) for c in band(0.0, 0.12)],
		"ground": [round(float(c), 4) for c in band(0.55, 0.75)],
		"ambient": [round(float(c), 4) for c in ambient],
	}
	print(f"  sun at elevation {info['sun_elevation']}, scale {info['scale']}")
	return info


# --- Ground -----------------------------------------------------------------------


def texture_url(files: dict, kind: str, res: str) -> str:
	formats = files[kind][res]
	for ext in ("jpg", "png"):
		if ext in formats:
			return formats[ext]["url"]
	raise KeyError(f"{kind} {res}: no jpg or png")


def load(path: Path, mode: str) -> np.ndarray:
	img = Image.open(path)
	if img.mode in ("I;16", "I;16B", "I"):
		arr = np.asarray(img, np.float32) / 65535.0
		return arr if mode == "L" else np.repeat(arr[..., None], 3, -1)
	return np.asarray(img.convert(mode), np.float32) / 255.0


def make_ground(layer: str, asset: str, cache: Path) -> dict:
	print(f"ground {layer}: {asset}")
	files = api(f"files/{asset}", cache)
	info = api(f"info/{asset}", cache)
	get = lambda kind, res: fetch(texture_url(files, kind, res), cache / "tex" / asset / f"{kind}_{res}{Path(texture_url(files, kind, res)).suffix}")
	diff = load(get("Diffuse", GROUND_ALBEDO), "RGB")
	ao = load(get("AO", GROUND_ALBEDO), "L") if "AO" in files else np.ones(diff.shape[:2], np.float32)
	if ao.shape != diff.shape[:2]:
		ao = np.asarray(Image.fromarray((ao * 255).astype(np.uint8)).resize(diff.shape[1::-1], Image.BILINEAR), np.float32) / 255.0
	albedo = diff * (1.0 - AO_STRENGTH + AO_STRENGTH * ao)[..., None]
	out_dir = GAME / "assets" / "textures" / "ground"
	out_dir.mkdir(parents=True, exist_ok=True)
	dest = out_dir / f"{layer}_albedo.jpg"
	Image.fromarray((np.clip(albedo, 0, 1) * 255 + 0.5).astype(np.uint8)).save(dest, quality=90, subsampling=0)
	write_import(dest, high_quality=False)

	nor = load(get("nor_gl", GROUND_NORMAL), "RGB")
	disp = load(get("Displacement", GROUND_NORMAL), "L")
	if disp.shape != nor.shape[:2]:
		disp = np.asarray(Image.fromarray((disp * 255).astype(np.uint8)).resize(nor.shape[1::-1], Image.BILINEAR), np.float32) / 255.0
	# Stretch the height to the full range: blending compares layers' heights.
	lo, hi = np.percentile(disp, 1), np.percentile(disp, 99)
	disp = np.clip((disp - lo) / max(hi - lo, 1e-6), 0, 1)
	packed = np.dstack([nor[..., 0], nor[..., 1], disp])
	dest = out_dir / f"{layer}_normal.jpg"
	Image.fromarray((packed * 255 + 0.5).astype(np.uint8)).save(dest, quality=94, subsampling=0)
	write_import(dest, high_quality=True)
	size_m = float(info.get("dimensions", [2000])[0]) / 1000.0
	return {"asset": asset, "name": info["name"], "size": round(size_m, 3),
		"authors": sorted(info.get("authors", {}).keys())}


def write_import(path: Path, high_quality: bool) -> None:
	"""A starting .import for Godot: VRAM-compressed with mipmaps (Godot
	fills in the rest on the next import). An existing one is kept."""
	imp = path.with_name(path.name + ".import")
	if not imp.exists():
		imp.write_text(IMPORT_TEMPLATE.format(hq="true" if high_quality else "false"))


def main() -> int:
	p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	p.add_argument("--cache", type=Path, default=Path(__file__).resolve().parent / ".cache")
	p.add_argument("--only", choices=["skies", "ground"])
	args = p.parse_args()
	manifest_path = GAME / "data" / "skies.json"
	if args.only in (None, "skies"):
		skies = {mood: make_sky(mood, asset, args.cache) for mood, asset in SKIES.items()}
		manifest_path.write_text(json.dumps({"skies": skies}, indent="\t") + "\n")
	if args.only in (None, "ground"):
		ground = {layer: make_ground(layer, asset, args.cache) for layer, asset in GROUND.items()}
		(GAME / "data" / "ground.json").write_text(json.dumps({"ground": ground}, indent="\t") + "\n")
	return 0


if __name__ == "__main__":
	sys.exit(main())
