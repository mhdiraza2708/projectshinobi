"""Shrinks a VRM's embedded textures for the game, keeping everything else.

    python art/characters/prepare_vrm.py IN.vrm OUT.vrm [--max 1024] [--normal-max 512]

VRoid exports carry 2048px textures and a 2048px thumbnail, about 15-20 MB
per character. At game camera distances 1024px (normal maps 512px) looks the
same and makes the file about a third the size. The GLB is rewritten with
the smaller PNGs; meshes, skeleton, materials, spring bones, expressions and
the licence metadata are untouched.

Needs pillow (pip install pillow).
"""

from __future__ import annotations

import argparse
import io
import json
import struct
from pathlib import Path

from PIL import Image


def read_glb(data: bytes) -> tuple[dict, bytes]:
    magic, _version, _length = struct.unpack("<4sII", data[:12])
    if magic != b"glTF":
        raise SystemExit("not a GLB/VRM file")
    clen, _ = struct.unpack("<II", data[12:20])
    js = json.loads(data[20:20 + clen])
    off = 20 + clen
    blen, _ = struct.unpack("<II", data[off:off + 8])
    return js, data[off + 8:off + 8 + blen]


def write_glb(js: dict, binary: bytes) -> bytes:
    text = json.dumps(js, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    return (struct.pack("<4sII", b"glTF", 2, total)
            + struct.pack("<II", len(text), 0x4E4F534A) + text
            + struct.pack("<II", len(binary), 0x004E4942) + binary)


def shrink(png: bytes, limit: int) -> bytes:
    im = Image.open(io.BytesIO(png))
    if max(im.size) <= limit:
        return png
    scale = limit / max(im.size)
    im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
    out = io.BytesIO()
    im.save(out, "PNG", optimize=True)
    return out.getvalue()


def prepare(src: Path, dst: Path, limit: int, normal_limit: int) -> None:
    js, binary = read_glb(src.read_bytes())
    views = js["bufferViews"]
    replaced: dict[int, bytes] = {}
    thumb = None
    meta = js.get("extensions", {}).get("VRM", {}).get("meta", {})
    if isinstance(meta.get("texture"), int) and meta["texture"] >= 0:
        thumb = js["textures"][meta["texture"]]["source"]
    for i, img in enumerate(js.get("images", [])):
        if "bufferView" not in img:
            continue
        view = views[img["bufferView"]]
        raw = binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]]
        name = img.get("name", "").lower()
        cap = 128 if i == thumb else normal_limit if name.endswith("_nml") or "normal" in name else limit
        replaced[img["bufferView"]] = shrink(raw, cap)

    # Repack every buffer view, in order, 4-byte aligned.
    out = bytearray()
    for i, view in enumerate(views):
        if view.get("buffer", 0) != 0:
            continue
        chunk = replaced.get(i)
        if chunk is None:
            chunk = binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]]
        out += b"\0" * (-len(out) % 4)
        view["byteOffset"] = len(out)
        view["byteLength"] = len(chunk)
        out += chunk
    js["buffers"][0]["byteLength"] = len(out)
    dst.write_bytes(write_glb(js, bytes(out)))
    print(f"{src.name}: {src.stat().st_size // 1024} KB -> {dst.stat().st_size // 1024} KB")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", type=Path)
    ap.add_argument("dst", type=Path)
    ap.add_argument("--max", type=int, default=1024, help="largest texture side (default 1024)")
    ap.add_argument("--normal-max", type=int, default=512, help="largest normal-map side (default 512)")
    args = ap.parse_args()
    prepare(args.src, args.dst, args.max, args.normal_max)


if __name__ == "__main__":
    main()
