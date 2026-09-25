"""Builds test fixtures that follow Mixamo's conventions (mixamorig: bone
names, T-pose, armature-only "Without Skin" FBX, 30 fps) so the Mixamo
retargeting pipeline can be tested without redistributing Mixamo files.

    python art/blender/make_mixamo_fixtures.py [OUT_DIR]

Default OUT_DIR: game/tests/fixtures/mixamo. Afterwards run
`godot --headless --path game --import`, then
`godot --headless --path game --script res://tools/setup_mixamo.gd -- --dir=res://tests/fixtures/mixamo`,
then import again.
"""
import math
import sys
from pathlib import Path

import bpy  # noqa: F401  (must precede mathutils when running as a module)
from mathutils import Vector

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

def build(clip):
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
    frames = 24
    scn.frame_start, scn.frame_end = 1, frames
    for f in range(1, frames + 1):
        t = (f - 1) / frames * math.tau
        pb = obj.pose.bones
        for b in pb: b.rotation_mode = 'XYZ'
        if clip == "run":
            pb["mixamorig:LeftUpLeg"].rotation_euler = (0.6*math.sin(t),0,0)
            pb["mixamorig:RightUpLeg"].rotation_euler = (-0.6*math.sin(t),0,0)
            pb["mixamorig:LeftLeg"].rotation_euler = (-0.5*max(0,math.cos(t)),0,0)
            pb["mixamorig:RightLeg"].rotation_euler = (-0.5*max(0,-math.cos(t)),0,0)
        pb["mixamorig:LeftArm"].rotation_euler = (0,0,-1.2 + (0.3*math.sin(t) if clip=="run" else 0.03*math.sin(t)))
        pb["mixamorig:RightArm"].rotation_euler = (0,0,1.2 + (0.3*math.sin(t) if clip=="run" else 0.03*math.sin(t)))
        pb["mixamorig:Hips"].location = (0, 0, 0.02*math.sin(2*t))
        for b in pb:
            b.keyframe_insert("rotation_euler", frame=f)
        pb["mixamorig:Hips"].keyframe_insert("location", frame=f)
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.animation_data.action.name = "mixamo.com"
    bpy.ops.export_scene.fbx(filepath=f"{out_dir}/{clip}.fbx", use_selection=False, object_types={'ARMATURE'},
        add_leaf_bones=False, bake_anim=True, bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False)

for clip in ["idle", "run"]:
    build(clip)
print(f"wrote idle.fbx, run.fbx to {out_dir}")
