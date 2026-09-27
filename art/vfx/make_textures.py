"""Generates the particle and effect textures in game/assets/vfx/.

    python art/vfx/make_textures.py

All procedural (numpy + Pillow, fixed seeds), so they're original and
reproducible. Textures are white with the shape in alpha (and a little
shading in the colour): effects tint them per element.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT = REPO_ROOT / "game" / "assets" / "vfx"


def grid(size: int, h: int | None = None):
	h = h or size
	y, x = np.mgrid[0:h, 0:size].astype(np.float64)
	return (x + 0.5) / size * 2 - 1, (y + 0.5) / h * 2 - 1


def fbm(size: int, seed: int, octaves: int = 5, base: int = 4) -> np.ndarray:
	"""Tileable fractal value noise in 0..1."""
	rng = np.random.default_rng(seed)
	out = np.zeros((size, size))
	amp, total = 1.0, 0.0
	for o in range(octaves):
		cells = base * 2 ** o
		lattice = rng.random((cells, cells))
		coords = np.arange(size) / size * cells
		i0 = np.floor(coords).astype(int)
		t = coords - i0
		t = t * t * (3 - 2 * t)
		i1 = (i0 + 1) % cells
		a = lattice[np.ix_(i0, i0)]
		b = lattice[np.ix_(i0, i1)]
		c = lattice[np.ix_(i1, i0)]
		d = lattice[np.ix_(i1, i1)]
		tx = t[None, :]
		ty = t[:, None]
		layer = (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
		out += layer * amp
		total += amp
		amp *= 0.5
	return out / total


def save(name: str, rgb: np.ndarray, alpha: np.ndarray) -> None:
	img = np.dstack([np.clip(rgb, 0, 1)] * 3 if rgb.ndim == 2 else [np.clip(rgb, 0, 1)])
	if img.ndim == 3 and img.shape[2] == 1:
		img = np.repeat(img, 3, axis=2)
	rgba = np.dstack([img, np.clip(alpha, 0, 1)])
	Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(OUT / f"{name}.png")
	print(f"{name}.png {rgba.shape[1]}x{rgba.shape[0]}")


def glow() -> None:
	x, y = grid(128)
	r = np.sqrt(x * x + y * y)
	a = np.clip(1 - r, 0, 1) ** 2.2
	save("glow", np.ones_like(a), a)


def star() -> None:
	"""A hit flash: bright core, four long rays and four short ones."""
	x, y = grid(256)
	r = np.sqrt(x * x + y * y)
	ang = np.arctan2(y, x)
	core = np.exp(-(r / 0.12) ** 2)
	rays = np.abs(np.cos(ang * 2)) ** 60 * np.clip(1 - r, 0, 1) ** 1.5
	short = np.abs(np.cos(ang * 2 + np.pi / 2)) ** 80 * np.clip(1 - r / 0.55, 0, 1) ** 2 * 0.7
	halo = np.exp(-(r / 0.45) ** 2) * 0.35
	a = np.clip(core + rays + short + halo, 0, 1)
	save("star", np.ones_like(a), a)


def ring() -> None:
	"""A shockwave: sharp outer edge, soft inner falloff."""
	x, y = grid(256)
	r = np.sqrt(x * x + y * y)
	outer = np.clip((0.97 - r) / 0.03, 0, 1)
	inner = np.clip((r - 0.45) / 0.5, 0, 1) ** 2.5
	a = outer * inner
	save("ring", np.ones_like(a), a)


def spark() -> None:
	"""An elongated streak (long axis vertical, head at the top)."""
	x, y = grid(32, 128)
	width = 0.18 + 0.35 * np.clip((1 - y) / 2, 0, 1)
	a = np.clip(1 - np.abs(x) / width, 0, 1) ** 2 * np.clip(1 - np.abs(y), 0, 1) ** 0.7
	save("spark", np.ones_like(a), a)


def trail() -> None:
	"""Cross-section of a ribbon trail: bright centre, soft edges (u across)."""
	x, y = grid(64, 8)
	a = np.clip(1 - np.abs(x), 0, 1) ** 1.6
	rgb = 0.75 + 0.25 * np.clip(1 - np.abs(x) * 2, 0, 1)
	save("trail", rgb, a)


def slash() -> None:
	"""A crescent sword/wind slash: bright leading edge, fading tail."""
	w, h = 256, 128
	x, y = grid(w, h)
	# Circle centred below the image; the arc is the band near radius 1.
	cx, cy = 0.0, 1.4
	px, py = x, y * (h / w) * 2
	r = np.sqrt((px - cx) ** 2 + (py - cy) ** 2)
	ang = np.arctan2(px - cx, -(py - cy))
	band = np.clip(1 - np.abs(r - 1.5) / 0.34, 0, 1) ** 1.2
	edge = np.clip((1.78 - r) / 0.04, 0, 1)
	along = np.clip(1 - np.abs(ang) / 1.05, 0, 1) ** 0.7
	lead = np.clip((ang + 0.95) / 1.9, 0, 1) ** 1.3
	a = band * edge * along * (0.25 + 0.75 * lead)
	rgb = 0.7 + 0.3 * np.clip((r - 1.4) / 0.3, 0, 1)
	save("slash", rgb, a)


def puff(seed: int, size: int = 256) -> tuple[np.ndarray, np.ndarray]:
	"""A single cloud puff: overlapping blobs with noisy edges, lit from above."""
	rng = np.random.default_rng(seed)
	x, y = grid(size)
	dens = np.zeros_like(x)
	for _ in range(7):
		cx, cy = rng.uniform(-0.3, 0.3, 2)
		rr = rng.uniform(0.38, 0.58)
		dens += np.exp(-((x - cx) ** 2 + (y - cy) ** 2) / (rr * rr))
	n = fbm(size, seed + 100, octaves=5, base=3)
	dens = dens * (0.55 + 0.9 * n)
	fall = np.clip(1 - np.sqrt(x * x + y * y), 0, 1) ** 0.8
	a = np.clip((dens - 0.45) * 1.2, 0, 1) * fall
	light = 0.72 + 0.28 * np.clip(-y * 0.8 - x * 0.3 + (n - 0.5), -1, 1)
	return light, a


def flame(seed: int, size: int = 256) -> tuple[np.ndarray, np.ndarray]:
	"""A flame tongue: wide soft base, pointed flickering tip, hot core."""
	x, y = grid(size)
	n = fbm(size, seed, octaves=4, base=3)
	yy = (1 - y) / 2  # 0 at bottom, 1 at top
	wobble = (n - 0.5) * 0.35 * yy
	half = 0.9 * (1 - yy) ** 0.7 * np.clip(yy * 3, 0, 1) ** 0.4
	d = np.abs(x + wobble) / np.maximum(half, 1e-3)
	a = np.clip(1 - d, 0, 1) ** 0.9 * np.clip(1 - yy, 0, 1) ** 0.3 * np.clip(yy * 5, 0, 1)
	a *= 0.75 + 0.5 * n
	core = np.clip(1 - d * 1.6, 0, 1) * np.clip(1 - yy * 1.3, 0, 1)
	return 0.55 + 0.45 * core, np.clip(a, 0, 1)


def atlas(name: str, maker) -> None:
	tiles = [maker(s) for s in (1, 2, 3, 4)]
	rgb = np.block([[tiles[0][0], tiles[1][0]], [tiles[2][0], tiles[3][0]]])
	a = np.block([[tiles[0][1], tiles[1][1]], [tiles[2][1], tiles[3][1]]])
	save(name, rgb, a)


def noise() -> None:
	n = fbm(256, 77, octaves=6, base=4)
	n = (n - n.min()) / (n.max() - n.min())
	save("noise", n, np.ones_like(n))


def main() -> int:
	OUT.mkdir(parents=True, exist_ok=True)
	glow()
	star()
	ring()
	spark()
	trail()
	slash()
	atlas("smoke", puff)
	atlas("flame", flame)
	noise()
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
