"""Procedurally models Project Shinobi's blockout assets and exports glTF.

Run with either:
    blender --background --python art/blender/build_assets.py -- [options]
    python art/blender/build_assets.py [options]        # needs `pip install -r art/blender/requirements.txt`

Options:
    --out DIR        output directory (default: game/assets/models)
    --only NAME      build a single asset (e.g. gate)
    --save-blend     also write a .blend next to each .glb for hand editing

These are environment *blockouts*: clean, stylised, readable shapes that let
the game be built and play-tested now. Characters are not modelled here: they
come from VRoid Studio as .vrm files (see docs/CHARACTERS.md).

Conventions: 1 unit = 1 metre, props face +Y in Blender (which becomes -Z,
Godot's forward, after glTF export), origins sit on the ground.
"""

from __future__ import annotations

import argparse
import math
import random
import sys
from pathlib import Path

import bpy  # must be imported before bmesh/mathutils when running as a pip module
import bmesh
from mathutils import Euler, Matrix, Vector

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO_ROOT / "game" / "assets" / "models"

# --------------------------------------------------------------------------
# Palette (sRGB, converted to linear on export).
# --------------------------------------------------------------------------
PALETTE = {
    "wood": (0.55, 0.36, 0.20),
    "wood_dark": (0.36, 0.22, 0.12),
    "rope": (0.85, 0.74, 0.48),
    "stone": (0.52, 0.53, 0.55),
    "stone_dark": (0.38, 0.39, 0.42),
    "bark": (0.33, 0.22, 0.14),
    "leaf": (0.20, 0.45, 0.22),
    "leaf_light": (0.30, 0.58, 0.26),
    "gate_red": (0.78, 0.18, 0.10),
    "gate_black": (0.08, 0.08, 0.09),
    "paper": (0.98, 0.93, 0.78),
}


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(name: str) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    # PALETTE is authored in sRGB (what colour pickers show); Blender and
    # glTF store base colour in linear space.
    r, g, b = (srgb_to_linear(c) for c in PALETTE[name])
    bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85
    if name == "paper":
        # Lantern paper glows at night.
        bsdf.inputs["Emission Color"].default_value = (1.0, 0.8, 0.45, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.5
    return mat


class Part:
    """Accumulates primitives into one mesh object whose origin is a joint.

    Primitive positions are given in *world* space (character standing at the
    origin), which keeps proportions easy to read; they are converted to the
    part's local space on build.
    """

    def __init__(self, name: str, origin=(0.0, 0.0, 0.0), parent: "Part | None" = None):
        self.name = name
        self.origin = Vector(origin)
        self.parent = parent
        self.bm = bmesh.new()
        self.materials: list[bpy.types.Material] = []
        self.obj: bpy.types.Object | None = None

    def _mat_index(self, mat_name: str) -> int:
        mat = material(mat_name)
        if mat not in self.materials:
            self.materials.append(mat)
        return self.materials.index(mat)

    def _matrix(self, loc, scale, rot) -> Matrix:
        return (
            Matrix.Translation(Vector(loc) - self.origin)
            @ Euler(rot).to_matrix().to_4x4()
            @ Matrix.Diagonal((*scale, 1.0))
        )

    def _finish(self, verts, mat_name: str, smooth: bool) -> None:
        idx = self._mat_index(mat_name)
        for face in {f for v in verts for f in v.link_faces}:
            face.material_index = idx
            face.smooth = smooth

    def box(self, mat, loc, size, rot=(0, 0, 0)):
        ret = bmesh.ops.create_cube(self.bm, size=1.0, matrix=self._matrix(loc, size, rot))
        self._finish(ret["verts"], mat, smooth=False)
        return self

    def ball(self, mat, loc, size, rot=(0, 0, 0), segments=18, rings=10):
        ret = bmesh.ops.create_uvsphere(
            self.bm, u_segments=segments, v_segments=rings, radius=0.5,
            matrix=self._matrix(loc, size, rot))
        self._finish(ret["verts"], mat, smooth=True)
        return self

    def tube(self, mat, loc, r1, r2, depth, rot=(0, 0, 0), segments=14, smooth=True):
        ret = bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=segments,
            radius1=r1, radius2=r2, depth=depth,
            matrix=self._matrix(loc, (1, 1, 1), rot))
        self._finish(ret["verts"], mat, smooth=smooth)
        return self

    def rock(self, mat, loc, size, seed: int, roughness=0.18):
        rng = random.Random(seed)
        ret = bmesh.ops.create_icosphere(
            self.bm, subdivisions=2, radius=0.5, matrix=self._matrix(loc, size, (0, 0, 0)))
        for v in ret["verts"]:
            v.co += v.co.normalized() * rng.uniform(-roughness, roughness) * min(size)
        self._finish(ret["verts"], mat, smooth=False)
        return self

    def build(self) -> bpy.types.Object:
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for mat in self.materials:
            mesh.materials.append(mat)
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        if self.parent is not None:
            obj.parent = self.parent.obj
            obj.location = self.origin - self.parent.origin
        else:
            obj.location = self.origin
        self.obj = obj
        return obj


