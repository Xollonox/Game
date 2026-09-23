"""Quick Cycles turntable-style preview render of a GLB/glTF for visual review.

    blender -b --python tools/blender/preview.py -- in.glb out.png [--action NAME --frame N] [--front]
"""
import bpy, sys, math
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]
src, out = a[0], a[1]
action = a[a.index("--action") + 1] if "--action" in a else None
frame = int(a[a.index("--frame") + 1]) if "--frame" in a else 1
bpy.ops.wm.read_factory_settings(use_empty=True)
if src.endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=src)
else:
    bpy.ops.import_scene.gltf(filepath=src)
for o in list(bpy.data.objects):
    if o.name.startswith("Icosphere"):
        bpy.data.objects.remove(o, do_unlink=True)
hide = a[a.index("--hide") + 1].split(",") if "--hide" in a else []
show = a[a.index("--show") + 1].split(",") if "--show" in a else None
for o in bpy.data.objects:
    if o.type == "MESH":
        if any(o.name.startswith(h) for h in hide) or (show is not None and not any(o.name.startswith(s) for s in show) and o.name not in ("Body",)):
            o.hide_render = True
arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
if arm and action:
    arm.animation_data_create()
    arm.animation_data.action = bpy.data.actions[action]
    if hasattr(arm.animation_data, "action_slot") and bpy.data.actions[action].slots:
        arm.animation_data.action_slot = bpy.data.actions[action].slots[0]
bpy.context.scene.frame_set(frame)
if arm and "--weapon" in a:
    from mathutils import Matrix
    sys.path.insert(0, __import__("os").path.dirname(__file__))
    wpath = a[a.index("--weapon") + 1]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=wpath)
    wobs = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    mw = arm.matrix_world
    P = lambda n: mw @ arm.pose.bones[n].head
    hand = P("hand_r")
    f = (P("middle_01_r") - hand).normalized()
    t0 = P("index_01_r") - P("pinky_01_r")
    t = (t0 - f * t0.dot(f)).normalized()
    palm = t.cross(f).normalized()
    blade = (t + f * 0.18).normalized()
    z = -blade
    y = (f - blade * f.dot(blade)).normalized()
    F = Matrix((y.cross(z), y, z)).transposed().to_4x4()
    F.translation = hand + f * 0.068 + palm * 0.028
    K = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0))).to_4x4()
    for o in wobs:
        o.matrix_world = F @ K
pts = []
for o in bpy.data.objects:
    if o.type == "MESH" and not o.hide_render:
        dg = bpy.context.evaluated_depsgraph_get()
        e = o.evaluated_get(dg)
        pts += [e.matrix_world @ Vector(c) for c in e.bound_box]
mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
c = (mn + mx) / 2
size = max((mx - mn).length, 0.2)
scn = bpy.context.scene
scn.render.engine = "CYCLES"
scn.cycles.samples = 24
scn.cycles.use_denoising = True
scn.render.resolution_x = int(a[a.index("--w") + 1]) if "--w" in a else 900
scn.render.resolution_y = int(a[a.index("--h") + 1]) if "--h" in a else 900
yaw = math.radians(float(a[a.index("--yaw") + 1])) if "--yaw" in a else math.radians(25)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scn.collection.objects.link(cam)
cam.data.lens = 50
d = size * 1.55
cam.location = c + Vector((math.sin(yaw) * d, -math.cos(yaw) * d, size * 0.12))
cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
scn.camera = cam
for loc, e in (((3, -4, 5), 800), ((-4, -2, 3), 300), ((0, 5, 4), 400)):
    l = bpy.data.objects.new("l", bpy.data.lights.new("l", "AREA"))
    l.data.energy = e
    l.data.size = 3
    l.location = c + Vector(loc)
    l.rotation_euler = (c - l.location).to_track_quat("-Z", "Y").to_euler()
    scn.collection.objects.link(l)
w = bpy.data.worlds.new("w"); scn.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.18, 0.17, 0.16, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
print("PREVIEW", out)
