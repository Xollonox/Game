"""Procedural XV-century wardrobe fitted to the Quaternius base body.

Called from build_fighter.py. Everything is generated from the body mesh itself
so garments follow its real proportions and inherit its skin weights:

* The body is first split into ZONES by face centroid (head, neck, torso,
  upper/lower arm, hand, thigh, upper/lower shin, foot). Each zone becomes a
  separate `B_<Zone>` mesh, so the game can hide skin that a garment covers —
  no poke-through, and fewer skinned triangles for armoured fighters.
* A garment is a union of zones, smoothed (cloth doesn't show abdominal
  muscles) and pushed out along normals by its layer thickness. Layer offsets
  increase outward: shirt < tunic < gambeson < mail < brigandine < plate, so any
  historically plausible stack nests without z-fighting.
* Skirts (tunic, gambeson, haubergeon) are lofted from the hip cross-section
  and skinned by nearest-vertex transfer from the legs, then weight-smoothed.
* Plate pieces are made rigid (single bone) so they move like steel, not skin.
* Helmets are lathed/lofted around the measured head and bound to `Head`.

Names are the contract with scripts/fighter_look.gd: `B_*` body zones, `G_*`
cloth garments, `A_*` armour, `H_*` headgear, `X_*` accessories.
"""

import bpy
import bmesh
import math
from mathutils import Vector, kdtree

ZONES = ("Head", "Neck", "Torso", "UpperArm", "LowerArm", "Hand", "Thigh", "ShinUp", "ShinLow", "Foot")


def zone_of(c):
    x, y, z = abs(c.x), c.y, c.z
    if x > 0.20 and z > 1.30:
        if x < 0.46:
            return "UpperArm"
        if x < 0.70:
            return "LowerArm"
        return "Hand"
    if z > 1.575:
        return "Head"
    if z > 1.50 and x < 0.09:
        return "Neck"
    if z > 0.90:
        return "Torso"
    if z > 0.52:
        return "Thigh"
    if z > 0.30:
        return "ShinUp"
    if z > 0.10:
        return "ShinLow"
    return "Foot"


