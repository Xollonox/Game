"""XV-century headgear, generated around the measured head of the base body.

Each helmet is a parametric shell: an ellipsoid dome over the skull that turns
into a wall below the head's equator, with a per-azimuth lower edge (so a
sallet can sweep into a tail and a bascinet can drop to the neck) and an
optional face opening. Shells are solidified to real plate thickness and bound
rigidly to the `Head` bone; mail aventails hang from the rim with a
head -> neck -> spine gradient so they drape onto the shoulders.
"""

import bmesh
import bpy
import math
from mathutils import Vector

import wardrobe as W


def head_metrics(body):
    xs, ys, zs = [], [], []
    for v in body.data.vertices:
        c = v.co
        if W.zone_of(c) == "Head" and c.z > 1.62:
            xs.append(c.x)
            ys.append(c.y)
            zs.append(c.z)
    cx = (min(xs) + max(xs)) / 2
    cy = (min(ys) + max(ys)) / 2
    top = max(zs)
    rx = (max(xs) - min(xs)) / 2
    ry = (max(ys) - min(ys)) / 2
    return Vector((cx, cy, top)), rx, ry


def shell(name, arm, body, material, head, rx, ry, rz, cz, bottom, cut=None, point=0.0, flare=None,
          n=40, rows=22, thickness=0.004, waist=0.0):
    """bottom(theta) -> z of the lower edge. theta=0 is the face (-Y)."""
    top, (hcx, hcy) = head.z, (head.x, head.y)
    bm = bmesh.new()
    grid = []
    for r in range(rows + 1):
        s = r / rows
        row = []
        for i in range(n):
            th = -math.pi + 2 * math.pi * i / n
            zb = bottom(th)
            z = top + (zb - top) * s
            if r == 0:
                f = 0.0
            elif z >= cz:
                k = min((z - cz) / max(top - cz, 1e-3), 1.0)
                f = math.sqrt(max(1.0 - k * k, 0.0))
                if point:
                    f = f ** (1.0 + point) if k > 0 else f
            else:
                below = (cz - z)
                f = 1.0 - waist * min(below / 0.12, 1.0)
                if flare:
                    f += flare(th, below)
            x = hcx + math.sin(th) * rx * f
            y = hcy - math.cos(th) * ry * f
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for r in range(rows):
        for i in range(n):
            j = (i + 1) % n
            quad = [grid[r][i], grid[r][j], grid[r + 1][j], grid[r + 1][i]]
            if cut is not None:
                c = sum((v.co for v in quad), Vector()) / 4
                th = math.atan2(c.x - hcx, -(c.y - hcy))
                if cut(th, c.z):
                    continue
            try:
                bm.faces.new(quad)
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = W.new_object(name, bm, arm, body, material)
    bm.free()
    me = ob.data
    me.update()
    outward = sum(p.normal.dot((p.center - Vector((hcx, hcy, cz))).normalized()) for p in me.polygons)
    if outward < 0:
        me.flip_normals()
    if thickness:
        W.solidify(ob, thickness)
    W.rigid(ob, lambda co: "Head")
    return ob


