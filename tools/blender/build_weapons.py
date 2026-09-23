"""Headless Blender generator for the physical weapon arsenal.

    blender -b --python tools/blender/build_weapons.py -- --out assets/models/weapons/arsenal

Every weapon is lofted from real cross-sections (lenticular/hexagonal blades,
single-edged falchion backs, round hafts, flanged mace heads) rather than
assembled from primitives, so silhouettes, bevels and tapering read correctly at
gameplay distance.

Axis contract with the Godot side (scripts/weapon_catalog.gd, physics_weapon.gd):

* Blender +Y runs from pommel to tip (glTF/Godot -Z). The origin is the centre of
  the MAIN hand's grip, so the grip spring pulls the weapon exactly where the
  fist is.
* Blender +Z is the edge direction (Godot +Y) — the direction a cut travels.
* Blender X is the blade's flat normal.

Alongside each GLB a `<id>.json` is written with the measured physical data in
Godot coordinates: length, tip, centre of mass, second-hand grip (for two-handed
weapons) and a set of collision boxes that follow the striking geometry.
"""

import bpy
import bmesh
import json
import math
import os
import sys
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = "assets/models/weapons/arsenal"
ONLY = None
for i, a in enumerate(ARGS):
    if a == "--out":
        OUT = ARGS[i + 1]
    if a == "--only":
        ONLY = ARGS[i + 1].split(",")
os.makedirs(OUT, exist_ok=True)

MATS = {}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()


