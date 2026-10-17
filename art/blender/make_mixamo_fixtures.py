"""Builds test fixtures that follow Mixamo's conventions (mixamorig: bone
names, T-pose, armature-only "Without Skin" FBX, 30 fps) so the Mixamo
retargeting pipeline can be tested without redistributing Mixamo files.

    python art/blender/make_mixamo_fixtures.py [OUT_DIR]

Default OUT_DIR: game/tests/fixtures/mixamo (idle, run and jump). A second
folder beside it, OUT_DIR + "_land", gets the same jump plus a land clip of
its own (a separate land.fbx wins over the jump's landing). Afterwards run
`godot --headless --path game --import`, then
`godot --headless --path game --script res://tools/setup_mixamo.gd -- --dir=res://tests/fixtures/mixamo`
and the same with `--dir=res://tests/fixtures/mixamo_land`, then import again.

The jump is a standing leap in one clip, shaped like Mixamo's "Jumping" and
with its hips' height baked in: standing, a crouch, a push-off, toes leaving
the ground, an airborne tuck with the hips rising, the legs reaching for the
ground, and a deep landing crouch. See JUMP_FRAMES for when each happens.
"""
import math
import sys
from pathlib import Path

import bpy  # noqa: F401  (must precede mathutils when running as a module)
from mathutils import Euler, Matrix, Vector

REPO_ROOT = Path(__file__).resolve().parents[2]
out_dir = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else str(REPO_ROOT / "game/tests/fixtures/mixamo")
Path(out_dir).mkdir(parents=True, exist_ok=True)

J = {  # name: (head, parent)  -- Blender coords, character faces -Y like an imported Mixamo FBX
 "Hips": ((0,0,1.0), None), "Spine": ((0,0,1.1), "Hips"), "Spine1": ((0,0,1.22), "Spine"), "Spine2": ((0,0,1.35), "Spine1"),
 "Neck": ((0,0,1.5), "Spine2"), "Head": ((0,0,1.58), "Neck"), "HeadTop_End": ((0,0,1.78), "Head"),
}
for side, sx in (("Left", 1), ("Right", -1)):   # Mixamo: character's left is +X when facing -Y
    J.update({
     f"{side}Shoulder": ((0.05*sx,0,1.45), "Spine2"), f"{side}Arm": ((0.17*sx,0,1.45), f"{side}Shoulder"),
     f"{side}ForeArm": ((0.44*sx,0,1.45), f"{side}Arm"), f"{side}Hand": ((0.70*sx,0,1.45), f"{side}ForeArm"),
     f"{side}HandMiddle1": ((0.79*sx,0,1.45), f"{side}Hand"), f"{side}HandMiddle2": ((0.83*sx,0,1.45), f"{side}HandMiddle1"),
     f"{side}HandMiddle3": ((0.86*sx,0,1.45), f"{side}HandMiddle2"), f"{side}HandMiddle4": ((0.88*sx,0,1.45), f"{side}HandMiddle3"),
     f"{side}HandIndex1": ((0.79*sx,-0.03,1.45), f"{side}Hand"), f"{side}HandIndex2": ((0.82*sx,-0.03,1.45), f"{side}HandIndex1"),
     f"{side}HandIndex3": ((0.85*sx,-0.03,1.45), f"{side}HandIndex2"), f"{side}HandIndex4": ((0.87*sx,-0.03,1.45), f"{side}HandIndex3"),
     f"{side}HandThumb1": ((0.73*sx,-0.03,1.43), f"{side}Hand"), f"{side}HandThumb2": ((0.76*sx,-0.06,1.43), f"{side}HandThumb1"),
     f"{side}HandThumb3": ((0.78*sx,-0.08,1.43), f"{side}HandThumb2"), f"{side}HandThumb4": ((0.8*sx,-0.09,1.43), f"{side}HandThumb3"),
     f"{side}UpLeg": ((0.1*sx,0,0.95), "Hips"), f"{side}Leg": ((0.1*sx,0,0.52), f"{side}UpLeg"),
     f"{side}Foot": ((0.1*sx,0,0.09), f"{side}Leg"), f"{side}ToeBase": ((0.1*sx,-0.12,0.02), f"{side}Foot"),
     f"{side}Toe_End": ((0.1*sx,-0.2,0.02), f"{side}ToeBase"),
    })
