"""Split every skinned mesh of the fighter into anatomical limb segments.

Dismemberment needs to hide exactly one limb — skin, sleeves, armour and all —
and to show exactly that limb on the detached part. Each face goes to the
segment of the bone that dominates its vertices' weights (walking up the
bone hierarchy to the nearest segment root), and each mesh is cut into one
object per segment it spans:

    head (neck up), upperarm_l/r, forearm_l/r, hand_l/r,
    thigh_l/r, shin_l/r, foot_l/r, and the core (everything else)

The core piece keeps the original object name (so the wardrobe's names and
materials are unchanged); the others are named "<name>__<segment>".
Corner normals are frozen as custom normals *before* the cut, so the pieces
shade exactly as the whole mesh did: attached, the seams are invisible.

Called by build_fighter.py after the web decimation pass.
"""
import bpy
import bmesh

# Segment roots on the UE / Quaternius skeleton. neck_01 severs with the head.
SEG_ROOTS = {
    "neck_01": "head", "head": "head",
    "upperarm_l": "upperarm_l", "lowerarm_l": "forearm_l", "hand_l": "hand_l",
    "upperarm_r": "upperarm_r", "lowerarm_r": "forearm_r", "hand_r": "hand_r",
    "thigh_l": "thigh_l", "calf_l": "shin_l", "foot_l": "foot_l",
    "thigh_r": "thigh_r", "calf_r": "shin_r", "foot_r": "foot_r",
}
MIN_FACES = 1


def seg_of_bone(arm, name, cache={}):
    key = (arm.name, name)
    if key in cache:
        return cache[key]
    b = arm.data.bones.get(name)
    seg = "core"
    while b is not None:
        if b.name in SEG_ROOTS:
            seg = SEG_ROOTS[b.name]
            break
        b = b.parent
    cache[key] = seg
    return seg


def face_segments(ob, arm):
    """Segment per polygon from the summed vertex-group weights."""
    groups = {g.index: seg_of_bone(arm, g.name) for g in ob.vertex_groups}
    me = ob.data
    vseg_w = []
    for v in me.vertices:
        acc = {}
        for ge in v.groups:
            s = groups.get(ge.group)
            if s is not None:
                acc[s] = acc.get(s, 0.0) + ge.weight
        vseg_w.append(acc)
    out = []
    for p in me.polygons:
        acc = {}
        for vi in p.vertices:
            for s, w in vseg_w[vi].items():
                acc[s] = acc.get(s, 0.0) + w
        out.append(max(acc, key=acc.get) if acc else "core")
    return out


def freeze_normals(ob):
    me = ob.data
    try:
        normals = [tuple(n.vector) for n in me.corner_normals]
    except AttributeError:
        me.calc_normals_split()
        normals = [tuple(l.normal) for l in me.loops]
    me.normals_split_custom_set(normals)


def split(ob, arm):
    segs = face_segments(ob, arm)
    present = sorted(set(segs))
    if len(present) <= 1:
        if present and present[0] != "core":
            ob.name = ob.name + "__" + present[0]
            ob.data.name = ob.name
        return [ob]
    freeze_normals(ob)
    pieces = []
    for seg in present:
        if seg == "core":
            continue
        dup = ob.copy()
        dup.data = ob.data.copy()
        dup.name = ob.name + "__" + seg
        dup.data.name = dup.name
        for c in ob.users_collection:
            c.objects.link(dup)
        _keep_faces(dup, [s == seg for s in segs])
        pieces.append(dup)
    if "core" in present:
        _keep_faces(ob, [s == "core" for s in segs])
        pieces.append(ob)
    else:
        bpy.data.objects.remove(ob, do_unlink=True)
    return pieces


def _keep_faces(ob, keep):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    kill = [f for f in bm.faces if not keep[f.index]]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def split_all(arm):
    n_in = n_out = 0
    for ob in list(bpy.data.objects):
        if ob.type != "MESH" or not ob.vertex_groups:
            continue
        if not any(m.type == "ARMATURE" for m in ob.modifiers) and ob.parent != arm:
            continue
        n_in += 1
        n_out += len(split(ob, arm))
    print("SEGMENTS", n_in, "meshes ->", n_out, "pieces")