# ------------------------------------------------------------------ util ---
def _mat(name, color, rough=0.8, metal=0.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    return m


MAT = {}


def mats():
    MAT.update({
        "linen": _mat("G_Linen", (0.78, 0.74, 0.64), 0.9),
        "wool": _mat("G_Wool", (0.35, 0.22, 0.16), 0.95),
        "wool2": _mat("G_Wool2", (0.22, 0.25, 0.30), 0.95),
        "hose": _mat("G_Hose", (0.28, 0.20, 0.16), 0.95),
        "padded": _mat("G_Padded", (0.72, 0.64, 0.48), 0.95),
        "leather": _mat("G_Leather", (0.22, 0.13, 0.07), 0.7),
        "mail": _mat("A_Mail", (0.45, 0.45, 0.46), 0.45, 1.0),
        "plate": _mat("A_Plate", (0.62, 0.63, 0.65), 0.3, 1.0),
        "iron": _mat("A_Iron", (0.32, 0.31, 0.30), 0.55, 1.0),
        "velvet": _mat("G_Velvet", (0.40, 0.08, 0.07), 0.85),
        "brass": _mat("A_Brass", (0.62, 0.47, 0.22), 0.4, 1.0),
    })


def body_bm(body):
    bm = bmesh.new()
    bm.from_mesh(body.data)
    return bm


def new_object(name, bm, arm, template, material=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    for vg in template.vertex_groups:
        ob.vertex_groups.new(name=vg.name)
    ob.parent = arm
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    if material is not None:
        me.materials.clear()
        me.materials.append(material)
    return ob


def region(body, zones, extra=None, exclude=None):
    """BMesh copy of the body containing only faces in `zones` (or accepted by
    `extra(centroid, zone)`), minus faces for which `exclude` is true."""
    bm = body_bm(body)
    bm.faces.ensure_lookup_table()
    kill = []
    for f in bm.faces:
        c = f.calc_center_median()
        z = zone_of(c)
        keep = z in zones or (extra is not None and extra(c, z))
        if keep and exclude is not None and exclude(c, z):
            keep = False
        if not keep:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    return bm


def smooth(bm, iterations=6, factor=0.5, pin_boundary=True):
    verts = [v for v in bm.verts if not (pin_boundary and v.is_boundary)]
    for _ in range(iterations):
        bmesh.ops.smooth_vert(bm, verts=verts, factor=factor, use_axis_x=True, use_axis_y=True, use_axis_z=True)


def inflate(bm, dist):
    """Push along smoothed vertex normals. `dist` may be a float or f(v)."""
    bm.normal_update()
    moves = []
    for v in bm.verts:
        d = dist(v) if callable(dist) else dist
        moves.append((v, v.normal * d))
    for v, m in moves:
        v.co += m


def subdivide(bm, cuts=1):
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)


def rigid(ob, bone_fn):
    """Rebind every vertex to a single bone chosen by bone_fn(co) -> name."""
    me = ob.data
    for v in me.vertices:
        for g in list(v.groups):
            ob.vertex_groups[g.group].remove([v.index])
        ob.vertex_groups[bone_fn(v.co)].add([v.index], 1.0, "REPLACE")


def side(co):
    return "l" if co.x >= 0 else "r"


def solidify(ob, thickness):
    m = ob.modifiers.new("Solid", "SOLIDIFY")
    m.thickness = thickness
    m.offset = -1.0
    m.use_rim = True
    bpy.context.view_layer.objects.active = ob
    # Keep armature last.
    bpy.ops.object.modifier_move_to_index(modifier="Solid", index=0)
    bpy.ops.object.modifier_apply(modifier="Solid")


def box_uv(ob, texel):
    me = ob.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uvl = me.uv_layers.new(name="UVMap").data
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                u, v = co.y, co.z
            elif ax == 1:
                u, v = co.x, co.z
            else:
                u, v = co.x, co.y
            uvl[li].uv = (u * texel, v * texel)


def cyl_uv(ob, texel, axis="z"):
    """Cylindrical UVs around the vertical (or arm) axis: seamless fabric flow."""
    me = ob.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uvl = me.uv_layers.new(name="UVMap").data
    for poly in me.polygons:
        cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        angs = [math.atan2(c.x, -c.y) for c in cos]
        ref = angs[0]
        for li, c, a in zip(poly.loop_indices, cos, angs):
            if a - ref > math.pi:
                a -= 2 * math.pi
            elif ref - a > math.pi:
                a += 2 * math.pi
            r = max(math.hypot(c.x, c.y), 0.05)
            if abs(c.x) > 0.22 and c.z > 1.3:
                # Sleeves: around the arm's own axis.
                a2 = math.atan2(c.y - 0.07, c.z - 1.456)
                uvl[li].uv = (abs(c.x) * texel, a2 * 0.06 * texel)
            else:
                uvl[li].uv = (a * 0.16 * texel, c.z * texel)


def finish(ob, texel=3.0, uv="cyl"):
    if uv == "cyl":
        cyl_uv(ob, texel)
    else:
        box_uv(ob, texel)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def transfer_weights(ob, body, groups=None):
    """Nearest-body-vertex weight copy, then 3 passes of neighbour smoothing."""
    bme = body.data
    kd = kdtree.KDTree(len(bme.vertices))
    for v in bme.vertices:
        if groups is None or any(body.vertex_groups[g.group].name in groups for g in v.groups):
            kd.insert(v.co, v.index)
    kd.balance()
    names = [vg.name for vg in body.vertex_groups]
    me = ob.data
    W = []
    for v in me.vertices:
        acc = {}
        found = kd.find_n(v.co, 4)
        tot = 0.0
        for co, idx, dist in found:
            w0 = 1.0 / max(dist, 1e-4)
            tot += w0
            for g in bme.vertices[idx].groups:
                acc[names[g.group]] = acc.get(names[g.group], 0.0) + g.weight * w0
        W.append({k: val / tot for k, val in acc.items()})
    # Smooth over mesh adjacency.
    adj = [[] for _ in me.vertices]
    for e in me.edges:
        a, b = e.vertices
        adj[a].append(b)
        adj[b].append(a)
    for _ in range(3):
        NW = []
        for i, w in enumerate(W):
            acc = dict(w)
            for j in adj[i]:
                for k, val in W[j].items():
                    acc[k] = acc.get(k, 0.0) + val
            n = 1 + len(adj[i])
            NW.append({k: val / n for k, val in acc.items()})
        W = NW
    for vg in list(ob.vertex_groups):
        ob.vertex_groups.remove(vg)
    for n in names:
        ob.vertex_groups.new(name=n)
    for i, w in enumerate(W):
        s = sum(w.values()) or 1.0
        for k, val in w.items():
            if val / s > 0.01:
                ob.vertex_groups[k].add([i], val / s, "REPLACE")


# ------------------------------------------------------- cross sections ---
def hull_profile(body, z, band=0.03, n=36, zones=("Torso", "Thigh")):
    """Polar outline (radius per angle) of the body at height z, measured about
    the section's own centroid so the ring hugs the body evenly."""
    pts = [v.co for v in body.data.vertices if abs(v.co.z - z) <= band and abs(v.co.x) <= 0.26
           and not (abs(v.co.x) > 0.2 and v.co.z > 1.3)]
    cx = sum(p.x for p in pts) / max(len(pts), 1)
    cy = sum(p.y for p in pts) / max(len(pts), 1)
    radii = [0.0] * n
    for c in pts:
        a = math.atan2(c.x - cx, -(c.y - cy))
        i = int(((a + math.pi) / (2 * math.pi)) * n) % n
        radii[i] = max(radii[i], math.hypot(c.x - cx, c.y - cy))
    for _ in range(n):
        if all(r > 0 for r in radii):
            break
        radii = [r if r > 0 else max(radii[i - 1], radii[(i + 1) % n]) for i, r in enumerate(radii)]
    radii = [(radii[i - 1] + 2 * radii[i] + radii[(i + 1) % n]) / 4 for i in range(n)]
    return radii, (cx, cy)


def skirt(body, arm, name, z_top, z_hem, offset, flare, material, template, slit_front=False, rows=8,
          wave=0.0):
    n = 36
    radii, (cx, cy) = hull_profile(body, z_top)
    bm = bmesh.new()
    rings = []
    for r_i in range(rows + 1):
        t = r_i / rows
        z = z_top + (z_hem - z_top) * t
        ring = []
        for i in range(n):
            a = -math.pi + 2 * math.pi * (i + 0.5) / n
            r = radii[i] * (1.0 + flare * t) + offset + 0.012 * t
            r += wave * t * math.sin(a * 9.0) * 0.5
            x = cx + math.sin(a) * r
            y = cy - math.cos(a) * r
            ring.append(bm.verts.new((x, y, z)))
        rings.append(ring)
    for a_r, b_r in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            if slit_front and i == n // 2 - 1 and a_r is not rings[0] and a_r is not rings[1]:
                continue
            bm.faces.new([a_r[i], a_r[j], b_r[j], b_r[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = new_object(name, bm, arm, template, material)
    bm.free()
    # Outward normals.
    me = ob.data
    me.update()
    out = sum((p.normal.dot(Vector((p.center.x, p.center.y, 0)).normalized()) for p in me.polygons)) < 0
    if out:
        me.flip_normals()
    transfer_weights(ob, body, groups={"pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r", "spine_01"})
    return ob


def join_into(dst, src):
    bpy.ops.object.select_all(action="DESELECT")
    src.select_set(True)
    dst.select_set(True)
    bpy.context.view_layer.objects.active = dst
    bpy.ops.object.join()
    return dst


# ------------------------------------------------------------- garments ---
def garment(body, arm, name, zones, material, offset, smooth_it=8, extra=None, exclude=None, sub=0,
            quilt=0.0, texel=3.0, uv="cyl", thickness=0.0):
    bm = region(body, zones, extra, exclude)
    if sub:
        subdivide(bm, sub)
    smooth(bm, smooth_it)
    inflate(bm, offset)
    if quilt:
        # Vertical quilting channels on the body, rings on the sleeves.
        bm.normal_update()
        for v in bm.verts:
            c = v.co
            if abs(c.x) > 0.22 and c.z > 1.3:
                s = abs(c.x) / 0.045
            else:
                s = math.atan2(c.x, -c.y) * 0.16 / 0.05 * math.pi * 2 / (2 * math.pi)
                s = math.atan2(c.x, -c.y) * math.hypot(c.x, c.y) / 0.05
            ridge = 0.5 + 0.5 * math.cos(s * 2 * math.pi)
            v.co += v.normal * (quilt * (ridge ** 0.6) - quilt * 0.5)
    ob = new_object(name, bm, arm, body, material)
    bm.free()
    if thickness:
        solidify(ob, thickness)
    return finish(ob, texel, uv)


def footwear(body, arm, name, material, top, shaft_offset=0.012, hull_offset=0.01, texel=4.0):
    """Shoes/boots: a convex-hull last per foot (no toes, flat sole), rounded by
    subdivision, plus an optional shaft fitted to the shin up to `top`."""
    parts = []
    for sgn in (1, -1):
        bm = bmesh.new()
        pts = [v.co.copy() for v in body.data.vertices
               if v.co.z < 0.13 and v.co.x * sgn > 0 and abs(v.co.x) < 0.25]
        vs = [bm.verts.new(p) for p in pts]
        bmesh.ops.convex_hull(bm, input=vs)
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True)
        smooth(bm, 3, 0.5, pin_boundary=False)
        inflate(bm, hull_offset)
        for v in bm.verts:
            if v.co.z < 0.012:
                v.co.z = 0.0 if v.co.z < 0.004 else v.co.z
        # Open the top so a shaft or the hose can meet it.
        top_faces = [f for f in bm.faces if f.calc_center_median().z > 0.118]
        bmesh.ops.delete(bm, geom=top_faces, context="FACES")
        ob = new_object(name + ("_l" if sgn > 0 else "_r"), bm, arm, body, material)
        bm.free()
        transfer_weights(ob, body, groups={"foot_l", "foot_r", "ball_l", "ball_r", "calf_l", "calf_r"})
        parts.append(ob)
    if top > 0.14:
        shaft = garment(body, arm, name + "_shaft", ("ShinLow", "ShinUp"), material, shaft_offset, 5,
                        extra=None, exclude=lambda c, z: c.z > top or c.z < 0.10, uv="box", texel=texel)
        parts.append(shaft)
    main = parts[0]
    for p in parts[1:]:
        join_into(main, p)
    main.name = name
    return finish(main, texel, uv="box")


def over(base, arm, body, name, material, offset, drop=None, smooth_it=3, texel=3.0):
    """A layer built on the OUTSIDE of another garment (mail over the
    gambeson), so it can never be poked through by the layer beneath."""
    bm = bmesh.new()
    bm.from_mesh(base.data)
    if drop is not None:
        kill = [f for f in bm.faces if drop(f.calc_center_median())]
        bmesh.ops.delete(bm, geom=kill, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    smooth(bm, smooth_it, 0.5)
    inflate(bm, offset)
    ob = new_object(name, bm, arm, base, material)
    bm.free()
    return ob


def build(arm, quick=False):
    mats()
    body = bpy.data.objects["Body"]
    armor_list = []

    # ---- split the body into zones (hidden under garments at runtime) ----
    for zname in ZONES:
        bm = region(body, (zname,))
        ob = new_object("B_" + zname, bm, arm, body)
        bm.free()
        ob.data.materials.clear()
        for m in body.data.materials:
            ob.data.materials.append(m)
        # Keep the body's own UVs: rebuild via copy of the original UV layer.
    _copy_uvs_by_position(body, ["B_" + z for z in ZONES])
    L = MAT

    below_belt = lambda c, z: z == "Torso" and c.z < 1.03
    no_face = lambda c, z: z == "Head" and c.y < -0.035 and c.z < 1.775 and abs(c.x) < 0.072
    face_band = lambda c, z: z == "Head" and c.y < -0.02 and c.z < 1.79 and abs(c.x) < 0.08

    # Base layers.
    garment(body, arm, "G_Shirt", ("Torso", "UpperArm", "LowerArm"), L["linen"], 0.007, 10, thickness=0.003)
    g = garment(body, arm, "G_Hose", ("Thigh", "ShinUp", "ShinLow"), L["hose"], 0.005, 4, extra=below_belt)
    footwear(body, arm, "G_Shoes", L["leather"], 0.15)
    footwear(body, arm, "G_Boots", L["leather"], 0.47, shaft_offset=0.014)
    t = garment(body, arm, "G_Tunic", ("Torso", "UpperArm", "LowerArm"), L["wool"], 0.016, 12,
                exclude=lambda c, z: z == "LowerArm" and abs(c.x) > 0.64, thickness=0.004)
    join_into(t, skirt(body, arm, "tunic_skirt", 0.97, 0.50, 0.016, 0.3, L["wool"], body, wave=0.012))
    finish(t, 3.0)
    garment(body, arm, "G_Cap", ("Head",), L["linen"], 0.006, 2,
            exclude=lambda c, z: (c.z < 1.70) or (c.y < -0.03 and c.z < 1.79), uv="box", texel=3.0)
    garment(body, arm, "G_Hood", ("Head", "Neck"), L["wool2"], 0.02, 5,
            extra=lambda c, z: z in ("Torso", "UpperArm") and c.z > 1.36 and abs(c.x) < 0.30,
            exclude=face_band, thickness=0.006)
    garment(body, arm, "G_Gloves", ("Hand",), L["leather"], 0.004, 1, uv="box", texel=5.0)

    # Padded jack / gambeson with quilting and a mid-thigh skirt.
    gb = garment(body, arm, "A_Gambeson", ("Torso", "Neck", "UpperArm", "LowerArm"), L["padded"], 0.03, 14,
                 sub=0 if quick else 1, quilt=0.006,
                 exclude=lambda c, z: (z == "Neck" and c.z > 1.56) or (z == "LowerArm" and abs(c.x) > 0.67))
    sk = skirt(body, arm, "gamb_skirt", 0.97, 0.62, 0.03, 0.22, L["padded"], body, slit_front=True)
    join_into(gb, sk)
    finish(gb, 3.0)

    # Mail haubergeon: elbow sleeves, skirt to upper thigh.
    ml = over(gb, arm, body, "A_Haubergeon", L["mail"], 0.016,
              drop=lambda c: abs(c.x) > 0.52 and c.z > 1.3, texel=7.0)
    finish(ml, 7.0)
    garment(body, arm, "A_MailCoif", ("Head", "Neck"), L["mail"], 0.022, 4,
            extra=lambda c, z: z in ("Torso", "UpperArm") and c.z > 1.40 and abs(c.x) < 0.26,
            exclude=face_band, texel=7.0)

    # Brigandine: riveted cloth-covered plates over the torso.
    br = garment(body, arm, "A_Brigandine", ("Torso",), L["velvet"], 0.062, 26,
                 exclude=lambda c, z: c.z > 1.50 or c.z < 0.94 or (abs(c.x) > 0.17 and c.z > 1.36),
                 thickness=0.01)
    _studs(br, arm, body, L["brass"], rows=((1.08, 1.43), 0.055))

    # Plate cuirass: globose breastplate + backplate, rigid to the spine, and a
    # fauld of three lames at the hips.
    cu = garment(body, arm, "A_Cuirass", ("Torso",), L["plate"], 0.075, 40,
                 exclude=lambda c, z: c.z > 1.49 or c.z < 1.04 or (abs(c.x) > 0.165 and c.z > 1.33),
                 thickness=0.004, uv="box", texel=1.5)
    rigid(cu, lambda co: "spine_03" if co.z > 1.28 else "spine_02")
    for k, (zt, zb) in enumerate(((1.05, 0.99), (1.00, 0.94), (0.95, 0.89))):
        lame = skirt(body, arm, "fauld%d" % k, zt, zb, 0.07 + 0.006 * k, 0.12, L["plate"], body, rows=1)
        rigid(lame, lambda co: "pelvis")
        join_into(cu, lame)
    finish(cu, 1.5, uv="box")

    # Arm harness.
    rb = garment(body, arm, "A_Rerebraces", ("UpperArm",), L["plate"], 0.03, 20,
                 exclude=lambda c, z: abs(c.x) < 0.25, thickness=0.003, uv="box", texel=1.5)
    rigid(rb, lambda co: "upperarm_" + side(co))
    pa = garment(body, arm, "A_Pauldrons", ("UpperArm", "Torso"), L["plate"], 0.07, 30,
                 exclude=lambda c, z: (z == "UpperArm" and abs(c.x) > 0.34) or (z == "Torso" and (abs(c.x) < 0.13 or c.z < 1.36)),
                 thickness=0.004, uv="box", texel=1.5)
    rigid(pa, lambda co: "upperarm_" + side(co) if abs(co.x) > 0.2 else "clavicle_" + side(co))
    vb = garment(body, arm, "A_Vambraces", ("LowerArm",), L["plate"], 0.025, 20,
                 exclude=lambda c, z: abs(c.x) < 0.49, thickness=0.003, uv="box", texel=1.5)
    rigid(vb, lambda co: "lowerarm_" + side(co))
    cou = _couters(arm, body, L["plate"])
    ga = garment(body, arm, "A_Gauntlets", ("Hand",), L["plate"], 0.014, 2,
                 extra=lambda c, z: z == "LowerArm" and abs(c.x) > 0.64, uv="box", texel=2.0)
    # Leg harness.
    cq = garment(body, arm, "A_Cuisses", ("Thigh",), L["plate"], 0.03, 16,
                 exclude=lambda c, z: c.y > 0.05, thickness=0.003, uv="box", texel=1.5)
    rigid(cq, lambda co: "thigh_" + side(co))
    gr = garment(body, arm, "A_Greaves", ("ShinUp", "ShinLow"), L["plate"], 0.026, 16,
                 exclude=lambda c, z: c.z > 0.49, thickness=0.003, uv="box", texel=1.5)
    rigid(gr, lambda co: "calf_" + side(co))
    _poleyns(arm, body, L["plate"])
    footwear(body, arm, "A_Sabatons", L["plate"], 0.14, hull_offset=0.02, texel=2.0)

    # Belts + pouch.
    for name, off in (("X_Belt", 0.022), ("X_BeltOuter", 0.058)):
        b = skirt(body, arm, name, 1.0, 0.96, off, 0.0, L["leather"], body, rows=1)
        rigid(b, lambda co: "pelvis")
        pouch = _pouch(arm, body, off, L["leather"])
        join_into(b, pouch)
        finish(b, 4.0, uv="box")

    import helmets
    helmets.build(arm, body, MAT)


def _copy_uvs_by_position(body, names):
    """Zone meshes came from bmesh copies that already carry the UV layer, so
    nothing to do — kept as a hook in case a split drops UVs."""
    return


def _studs(ob, arm, body, material, rows, spacing=0.05):
    """Rivet heads on a brigandine: small domes on its outer surface."""
    (z0, z1), step = rows
    bm = bmesh.new()
    me = ob.data
    kd = kdtree.KDTree(len(me.vertices))
    for v in me.vertices:
        kd.insert(v.co, v.index)
    kd.balance()
    radii, (cx, cy) = hull_profile(body, 1.2)
    z = z0
    while z <= z1:
        for i in range(28):
            a = -math.pi + 2 * math.pi * (i + 0.5) / 28
            probe = Vector((math.sin(a) * 0.35, cy - math.cos(a) * 0.35, z))
            # Walk inward to the surface: nearest vertex to the probe ray.
            best = None
            for r in [0.3 - k * 0.01 for k in range(25)]:
                p = Vector((math.sin(a) * r, cy - math.cos(a) * r, z))
                co, idx, d = kd.find(p)
                if d < 0.012:
                    best = (co, me.vertices[idx].normal)
                    break
            if best:
                co, n = best
                res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.0055)
                for v in res["verts"]:
                    v.co = v.co + co + n * 0.003
        z += step
    st = new_object("studs", bm, arm, body, material)
    bm.free()
    transfer_weights(st, ob)
    join_into(ob, st)


def _ring(bm, center, axis, radius, width, n=12):
    axis = axis.normalized()
    t1 = axis.orthogonal().normalized()
    t2 = axis.cross(t1)
    a_r, b_r = [], []
    for i in range(n):
        a = 2 * math.pi * i / n
        d = t1 * math.cos(a) + t2 * math.sin(a)
        a_r.append(bm.verts.new(center + d * radius - axis * width / 2))
        b_r.append(bm.verts.new(center + d * radius * 0.92 + axis * width / 2))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([a_r[i], a_r[j], b_r[j], b_r[i]])


def _cop(bm, center, out_dir, radius, depth, n=12):
    """A shallow cone (couter/poleyn cop) facing out_dir."""
    out_dir = out_dir.normalized()
    t1 = out_dir.orthogonal().normalized()
    t2 = out_dir.cross(t1)
    tip = bm.verts.new(center + out_dir * depth)
    ring = []
    for i in range(n):
        a = 2 * math.pi * i / n
        ring.append(bm.verts.new(center + (t1 * math.cos(a) + t2 * math.sin(a)) * radius))
    for i in range(n):
        bm.faces.new([ring[i], ring[(i + 1) % n], tip])
    # Wing plate.
    for i in range(n):
        pass


def _couters(arm, body, material):
    bm = bmesh.new()
    for s in (1, -1):
        _cop(bm, Vector((0.463 * s, 0.115, 1.456)), Vector((0, 1, 0.05)), 0.055, 0.035)
    ob = new_object("A_Couters", bm, arm, body, material)
    bm.free()
    rigid(ob, lambda co: "lowerarm_" + side(co))
    return finish(ob, 1.5, uv="box")


def _poleyns(arm, body, material):
    bm = bmesh.new()
    for s in (1, -1):
        _cop(bm, Vector((0.114 * s, -0.035, 0.53)), Vector((0, -1, 0.02)), 0.07, 0.04)
    ob = new_object("A_Poleyns", bm, arm, body, material)
    bm.free()
    rigid(ob, lambda co: "calf_" + side(co))
    return finish(ob, 1.5, uv="box")


def _pouch(arm, body, off, material):
    radii, (cx, cy) = hull_profile(body, 1.0)
    n = len(radii)
    a = math.radians(-115)  # right hip, slightly back
    i = int(((a + math.pi) / (2 * math.pi)) * n) % n
    r = radii[i] + off + 0.03
    c = Vector((math.sin(a) * r, cy - math.cos(a) * r, 0.94))
    bm = bmesh.new()
    res = bmesh.ops.create_cube(bm, size=1.0)
    for v in res["verts"]:
        v.co = Vector((v.co.x * 0.11, v.co.y * 0.045, v.co.z * 0.12))
        v.co.x *= 1.0 - 0.15 * (v.co.z < 0)
    rot = Vector((math.sin(a), -math.cos(a), 0))
    ang = math.atan2(rot.x, -rot.y)
    for v in res["verts"]:
        x, y = v.co.x, v.co.y
        v.co = Vector((x * math.cos(ang) - y * math.sin(ang), x * math.sin(ang) + y * math.cos(ang), v.co.z)) + c
    ob = new_object("pouch", bm, arm, body, material)
    bm.free()
    rigid(ob, lambda co: "pelvis")
    return ob