children = {}
for n,(h,p) in J.items(): children.setdefault(p, []).append(n)

# The jump's timeline, in frames at 30 fps (the tests read the phases back
# from the imported clip and expect them near these).
JUMP_FRAMES = {
    "crouch": 8,       # starts to crouch
    "bottom": 18,      # deepest point of the crouch
    "toes_off": 27,    # the toes leave the ground
    "peak": 35,        # highest, legs tucked furthest
    "touchdown": 43,   # the toes are back down
    "landed": 51,      # deepest point of the landing crouch
    "stood": 63,       # upright again
    "end": 72,
}
THIGH = 0.43  # UpLeg -> Leg, and Leg -> Foot


def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def jump_pose(f, clip="jump"):
    """Hips height (m), the legs' hip flexion and knee bend, and the hips' lean
    for a frame of the jump (or, for "land", of a plain crouch)."""
    j = JUMP_FRAMES
    air = 0.0
    if clip == "land":
        h = 1.0 - 0.5 * math.sin(math.pi * (f - 1) / 23.0)
    elif f < j["crouch"]:
        h = 1.0
    elif f < j["bottom"]:
        h = 1.0 - 0.40 * smooth((f - j["crouch"]) / (j["bottom"] - j["crouch"]))
    elif f < j["toes_off"]:
        # Accelerating up out of the crouch, legs planted.
        h = 0.60 + 0.40 * ((f - j["bottom"]) / (j["toes_off"] - j["bottom"])) ** 2
    elif f < j["touchdown"]:
        # A parabola; the tuck follows it.
        x = (f - j["peak"]) / (j["peak"] - j["toes_off"])
        air = max(0.0, 1.0 - x * x)
        h = 1.0 + 0.40 * air
    elif f < j["landed"]:
        x = (f - j["touchdown"]) / (j["landed"] - j["touchdown"])
        h = 1.0 - 0.60 * (1.0 - (1.0 - x) ** 2)
    elif f < j["stood"]:
        h = 0.40 + 0.60 * smooth((f - j["landed"]) / (j["stood"] - j["landed"]))
    else:
        h = 1.0
    if air > 0.0:
        hip, knee = 1.2 * air, 2.0 * air
    else:
        # Feet planted: the hip joint is 0.05 below the hips' origin, the ankle 0.09 up.
        d = min((h - 0.14) / (2 * THIGH), 1.0)
        hip = math.acos(d)
        knee = 2 * hip
    lean = 0.5 * max(0.0, 1.0 - h)
    return h, hip, knee, lean, air


def pose_leap(obj, f, clip):
    """Poses the rig for a frame of the jump by world angles about X (right
    hand rule, so a positive angle tips a bone pointing up toward the front
    and one pointing down toward the back)."""
    h, hip, knee, lean, air = jump_pose(f, clip)
    world = {"Hips": lean}
    for side in ("Left", "Right"):
        world[f"{side}UpLeg"] = -hip
        world[f"{side}Leg"] = -hip + knee
        world[f"{side}Foot"] = 0.5 * air
        world[f"{side}ToeBase"] = 0.5 * air
    pb = obj.pose.bones
    for bone in pb:
        # B = R^-1 (Wp^-1 Wb) R, with R the bone's rest orientation and W the
        # world rotation each bone is given about X.
        wb = pb_world(world, bone)
        wp = pb_world(world, bone.parent) if bone.parent else 0.0
        r = bone.bone.matrix_local.to_3x3()
        rel = Matrix.Rotation(wb - wp, 3, "X")
        bone.rotation_euler = (r.inverted() @ rel @ r).to_euler("XYZ")
    hips = pb["mixamorig:Hips"]
    hips.location = hips.bone.matrix_local.to_3x3().inverted() @ Vector((0, 0, h - 1.0))
    # Arms swing out in the air.
    for side, sx in (("Left", 1), ("Right", -1)):
        pb[f"mixamorig:{side}Arm"].rotation_euler = (0, 0, -sx * (1.2 - 0.8 * air))


