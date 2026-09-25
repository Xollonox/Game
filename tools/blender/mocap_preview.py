"""Frames of a mocap clip on the fighter (Cycles CPU, headless).

    blender -b --python tools/blender/mocap_preview.py -- CLIP[,CLIP...] OUTDIR [frames] [--side]
"""
import os
import sys

import bpy
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
clip, out = a[0], a[1]
n = int(a[2]) if len(a) > 2 else 6
root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(root, "assets/models/characters/fighter/fighter.glb"))
arm = bpy.data.objects["Fighter"]
keep = ("Body", "Z_", "G_Shirt", "G_Hose", "Head", "Hair_Buzzed", "Eyes")
for o in bpy.data.objects:
    if o.type == "MESH":
        o.hide_render = not any(o.name.startswith(k) for k in keep)
before = set(bpy.data.actions)
bpy.ops.import_scene.gltf(filepath=os.path.join(root, "assets/models/characters/fighter/mocap_anims.glb"))
new_actions = [x for x in bpy.data.actions if x not in before]
for o in list(bpy.data.objects):
    if o.type == "ARMATURE" and o is not arm:
        bpy.data.objects.remove(o, do_unlink=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 6
sc.cycles.use_denoising = False
sc.render.resolution_x = 240
sc.render.resolution_y = 320
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 4.0
sun.rotation_euler = (0.7, 0.2, 0.5)
sc.collection.objects.link(sun)
sc.world = bpy.data.worlds.new("W")
sc.world.color = (0.35, 0.35, 0.38)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
sc.collection.objects.link(cam)
sc.camera = cam
side = "--side" in a
cam.location = Vector((-3.6, -1.2, 1.2)) if side else Vector((1.6, -3.4, 1.25))
d = Vector((0, 0, 1.0)) - cam.location
cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
import bmesh
floor = bpy.data.objects.new("Floor", bpy.data.meshes.new("Floor"))
bm = bmesh.new()
bmesh.ops.create_grid(bm, x_segments=8, y_segments=8, size=2.0)
bm.to_mesh(floor.data)
sc.collection.objects.link(floor)
os.makedirs(out, exist_ok=True)
for c in clip.split(","):
    act = next(x for x in new_actions if x.name == c or x.name.startswith(c + "|") or x.name.endswith("|" + c))
    arm.animation_data_create()
    arm.animation_data.action = act
    if act.slots:
        arm.animation_data.action_slot = act.slots[0]
    f0, f1 = [int(x) for x in act.frame_range]
    for i in range(n):
        f = int(round(f0 + (f1 - f0) * i / max(1, n - 1)))
        sc.frame_set(f)
        sc.render.filepath = os.path.join(out, "%s_%02d.png" % (c, i))
        bpy.ops.render.render(write_still=True)
    print("CLIP_DONE", c)