def mat(name, color, rough, metal=0.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    MATS[name] = m
    return m


def steel():
    return mat("W_Steel", (0.62, 0.63, 0.65), 0.32, 1.0)


def steel_dark():
    return mat("W_Iron", (0.30, 0.30, 0.31), 0.55, 1.0)


def brass():
    return mat("W_Brass", (0.60, 0.45, 0.22), 0.4, 1.0)


def leather():
    return mat("W_Leather", (0.16, 0.09, 0.05), 0.75)


def wood():
    return mat("W_Wood", (0.36, 0.24, 0.14), 0.7)


def wood_pale():
    return mat("W_WoodPale", (0.52, 0.40, 0.27), 0.8)


def paint_a():
    return mat("W_Paint", (0.46, 0.12, 0.09), 0.8)


# ------------------------------------------------------------ geometry -----
def profile_hex(w, t, flat=0.28):
    """Flattened hexagonal blade section (x = thickness, z = width)."""
    return [(0.0, w / 2), (t / 2, w * flat), (t / 2, -w * flat), (0.0, -w / 2),
            (-t / 2, -w * flat), (-t / 2, w * flat)]


def profile_diamond(w, t):
    return [(0.0, w / 2), (t / 2, 0.0), (0.0, -w / 2), (-t / 2, 0.0)]


def profile_single(w, t):
    """Single-edged section: sharp edge at +z, thick flat back at -z."""
    return [(0.0, w / 2), (t * 0.35, w * 0.2), (t / 2, -w * 0.35), (t / 2, -w / 2),
            (-t / 2, -w / 2), (-t / 2, -w * 0.35), (-t * 0.35, w * 0.2)]


def profile_circle(r, n=12, rz=None):
    rz = r if rz is None else rz
    return [(math.cos(2 * math.pi * i / n) * r, math.sin(2 * math.pi * i / n) * rz) for i in range(n)]


def loft(name, stations, material, cap_start=True, cap_end=True):
    """stations: list of (y, [(x, z), ...]) with equal point counts. Builds a
    closed tube along +Y; a station whose points all coincide becomes a tip."""
    bm = bmesh.new()
    rings = []
    for y, pts in stations:
        rings.append([bm.verts.new((x, y, z)) for x, z in pts])
    n = len(stations[0][1])
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            quad = [a[i], a[j], b[j], b[i]]
            if len({v.co.to_tuple(6) for v in quad}) >= 3:
                try:
                    bm.faces.new(quad)
                except ValueError:
                    pass
    if cap_start:
        try:
            bm.faces.new(list(reversed(rings[0])))
        except ValueError:
            pass
    if cap_end:
        try:
            bm.faces.new(rings[-1])
        except ValueError:
            pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(material)
    return ob


def blade(name, y0, length, w_base, w_tip_frac, t_base, prof=profile_hex, stations=14,
          tip_len=0.12, belly=0.0, material=None):
    """A tapering blade from y0 to y0+length. `belly` widens it toward the
    tip (falchion); the last `tip_len` metres converge to a point."""
    st = []
    body = length - tip_len
    for i in range(stations + 1):
        f = i / stations
        y = y0 + body * f
        w = w_base * (1.0 - (1.0 - w_tip_frac) * f) * (1.0 + belly * math.sin(f * math.pi * 0.85))
        t = t_base * (1.0 - 0.45 * f)
        st.append((y, prof(w, t)))
    y_last, pts_last = st[-1]
    w_last = max(abs(p[1]) for p in pts_last) * 2
    t_last = max(abs(p[0]) for p in pts_last) * 2
    for k in range(1, 5):
        f = k / 4.0
        s = (1.0 - f) ** 1.3
        st.append((y_last + tip_len * f, prof(max(w_last * s, 1e-4), max(t_last * s, 1e-4))))
    return loft(name, st, material or steel(), cap_end=False)


def lathe(name, profile, material, n=14, y_offset=0.0, ellipse=1.0):
    """Revolve [(y, r)] around the Y axis."""
    st = [(y + y_offset, profile_circle(max(r, 1e-4), n, max(r, 1e-4) * ellipse)) for y, r in profile]
    return loft(name, st, material)


def box(name, size, loc, material):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.scale = size
    bpy.ops.object.transform_apply(scale=True)
    ob.data.materials.append(material)
    return ob


def bevel(ob, width=0.002, segments=1):
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    return ob


def crossguard(name, span, y, thick=0.014, depth=0.02, curl=0.0, material=None):
    """A crossguard bar along Z, tapered and slightly flared at the tips."""
    st = []
    n = 10
    for i in range(n + 1):
        f = i / n
        z = -span / 2 + span * f
        edge = abs(f - 0.5) * 2
        s = 1.0 - 0.35 * edge + (0.25 if edge > 0.92 else 0.0)
        dy = curl * edge * edge
        st.append((z, [(-thick / 2 * s, y + dy - depth / 2 * s), (thick / 2 * s, y + dy - depth / 2 * s),
                       (thick / 2 * s, y + dy + depth / 2 * s), (-thick / 2 * s, y + dy + depth / 2 * s)]))
    bm = bmesh.new()
    rings = [[bm.verts.new((x, yy, z)) for x, yy in pts] for z, pts in st]
    for a, b in zip(rings, rings[1:]):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new([a[i], a[j], b[j], b[i]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(material or steel_dark())
    return bevel(ob, 0.002)


def grip_wrap(name, y0, y1, r0, r1, material=None, ridges=6):
    """A leather/cord-wrapped grip with subtle ridges."""
    prof = []
    steps = ridges * 4
    for i in range(steps + 1):
        f = i / steps
        r = r0 + (r1 - r0) * f
        r *= 1.0 + 0.06 * math.sin(f * ridges * 2 * math.pi) ** 2 + 0.08 * math.sin(f * math.pi)
        prof.append((y0 + (y1 - y0) * f, r))
    return lathe(name, prof, material or leather(), n=10, ellipse=1.18)


def join(objs, name):
    for o in objs:
        for m in list(o.modifiers):
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.object
    ob.name = name
    return ob


SHIELD_UV = [None]


def uv_project(ob, texel=4.0):
    """Cylindrical-ish projection: U around the long axis, V along it.
    Blades get a flat planar map (both sides mirror), which is what steel
    polish streaks want anyway."""
    me = ob.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uvl = me.uv_layers.new(name="UVMap").data
    for poly in me.polygons:
        n = poly.normal
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if SHIELD_UV[0] is not None and me.materials[poly.material_index].name == "W_Paint":
                w, top, h = SHIELD_UV[0]
                uvl[li].uv = ((co.z + w / 2) / w, (top - co.y) / h)
                continue
            if abs(n.y) > 0.8:
                u, v = co.x, co.z
            elif abs(n.x) > abs(n.z):
                u, v = co.z, co.y
            else:
                u, v = co.x, co.y
            uvl[li].uv = (u * texel, v * texel)
    me.update()


# ----------------------------------------------------------- metadata ------
def g(v):
    """Blender -> Godot coordinates."""
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def mass_properties(ob, parts):
    """Centre of mass from per-part (object, density) volume estimate."""
    total = 0.0
    acc = Vector()
    for o, density in parts:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        vol = abs(bm.calc_volume(signed=False))
        c = Vector()
        for v in bm.verts:
            c += v.co
        c /= max(len(bm.verts), 1)
        bm.free()
        m = vol * density
        total += m
        acc += c * m
    return total, acc / max(total, 1e-6)


def write_meta(wid, data):
    with open(os.path.join(OUT, wid + ".json"), "w") as f:
        json.dump(data, f, indent=1)


def export(ob, wid):
    uv_project(ob)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    path = os.path.join(OUT, wid + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_animations=False)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print("WEAPON", wid, path, "tris", tris)


STEEL_DENSITY = 7850.0
WOOD_DENSITY = 700.0
LEATHER_DENSITY = 900.0


def finish(wid, parts, meta, boxes, target_mass):
    """Join, compute COM, rescale density so the total matches the historical
    target mass (volume from a low-poly loft is only approximate)."""
    _, com = mass_properties(None, parts)
    ob = join([p for p, _ in parts], wid)
    export(ob, wid)
    meta.update({
        "id": wid,
        "mass": target_mass,
        "com": g(com),
        "boxes": [{"center": g(c), "size": [round(s[0], 4), round(s[2], 4), round(s[1], 4)],
                   "part": part} for c, s, part in boxes],
    })
    meta["markers"] = markers(meta, boxes)
    meta["tip"] = g(meta["tip"])
    if "grip2" in meta:
        meta["grip2"] = g(meta["grip2"])
    if "pommel" in meta:
        meta["pommel"] = g(meta["pommel"])
    write_meta(wid, meta)


def markers(meta, boxes):
    """Named points (Godot coordinates) every system reads instead of
    guessing: GripPrimary (the main hand, the weapon origin), GripSecondary,
    Pommel, Guard, EdgeStart/EdgeEnd (the cutting run of the blade), Tip,
    Head (a mace or club head, an axe bit) and Shaft (a haft's middle)."""
    m = {"GripPrimary": [0.0, 0.0, 0.0], "Tip": g(meta["tip"])}
    if "grip2" in meta:
        m["GripSecondary"] = g(meta["grip2"])
    if "pommel" in meta:
        m["Pommel"] = g(meta["pommel"])
    edge = [(c, s) for c, s, part in boxes if part in ("edge", "point")]
    if edge:
        lo = min(c.y - s.y * 0.5 for c, s in edge)
        hi = max(c.y + s.y * 0.5 for c, s in edge)
        m["EdgeStart"] = g(Vector((0, lo, 0)))
        m["EdgeEnd"] = g(Vector((0, hi, 0)))
    for c, s, part in boxes:
        if part == "guard":
            m["Guard"] = g(c)
        elif part == "head" or (part == "edge" and meta.get("class") == "axe"):
            m["Head"] = g(c)
        elif part == "haft":
            m["Shaft"] = g(c)
    return m


def blade_boxes(y0, y1, w, t, n=3, part="edge"):
    out = []
    seg = (y1 - y0) / n
    for i in range(n):
        yc = y0 + seg * (i + 0.5)
        ww = w * (1.0 - 0.35 * (i / max(n - 1, 1)))
        out.append((Vector((0, yc, 0)), Vector((max(t, 0.02), seg, ww)), part if i < n - 1 else "point"))
    return out


# ------------------------------------------------------------- weapons -----
def arming_sword():
    reset()
    grip_half = 0.05
    parts = [
        (blade("blade", grip_half + 0.012, 0.80, 0.052, 0.42, 0.0075, tip_len=0.14), STEEL_DENSITY),
        (crossguard("guard", 0.21, grip_half + 0.006, curl=0.012), STEEL_DENSITY),
        (grip_wrap("grip", -grip_half, grip_half, 0.0145, 0.0125), LEATHER_DENSITY),
        (lathe("pommel", [(-grip_half - 0.042, 0.004), (-grip_half - 0.038, 0.021), (-grip_half - 0.02, 0.026),
                          (-grip_half - 0.004, 0.021), (-grip_half, 0.01)], steel_dark(), n=16, ellipse=0.55), STEEL_DENSITY),
    ]
    boxes = blade_boxes(grip_half + 0.02, grip_half + 0.81, 0.05, 0.02)
    boxes.append((Vector((0, grip_half + 0.006, 0)), Vector((0.02, 0.02, 0.21)), "guard"))
    finish("arming_sword", parts, {
        "name": "Arming Sword", "class": "sword", "hands": 1, "damage": "cut",
        "tip": Vector((0, grip_half + 0.81, 0)), "length": 0.95, "pommel": Vector((0, -grip_half - 0.04, 0)),
    }, boxes, 1.15)


def longsword():
    reset()
    grip_half = 0.12
    y0 = grip_half * 0.2
    parts = [
        (blade("blade", y0 + 0.012, 0.93, 0.05, 0.36, 0.008, tip_len=0.18), STEEL_DENSITY),
        (crossguard("guard", 0.27, y0 + 0.006, depth=0.022), STEEL_DENSITY),
        (grip_wrap("grip", y0 - 0.25, y0, 0.0155, 0.0135, ridges=10), LEATHER_DENSITY),
        (lathe("pommel", [(y0 - 0.33, 0.004), (y0 - 0.32, 0.017), (y0 - 0.29, 0.024), (y0 - 0.265, 0.014),
                          (y0 - 0.25, 0.012)], steel_dark(), n=16), STEEL_DENSITY),
    ]
    boxes = blade_boxes(y0 + 0.02, y0 + 0.95, 0.048, 0.02, n=3)
    boxes.append((Vector((0, y0 + 0.006, 0)), Vector((0.02, 0.022, 0.27)), "guard"))
    finish("longsword", parts, {
        "name": "Longsword", "class": "sword", "hands": 2, "damage": "cut",
        "tip": Vector((0, y0 + 0.95, 0)), "grip2": Vector((0, y0 - 0.19, 0)), "length": 1.28,
        "pommel": Vector((0, y0 - 0.32, 0)),
    }, boxes, 1.45)


def falchion():
    reset()
    grip_half = 0.05
    parts = [
        (blade("blade", grip_half + 0.012, 0.70, 0.045, 1.05, 0.009, prof=profile_single, tip_len=0.13,
               belly=0.55), STEEL_DENSITY),
        (crossguard("guard", 0.16, grip_half + 0.006, curl=-0.01), STEEL_DENSITY),
        (grip_wrap("grip", -grip_half, grip_half, 0.015, 0.013), LEATHER_DENSITY),
        (lathe("pommel", [(-grip_half - 0.035, 0.003), (-grip_half - 0.03, 0.017), (-grip_half - 0.012, 0.02),
                          (-grip_half, 0.01)], brass(), n=12), STEEL_DENSITY),
    ]
    boxes = blade_boxes(grip_half + 0.02, grip_half + 0.71, 0.07, 0.022)
    finish("falchion", parts, {
        "name": "Falchion", "class": "sword", "hands": 1, "damage": "cut",
        "tip": Vector((0, grip_half + 0.71, 0)), "length": 0.86, "pommel": Vector((0, -grip_half - 0.03, 0)),
    }, boxes, 1.3)


def rondel_dagger():
    reset()
    gh = 0.045
    parts = [
        (blade("blade", gh + 0.012, 0.29, 0.02, 0.45, 0.012, prof=profile_diamond, tip_len=0.07, stations=6), STEEL_DENSITY),
        (lathe("rondel_a", [(gh, 0.001), (gh + 0.001, 0.028), (gh + 0.009, 0.028), (gh + 0.01, 0.001)],
               steel_dark(), n=16), STEEL_DENSITY),
        (grip_wrap("grip", -gh, gh, 0.013, 0.012, material=wood()), WOOD_DENSITY),
        (lathe("rondel_b", [(-gh - 0.01, 0.001), (-gh - 0.009, 0.024), (-gh, 0.024), (-gh + 0.001, 0.001)],
               steel_dark(), n=16), STEEL_DENSITY),
    ]
    boxes = [(Vector((0, gh + 0.16, 0)), Vector((0.02, 0.29, 0.022)), "point")]
    finish("rondel_dagger", parts, {
        "name": "Rondel Dagger", "class": "dagger", "hands": 1, "damage": "pierce",
        "tip": Vector((0, gh + 0.30, 0)), "length": 0.41, "pommel": Vector((0, -gh - 0.01, 0)),
    }, boxes, 0.38)


def axe():
    reset()
    haft_top = 0.52
    prof = [(-0.2, 0.017), (-0.18, 0.02), (-0.1, 0.016), (0.1, 0.0155), (0.35, 0.0165), (haft_top, 0.018),
            (haft_top + 0.02, 0.012)]
    parts = [(lathe("haft", prof, wood(), n=10, ellipse=1.3), WOOD_DENSITY)]
    # Bearded axe head: a lofted wedge along +Z (the cutting direction).
    hy = haft_top - 0.05
    st = []
    for i in range(9):
        f = i / 8.0
        z = 0.02 + 0.15 * f
        top = hy + 0.035 + 0.02 * f
        bot = hy - 0.03 - 0.1 * f ** 1.6
        t = 0.024 * (1 - f) + 0.0015
        st.append((z, [(-t / 2, bot), (t / 2, bot), (t / 2, top), (-t / 2, top)]))
    bm = bmesh.new()
    rings = [[bm.verts.new((x, y, z)) for x, y in pts] for z, pts in st]
    for a, b in zip(rings, rings[1:]):
        for i in range(4):
            bm.faces.new([a[i], a[(i + 1) % 4], b[(i + 1) % 4], b[i]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("head")
    bm.to_mesh(me)
    bm.free()
    head = bpy.data.objects.new("head", me)
    bpy.context.collection.objects.link(head)
    me.materials.append(steel())
    socket = lathe("socket", [(hy - 0.035, 0.024), (hy + 0.04, 0.024)], steel_dark(), n=10, ellipse=1.2)
    poll = box("poll", (0.03, 0.05, 0.035), (0, hy + 0.005, -0.03), steel_dark())
    parts += [(head, STEEL_DENSITY), (socket, STEEL_DENSITY), (poll, STEEL_DENSITY)]
    boxes = [
        (Vector((0, hy - 0.02, 0.1)), Vector((0.03, 0.14, 0.17)), "edge"),
        (Vector((0, 0.18, 0)), Vector((0.035, 0.6, 0.04)), "haft"),
    ]
    finish("bearded_axe", parts, {
        "name": "Bearded Axe", "class": "axe", "hands": 1, "damage": "cut",
        "tip": Vector((0, hy, 0.17)), "length": 0.76, "pommel": Vector((0, -0.2, 0)),
    }, boxes, 1.35)


def mace():
    reset()
    parts = [(lathe("haft", [(-0.14, 0.012), (-0.13, 0.019), (-0.11, 0.016), (0.25, 0.015), (0.36, 0.017)],
                    steel_dark(), n=10), STEEL_DENSITY)]
    grip = grip_wrap("grip", -0.11, 0.07, 0.0165, 0.0155)
    parts.append((grip, LEATHER_DENSITY))
    core = lathe("core", [(0.34, 0.018), (0.36, 0.024), (0.46, 0.022), (0.48, 0.012), (0.49, 0.004)],
                 steel_dark(), n=12)
    parts.append((core, STEEL_DENSITY))
    for k in range(7):
        a = 2 * math.pi * k / 7
        bm = bmesh.new()
        pts2d = [(0.35, 0.02), (0.37, 0.058), (0.43, 0.064), (0.475, 0.035), (0.48, 0.02)]
        vs_a = []
        vs_b = []
        for y, r in pts2d:
            for off, lst in ((-0.0035, vs_a), (0.0035, vs_b)):
                x = math.cos(a) * r - math.sin(a) * off
                z = math.sin(a) * r + math.cos(a) * off
                lst.append(bm.verts.new((x, y, z)))
        inner_a = bm.verts.new((math.cos(a) * 0.015, 0.35, math.sin(a) * 0.015))
        bm.faces.new(vs_a + [inner_a][:0])
        bm.faces.new(list(reversed(vs_b)))
        n = len(vs_a)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new([vs_a[i], vs_b[i], vs_b[j], vs_a[j]])
        bm.verts.remove(inner_a)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        me = bpy.data.meshes.new("flange%d" % k)
        bm.to_mesh(me)
        bm.free()
        fo = bpy.data.objects.new("flange%d" % k, me)
        bpy.context.collection.objects.link(fo)
        me.materials.append(steel())
        parts.append((fo, STEEL_DENSITY))
    boxes = [(Vector((0, 0.415, 0)), Vector((0.13, 0.13, 0.13)), "head"),
             (Vector((0, 0.12, 0)), Vector((0.03, 0.46, 0.03)), "haft")]
    finish("flanged_mace", parts, {
        "name": "Flanged Mace", "class": "mace", "hands": 1, "damage": "blunt",
        "tip": Vector((0, 0.44, 0.06)), "length": 0.63, "pommel": Vector((0, -0.14, 0)),
    }, boxes, 1.55)


def club():
    reset()
    prof = []
    for i in range(17):
        f = i / 16
        y = -0.12 + 0.78 * f
        r = 0.018 + 0.03 * f ** 1.8
        r *= 1.0 + 0.09 * math.sin(f * 31.0) * f
        prof.append((y, r))
    prof.append((0.665, 0.03))
    prof.append((0.675, 0.01))
    parts = [(lathe("club", prof, wood_pale(), n=9, ellipse=1.1), WOOD_DENSITY)]
    # A few iron studs driven into the head.
    for k in range(6):
        a = k * 2.2
        y = 0.45 + 0.035 * k
        r = 0.045
        s = box("stud%d" % k, (0.014, 0.014, 0.014), (math.cos(a) * r, y, math.sin(a) * r), steel_dark())
        parts.append((s, STEEL_DENSITY))
    boxes = [(Vector((0, 0.5, 0)), Vector((0.09, 0.32, 0.09)), "head"),
             (Vector((0, 0.1, 0)), Vector((0.04, 0.44, 0.04)), "haft")]
    finish("cudgel", parts, {
        "name": "Cudgel", "class": "club", "hands": 1, "damage": "blunt",
        "tip": Vector((0, 0.62, 0.04)), "length": 0.8, "pommel": Vector((0, -0.12, 0)),
    }, boxes, 1.0)


def spear():
    reset()
    butt = -0.75
    top = 1.25
    parts = [(lathe("shaft", [(butt, 0.012), (butt + 0.01, 0.0155), (0.0, 0.0165), (top, 0.0145)], wood(), n=10),
              WOOD_DENSITY)]
    parts.append((lathe("ferrule", [(butt - 0.03, 0.004), (butt - 0.02, 0.012), (butt + 0.04, 0.0165)],
                        steel_dark(), n=10), STEEL_DENSITY))
    parts.append((lathe("socket", [(top - 0.06, 0.017), (top + 0.07, 0.013)], steel_dark(), n=10), STEEL_DENSITY))
    parts.append((blade("head", top + 0.07, 0.26, 0.045, 0.5, 0.012, prof=profile_diamond, tip_len=0.1,
                        stations=6, belly=0.3), STEEL_DENSITY))
    boxes = [(Vector((0, top + 0.19, 0)), Vector((0.025, 0.26, 0.05)), "point"),
             (Vector((0, 0.55, 0)), Vector((0.035, 1.1, 0.035)), "haft")]
    finish("war_spear", parts, {
        "name": "War Spear", "class": "spear", "hands": 2, "damage": "pierce",
        "tip": Vector((0, top + 0.33, 0)), "grip2": Vector((0, -0.45, 0)), "length": 2.33,
        "pommel": Vector((0, butt, 0)),
    }, boxes, 2.1)


def heater_shield():
    """A heater shield on the left forearm. Origin is the hand grip; the shield
    face points along Blender -X (away from the body when held in the left hand)."""
    reset()
    w, h, thick = 0.5, 0.64, 0.02
    outline = []
    n = 14
    for i in range(n + 1):
        f = i / n
        z = -w / 2 + w * f
        outline.append(z)
    # Build as a gently curved plate: X offset follows the curvature across Z.
    bm = bmesh.new()
    cols = 12
    rows = 14
    grid_f = []
    grid_b = []
    for r in range(rows + 1):
        v = r / rows
        y = h * 0.62 - h * v
        half = w / 2 if v < 0.45 else w / 2 * math.cos((v - 0.45) / 0.55 * math.pi / 2) ** 0.8
        half = max(half, 0.004)
        rowf = []
        rowb = []
        for c in range(cols + 1):
            u = c / cols
            z = -half + 2 * half * u
            x = -0.05 * (1 - (z / (w / 2)) ** 2) - 0.03
            rowf.append(bm.verts.new((x - thick / 2, y, z)))
            rowb.append(bm.verts.new((x + thick / 2, y, z)))
        grid_f.append(rowf)
        grid_b.append(rowb)
    for r in range(rows):
        for c in range(cols):
            bm.faces.new([grid_f[r][c], grid_f[r + 1][c], grid_f[r + 1][c + 1], grid_f[r][c + 1]])
            bm.faces.new([grid_b[r][c], grid_b[r][c + 1], grid_b[r + 1][c + 1], grid_b[r + 1][c]])
    # Rim.
    edge_f = [grid_f[0][c] for c in range(cols + 1)] + [grid_f[r][cols] for r in range(1, rows + 1)] + \
             [grid_f[rows][c] for c in range(cols - 1, -1, -1)] + [grid_f[r][0] for r in range(rows - 1, 0, -1)]
    edge_b = [grid_b[0][c] for c in range(cols + 1)] + [grid_b[r][cols] for r in range(1, rows + 1)] + \
             [grid_b[rows][c] for c in range(cols - 1, -1, -1)] + [grid_b[r][0] for r in range(rows - 1, 0, -1)]
    for i in range(len(edge_f)):
        j = (i + 1) % len(edge_f)
        try:
            bm.faces.new([edge_f[i], edge_f[j], edge_b[j], edge_b[i]])
        except ValueError:
            pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("board")
    bm.to_mesh(me)
    bm.free()
    board = bpy.data.objects.new("board", me)
    bpy.context.collection.objects.link(board)
    me.materials.append(paint_a())
    boss = lathe("boss", [(0.0, 0.001), (0.0, 0.05), (0.0, 0.0)], steel_dark(), n=12)
    boss.rotation_euler = (0, 0, math.radians(90))
    bpy.ops.object.select_all(action="DESELECT")
    strap = box("strap", (0.02, 0.2, 0.03), (-0.008, 0.02, 0.0), leather())
    grip = box("grip", (0.02, 0.03, 0.12), (0.0, -0.0, 0.0), leather())
    for o in (boss,):
        bpy.data.objects.remove(o, do_unlink=True)
    parts = [(board, WOOD_DENSITY), (strap, LEATHER_DENSITY), (grip, LEATHER_DENSITY)]
    SHIELD_UV[0] = (w, h * 0.62, h)
    boxes = [(Vector((-0.06, 0.1, 0)), Vector((0.05, h * 0.9, w * 0.95)), "shield")]
    finish("heater_shield", parts, {
        "name": "Heater Shield", "class": "shield", "hands": 1, "damage": "blunt",
        "tip": Vector((-0.06, h * 0.6, 0)), "length": h, "pommel": Vector((0, 0, 0)),
    }, boxes, 3.2)


BUILDERS = {
    "arming_sword": arming_sword,
    "longsword": longsword,
    "falchion": falchion,
    "rondel_dagger": rondel_dagger,
    "bearded_axe": axe,
    "flanged_mace": mace,
    "cudgel": club,
    "war_spear": spear,
    "heater_shield": heater_shield,
}

for wid, fn in BUILDERS.items():
    if ONLY and wid not in ONLY:
        continue
    fn()
print("WEAPONS_DONE")