def empty(name: str, location=(0, 0, 0), parent=None) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    obj.parent = parent
    return obj


# --------------------------------------------------------------------------
# Assets
# --------------------------------------------------------------------------

def build_training_dummy() -> None:
    """Classic wooden training post with arms and a straw-wrapped head."""
    empty("TrainingDummy")
    post = Part("Post")
    post.tube("wood_dark", (0, 0, 0.08), 0.42, 0.42, 0.16, segments=8, smooth=False)
    post.tube("wood", (0, 0, 0.95), 0.2, 0.18, 1.7)
    post.tube("rope", (0, 0, 1.30), 0.205, 0.205, 0.1)
    post.tube("rope", (0, 0, 0.62), 0.205, 0.205, 0.1)
    post.ball("rope", (0, 0, 1.88), (0.36, 0.36, 0.36))
    for x, z, yaw in ((-0.12, 1.42, -20), (0.12, 1.42, 20), (0.0, 1.05, 0)):
        post.tube("wood_dark", (x, 0.28, z), 0.04, 0.035, 0.5,
                  rot=(math.radians(90), 0, math.radians(yaw)))
    post.build().parent = bpy.data.objects["TrainingDummy"]


def build_rock() -> None:
    empty("Rock")
    r = Part("RockMesh")
    r.rock("stone", (0, 0, 0.35), (1.3, 1.1, 0.9), seed=7)
    r.rock("stone_dark", (0.6, 0.3, 0.2), (0.6, 0.55, 0.45), seed=11)
    r.build().parent = bpy.data.objects["Rock"]


def build_pine() -> None:
    empty("Pine")
    t = Part("PineMesh")
    t.tube("bark", (0, 0, 1.2), 0.22, 0.14, 2.4, segments=8, smooth=False)
    for i, (z, r) in enumerate(((2.0, 1.6), (3.0, 1.25), (3.9, 0.9), (4.7, 0.55))):
        t.tube("leaf" if i % 2 == 0 else "leaf_light", (0, 0, z), r, 0.0, 1.6, segments=9, smooth=False)
    t.build().parent = bpy.data.objects["Pine"]


def build_gate() -> None:
    """A shrine-style gate framing the training ground."""
    empty("Gate")
    g = Part("GateMesh")
    for x in (-2.0, 2.0):
        g.tube("gate_red", (x, 0, 2.0), 0.2, 0.17, 4.0)
        g.tube("gate_black", (x, 0, 0.15), 0.26, 0.26, 0.3)
    g.box("gate_red", (0, 0, 3.35), (4.6, 0.22, 0.22))
    g.box("gate_red", (0, 0, 4.05), (5.4, 0.36, 0.26))
    g.box("gate_black", (0, 0, 4.26), (5.9, 0.42, 0.16))
    g.box("gate_red", (0, 0, 3.7), (0.22, 0.2, 0.5))
    g.build().parent = bpy.data.objects["Gate"]


def build_lantern() -> None:
    empty("Lantern")
    lamp = Part("LanternMesh")
    lamp.box("stone_dark", (0, 0, 0.1), (0.7, 0.7, 0.2))
    lamp.tube("stone", (0, 0, 0.55), 0.12, 0.12, 0.7, segments=8, smooth=False)
    lamp.box("stone", (0, 0, 0.95), (0.55, 0.55, 0.12))
    lamp.box("paper", (0, 0, 1.18), (0.36, 0.36, 0.34))
    lamp.tube("stone_dark", (0, 0, 1.47), 0.5, 0.05, 0.26, segments=4, smooth=False,
              rot=(0, 0, math.radians(45)))
    lamp.build().parent = bpy.data.objects["Lantern"]


ASSETS = {
    "training_dummy": build_training_dummy,
    "rock": build_rock,
    "pine": build_pine,
    "gate": build_gate,
    "lantern": build_lantern,
}


def export(name: str, out_dir: Path, save_blend: bool) -> Path:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ASSETS[name]()
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{name}.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
    )
    if save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=str(out_dir / f"{name}.blend"))
    return path


def parse_args(argv: list[str]) -> argparse.Namespace:
    # Under `blender --python`, our args follow a literal `--`.
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    elif Path(argv[0]).name.startswith("blender"):
        argv = []
    else:
        argv = argv[1:]
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    p.add_argument("--only", choices=sorted(ASSETS))
    p.add_argument("--save-blend", action="store_true")
    return p.parse_args(argv)


def main() -> int:
    args = parse_args(sys.argv)
    names = [args.only] if args.only else list(ASSETS)
    for name in names:
        path = export(name, args.out, args.save_blend)
        print(f"exported {path.relative_to(REPO_ROOT) if path.is_relative_to(REPO_ROOT) else path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