def brim(name, arm, body, material, head, r_in_x, r_in_y, z, width, droop, n=40):
    bm = bmesh.new()
    inner, outer = [], []
    for i in range(n):
        th = -math.pi + 2 * math.pi * i / n
        s, c = math.sin(th), -math.cos(th)
        inner.append(bm.verts.new((head.x + s * r_in_x, head.y + c * r_in_y, z)))
        outer.append(bm.verts.new((head.x + s * (r_in_x + width), head.y + c * (r_in_y + width), z - droop)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([inner[i], inner[j], outer[j], outer[i]])
    ob = W.new_object(name, bm, arm, body, material)
    bm.free()
    W.solidify(ob, 0.004)
    W.rigid(ob, lambda co: "Head")
    return ob


def aventail(name, arm, body, material, head, rx, ry, z_top, bottom_front, bottom_back, n=40, rows=8):
    """Mail curtain hanging from a helmet rim onto the shoulders."""
    radii, (cx, cy) = W.hull_profile(body, 1.47, band=0.04, zones=("Torso",))
    bm = bmesh.new()
    grid = []
    m = len(radii)
    for r in range(rows + 1):
        t = r / rows
        row = []
        for i in range(n):
            th = -math.pi + 2 * math.pi * i / n
            back = (1 - math.cos(th)) / 2  # 0 front, 1 back
            zb = bottom_front + (bottom_back - bottom_front) * back
            # The curtain hangs from under the chin at the front, from the
            # helmet rim at the sides and back.
            zt = z_top - 0.075 * (1 - back) ** 2
            z = zt + (zb - zt) * t
            k = int(((th + math.pi) / (2 * math.pi)) * m) % m
            r_sh = min(radii[k], 0.24) + 0.05
            r0x, r0y = rx, ry
            rrx = r0x + (r_sh - r0x) * (t ** 1.6)
            rry = r0y + (min(r_sh, 0.16) - r0y) * (t ** 1.6)
            row.append(bm.verts.new((head.x + math.sin(th) * rrx, head.y - math.cos(th) * rry, z)))
        grid.append(row)
    for r in range(rows):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new([grid[r][i], grid[r][j], grid[r + 1][j], grid[r + 1][i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = W.new_object(name, bm, arm, body, material)
    bm.free()
    W.solidify(ob, 0.006)
    # Weight gradient: head at the rim, neck, then upper spine at the hem.
    me = ob.data
    for vg in list(ob.vertex_groups):
        ob.vertex_groups.remove(vg)
    for nme in ("Head", "neck_01", "spine_03", "clavicle_l", "clavicle_r"):
        ob.vertex_groups.new(name=nme)
    for v in me.vertices:
        t = max(0.0, min(1.0, (z_top - v.co.z) / max(z_top - 1.43, 0.05)))
        w_head = max(0.0, 1.0 - t * 1.6)
        w_spine = max(0.0, t * 1.4 - 0.4)
        w_neck = max(0.0, 1.0 - w_head - w_spine)
        cl = "clavicle_l" if v.co.x > 0 else "clavicle_r"
        sidew = min(abs(v.co.x) / 0.2, 1.0) * w_spine * 0.6
        tot = w_head + w_neck + w_spine
        ob.vertex_groups["Head"].add([v.index], w_head / tot, "REPLACE")
        ob.vertex_groups["neck_01"].add([v.index], w_neck / tot, "REPLACE")
        ob.vertex_groups["spine_03"].add([v.index], (w_spine - sidew) / tot, "REPLACE")
        ob.vertex_groups[cl].add([v.index], sidew / tot, "REPLACE")
    return ob


def build(arm, body, MAT):
    head, hrx, hry = head_metrics(body)
    cz = head.z - 0.105  # head "equator" (roughly brow level)
    plate, mail, leather, linen = MAT["plate"], MAT["mail"], MAT["leather"], MAT["linen"]
    iron = MAT["iron"]
    cl = 0.022  # clearance over the scalp for a padded liner

    # Cervelliere: close skullcap to the brow.
    W.finish(shell("H_Skullcap", arm, body, iron, head + Vector((0, 0, cl)), hrx + cl, hry + cl, 0.12 + cl, cz + 0.01,
                   lambda th: cz + 0.005, rows=12), 1.5, uv="box")

    # Kettle hat (chapel de fer): a low ridged crown and a broad brim that
    # slopes down ~20 degrees, with a rolled edge.
    k = shell("H_Kettle", arm, body, iron, head + Vector((0, 0, cl + 0.035)), hrx + cl + 0.006, hry + cl + 0.006,
              0.1, cz + 0.02, lambda th: cz + 0.02, point=0.25, rows=12)
    W.join_into(k, brim("kbrim", arm, body, iron, head, hrx + cl + 0.006, hry + cl + 0.006, cz + 0.02, 0.07, 0.028))
    W.join_into(k, brim("kroll", arm, body, iron, head, hrx + cl + 0.074, hry + cl + 0.074, cz - 0.006, 0.008, 0.012))
    W.finish(k, 1.5, uv="box")

    # Bascinet: pointed skull dropping to the jaw at the sides and nape at the
    # back, open face, with a mail aventail.
    def bas_bottom(th):
        back = (1 - math.cos(th)) / 2
        return cz - 0.05 - 0.06 * back
    bas_cut = lambda th, z: abs(th) < 0.62 and z < cz + 0.03
    b = shell("H_Bascinet", arm, body, plate, head + Vector((0, 0.005, cl + 0.035)), hrx + cl, hry + cl + 0.01,
              0.16 + cl, cz, bas_bottom, cut=bas_cut, point=0.5, rows=18)
    W.join_into(b, aventail("aven", arm, body, mail, head, hrx + cl + 0.004, hry + cl + 0.01, cz - 0.03, 1.47, 1.45))
    W.finish(b, 1.5, uv="box")

    # Sallet: rounded skull with a long flared tail and a visor down to the
    # nose, eye-slit left open; worn with a bevor at the chin.
    def sal_bottom(th):
        back = (1 - math.cos(th)) / 2
        return cz - 0.02 - 0.085 * back ** 1.5
    sal_flare = lambda th, below: 0.55 * below * ((1 - math.cos(th)) / 2) ** 2
    sal_cut = lambda th, z: abs(th) < 0.75 and cz - 0.004 < z < cz + 0.018
    s = shell("H_Sallet", arm, body, plate, head + Vector((0, 0.01, cl + 0.015)), hrx + cl + 0.008,
              hry + cl + 0.018, 0.14 + cl, cz + 0.01, sal_bottom, cut=sal_cut, flare=sal_flare, rows=18)
    bev = shell("bevor", arm, body, plate, Vector((head.x, head.y - 0.02, cz - 0.02)), hrx + 0.02, hry + 0.028,
                0.02, cz - 0.021, lambda th: cz - 0.13, cut=lambda th, z: abs(th) > 1.9, rows=6)
    W.join_into(s, bev)
    W.finish(s, 1.5, uv="box")

    # Great bascinet with a hounskull visor: the pointed "pig-face" snout of
    # the late 1300s-1400s, eye slits and breaths, over a mail aventail.
    hb = shell("H_Hounskull", arm, body, plate, head + Vector((0, 0.005, cl + 0.04)), hrx + cl, hry + cl + 0.01,
               0.16 + cl, cz, bas_bottom, cut=bas_cut, point=0.55, rows=18)
    W.join_into(hb, aventail("aven2", arm, body, mail, head, hrx + cl + 0.004, hry + cl + 0.01, cz - 0.03, 1.47, 1.45))

    def snout(th, below):
        return 0.0
    visor = shell("visor", arm, body, plate, Vector((head.x, head.y - 0.01, cz + 0.035)), hrx + cl + 0.012,
                  hry + cl + 0.022, 0.02, cz + 0.034, lambda th: cz - 0.115,
                  cut=lambda th, z: abs(th) > 1.25 or (0.07 < abs(th) < 0.75 and cz - 0.008 < z < cz + 0.008),
                  rows=12, thickness=0.004)
    # Pull the centre of the visor forward into the snout.
    for v in visor.data.vertices:
        c = v.co
        if c.y < head.y:
            th = abs(math.atan2(c.x - head.x, -(c.y - head.y)))
            t = max(0.0, 1.0 - th / 1.1)
            zc = max(0.0, 1.0 - abs(c.z - (cz - 0.045)) / 0.08)
            c.y -= 0.075 * (t ** 1.6) * zc
    visor.data.update()
    W.join_into(hb, visor)
    W.finish(hb, 1.5, uv="box")

    # Barbute: deep enclosing helmet with a T-shaped face opening.
    def bar_cut(th, z):
        return (abs(th) < 0.16 and z < cz + 0.0) or (abs(th) < 0.5 and cz - 0.012 < z < cz + 0.02)
    ba = shell("H_Barbute", arm, body, plate, head + Vector((0, 0.005, cl + 0.01)), hrx + cl, hry + cl + 0.012,
               0.13 + cl, cz, lambda th: cz - 0.135 - 0.01 * ((1 - math.cos(th)) / 2), cut=bar_cut, waist=0.1, rows=20)
    W.finish(ba, 1.5, uv="box")

    # Leather arming cap under nothing: a padded coif for the low tiers.
    W.finish(shell("H_PaddedCoif", arm, body, MAT["padded"], head + Vector((0, 0, 0.012)), hrx + 0.014, hry + 0.014,
                   0.12, cz, lambda th: cz - 0.07 - 0.03 * ((1 - math.cos(th)) / 2),
                   cut=lambda th, z: abs(th) < 0.85 and z < cz + 0.02, rows=12, thickness=0.008), 3.0, uv="box")
