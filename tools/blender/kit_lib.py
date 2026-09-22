"""Shared headless-Blender helpers for the medieval world kit.

Everything here runs under `blender -b --python <script>` with no editor UI.
The design goals, in order:

1. Every piece exports as its own small GLB with the pivot at the base centre,
   real-world metres, +Z up (the glTF exporter converts to Godot's Y-up).
2. Textures are NOT baked into the GLBs. Each face is assigned a named material
   slot (M_Stone, M_Wood, M_Roof...) and real box-projected UVs. The Godot side
   applies one shared PBR material per slot name, which keeps the whole kit on a
   handful of materials (batching-friendly on the web renderer) and lets the
   look be retuned in one place.
3. UVs are written directly with bmesh math rather than bpy.ops.uv.*, because
   the UV operators need a 3D-view context that headless Blender does not have.
"""

import bpy
import bmesh
import math
import random
from mathutils import Vector, Matrix, Euler

MATS = {}


# ---------------------------------------------------------------- scene -----
def reset_scene(seed=7):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    random.seed(seed)


def mat(name, color=(0.5, 0.5, 0.5), rough=0.9, metal=0.0):
    """Named Principled material; name is the contract with the Godot side."""
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    MATS[name] = m
    return m


# ------------------------------------------------------------ primitives ----
def box(name, sx, sy, sz, loc=(0, 0, 0), material=None, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.scale = (sx, sy, sz)
    ob.rotation_euler = Euler(rot)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if material:
        ob.data.materials.append(material)
    return ob


def cyl(name, r, h, loc=(0, 0, 0), material=None, verts=12, r2=None, rot=(0, 0, 0)):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=h, location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.rotation_euler = Euler(rot)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if material:
        ob.data.materials.append(material)
    return ob


def sphere(name, r, loc=(0, 0, 0), material=None, seg=12, rings=8, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=r, location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if material:
        ob.data.materials.append(material)
    return ob


def join(objs, name):
    """Join parts into one object; material slots and UVs survive the join."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.object
    ob.name = name
    return ob


# ------------------------------------------------------------------ UVs -----
def box_uv(ob, texel=0.5):
    """Per-face planar (box) projection in world units.

    texel = texture repeats per metre, so 0.5 means one repeat per 2 m and
    every piece in the kit ends up at the same visual texture density.
    """
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uvl = me.uv_layers.active.data
    mw = ob.matrix_world
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            w = mw @ me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                u, v = w.y, w.z
            elif ax == 1:
                u, v = w.x, w.z
            else:
                u, v = w.x, w.y
            uvl[li].uv = (u * texel, v * texel)
    me.update()


# ----------------------------------------------------------------- LODs -----
def decimate(ob, ratio=0.4):
    """Apply a decimate modifier in place — LOD generation for the pipeline."""
    bpy.context.view_layer.objects.active = ob
    m = ob.modifiers.new("Decimate", "DECIMATE")
    m.ratio = ratio
    bpy.ops.object.modifier_apply(modifier=m.name)
    return ob


# --------------------------------------------------------------- export -----
def export_glb(ob, path, texel=0.5):
    box_uv(ob, texel)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_animations=False,
        export_skins=False,
    )
    print("EXPORT", path, "tris=", len(ob.data.loop_triangles) if ob.data.loop_triangles else "?")
    return path


def drop_to_ground(ob):
    """Shift mesh so its lowest point sits at z=0 and its origin is base-centre."""
    me = ob.data
    zs = [v.co.z for v in me.vertices]
    if not zs:
        return ob
    dz = min(zs)
    for v in me.vertices:
        v.co.z -= dz
    me.update()
    return ob


# ------------------------------------------------------------- shortcuts ----
def stone():
    return mat("M_Stone", (0.42, 0.40, 0.37), 0.95)


def stone_dark():
    return mat("M_StoneDark", (0.28, 0.27, 0.26), 0.95)


def wood():
    return mat("M_Wood", (0.30, 0.20, 0.11), 0.85)


def wood_dark():
    return mat("M_WoodDark", (0.18, 0.12, 0.07), 0.85)


def roof():
    return mat("M_Roof", (0.32, 0.16, 0.12), 0.9)


def plaster():
    return mat("M_Plaster", (0.66, 0.61, 0.52), 0.9)


def metal():
    return mat("M_Metal", (0.22, 0.22, 0.24), 0.45, 1.0)


def cloth_red():
    return mat("M_ClothRed", (0.45, 0.10, 0.10), 0.9)


def cloth_blue():
    return mat("M_ClothBlue", (0.14, 0.18, 0.38), 0.9)


def cloth():
    return mat("M_Cloth", (0.55, 0.50, 0.40), 0.9)


def straw():
    return mat("M_Straw", (0.62, 0.50, 0.24), 0.95)


def mud():
    return mat("M_Mud", (0.20, 0.16, 0.12), 0.95)


def grass():
    return mat("M_Grass", (0.24, 0.32, 0.14), 0.9)


def water():
    return mat("M_Water", (0.10, 0.13, 0.14), 0.08, 0.4)


def thatch():
    return mat("M_Thatch", (0.45, 0.36, 0.20), 0.95)