def pb_world(world, bone):
    """A bone's world angle: its own if listed, else its parent's (it rides along)."""
    while bone is not None:
        short = bone.name.split(":")[1]
        if short in world:
            return world[short]
        bone = bone.parent
    return 0.0


def build(clip, directory=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = bpy.context.scene; scn.render.fps = 30
    arm = bpy.data.armatures.new("Armature"); obj = bpy.data.objects.new("Armature", arm)
    scn.collection.objects.link(obj); bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    eb = {}
    for n,(h,p) in J.items():
        b = arm.edit_bones.new("mixamorig:" + n); b.head = h
        kids = children.get(n)
        if kids: b.tail = Vector(J[kids[0]][0]) if (Vector(J[kids[0]][0]) - Vector(h)).length > 0.01 else Vector(h) + Vector((0,0,0.05))
        else:
            par = Vector(J[p][0]) if p else Vector(h) - Vector((0,0,0.1))
            d = (Vector(h) - par).normalized(); b.tail = Vector(h) + d * 0.05
        eb[n] = b
    for n,(h,p) in J.items():
        if p: eb[n].parent = eb[p]
    bpy.ops.object.mode_set(mode='POSE')
    frames = {"jump": JUMP_FRAMES["end"], "land": 24}.get(clip, 24)
    scn.frame_start, scn.frame_end = 1, frames
    for f in range(1, frames + 1):
        t = (f - 1) / frames * math.tau
        pb = obj.pose.bones
        for b in pb: b.rotation_mode = 'XYZ'
        if clip in ("jump", "land"):
            pose_leap(obj, f, clip)
        elif clip == "run":
            pb["mixamorig:LeftUpLeg"].rotation_euler = (0.6*math.sin(t),0,0)
            pb["mixamorig:RightUpLeg"].rotation_euler = (-0.6*math.sin(t),0,0)
            pb["mixamorig:LeftLeg"].rotation_euler = (-0.5*max(0,math.cos(t)),0,0)
            pb["mixamorig:RightLeg"].rotation_euler = (-0.5*max(0,-math.cos(t)),0,0)
        if clip not in ("jump", "land"):
            pb["mixamorig:LeftArm"].rotation_euler = (0,0,-1.2 + (0.3*math.sin(t) if clip=="run" else 0.03*math.sin(t)))
            pb["mixamorig:RightArm"].rotation_euler = (0,0,1.2 + (0.3*math.sin(t) if clip=="run" else 0.03*math.sin(t)))
            pb["mixamorig:Hips"].location = (0, 0, 0.02*math.sin(2*t))
        for b in pb:
            b.keyframe_insert("rotation_euler", frame=f)
        pb["mixamorig:Hips"].keyframe_insert("location", frame=f)
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.animation_data.action.name = "mixamo.com"
    bpy.ops.export_scene.fbx(filepath=f"{directory or out_dir}/{clip}.fbx", use_selection=False, object_types={'ARMATURE'},
        add_leaf_bones=False, bake_anim=True, bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False)

for clip in ["idle", "run", "jump"]:
    build(clip)
land_dir = out_dir.rstrip("/") + "_land"
Path(land_dir).mkdir(parents=True, exist_ok=True)
build("jump", land_dir)
build("land", land_dir)
print(f"wrote idle.fbx, run.fbx, jump.fbx to {out_dir}, and jump.fbx, land.fbx to {land_dir}")
