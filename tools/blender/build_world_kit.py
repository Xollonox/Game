"""Headless Blender build of the medieval fighting-ground kit.

Run:  blender -b --python tools/blender/build_world_kit.py -- --out /data/kit

Each piece is procedural, metre-scale, base-centre pivoted, and exported as its
own GLB with named material slots (see kit_lib.py for the material contract).
The kit is modular: wall segments tile a perimeter, stands/roofs/sheds compose
from posts + panels + gable roofs, and props are instanced freely. LODs are
emitted for the three heaviest silhouettes (gatehouse, round tower, square
tower) so distant placements can swap to a decimated mesh.
"""

import bpy
import bmesh
import math
import random
import sys
import os

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from kit_lib import (reset_scene, box, cyl, sphere, join, box_uv, decimate,
                     export_glb, drop_to_ground, stone, stone_dark, wood,
                     wood_dark, roof, plaster, metal, cloth_red, cloth_blue,
                     cloth, straw, mud, grass, water, thatch)

OUT = "/data/kit"
for i, a in enumerate(sys.argv):
    if a == "--out":
        OUT = sys.argv[i + 1]
os.makedirs(OUT, exist_ok=True)


def finish(name, parts, texel=0.5, lod=None):
    """Join parts, pivot at base-centre, export GLB (+ optional LOD)."""
    ob = join(parts, name)
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    drop_to_ground(ob)
    export_glb(ob, f"{OUT}/{name}.glb", texel)
    if lod:
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.duplicate()
        dup = bpy.context.object
        dup.name = f"{name}_lod"
        decimate(dup, lod)
        export_glb(dup, f"{OUT}/{name}_lod.glb", texel)
        bpy.data.objects.remove(dup, do_unlink=True)
    bpy.data.objects.remove(ob, do_unlink=True)


def gable(name, length, width, rise, thick, base_z, mat_r, overhang=0.18):
    """Two slanted slabs meeting at a ridge along X."""
    half = width * 0.5 + overhang
    slope = math.hypot(half, rise)
    ang = math.atan2(rise, half)
    parts = []
    for s in (1.0, -1.0):
        parts.append(box(f"{name}_{'p' if s > 0 else 'n'}",
                         length + overhang * 2.0, slope, thick,
                         (0.0, s * half * 0.5, base_z + rise * 0.5),
                         mat_r, rot=(-s * ang, 0.0, 0.0)))
    return parts


def merlons(name, length, thickness, height, y, top_z, mat_m, count=None):
    """Crenellation blocks along X."""
    if count is None:
        count = max(3, int(length / 0.9))
    w = length / (count * 2.0 - 1.0)
    parts = []
    for i in range(count):
        x = -length * 0.5 + w * 0.5 + i * 2.0 * w
        parts.append(box(f"{name}_{i}", w, thickness, height, (x, y, top_z + height * 0.5), mat_m))
    return parts


def wavy_cloth(name, w, h, loc, mat_c, rows=6, cols=4, amp=0.06):
    """Hanging banner cloth with a gentle wave, built as a bmesh grid."""
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    bm = bmesh.new()
    grid = []
    for r in range(rows + 1):
        row = []
        for c in range(cols + 1):
            x = (c / cols - 0.5) * w
            z = -(r / rows) * h
            y = math.sin(c * 1.3 + r * 0.4) * amp * (0.4 + 0.6 * r / rows)
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for r in range(rows):
        for c in range(cols):
            bm.faces.new((grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]))
    bm.to_mesh(me)
    bm.free()
    ob.data.materials.append(mat_c)
    ob.location = loc
    return ob


# ============================================================== STONE =====
def wall_straight():
    s, d = stone(), stone_dark()
    parts = [box("body", 4.0, 0.85, 3.0, (0, 0, 1.5), s),
             box("plinth", 4.0, 1.02, 0.55, (0, 0, 0.27), d),
             box("course", 4.02, 0.9, 0.14, (0, 0, 2.35), d)]
    parts += merlons("merlon", 4.0, 0.85, 0.55, 0.0, 3.0, s, 5)
    finish("wall_straight", parts, 0.42)


def wall_broken():
    s, d = stone(), stone_dark()
    parts = [box("body", 3.2, 0.85, 2.1, (0, 0, 1.05), s),
             box("plinth", 3.2, 1.0, 0.5, (0, 0, 0.25), d),
             box("chunk_a", 1.1, 0.8, 0.6, (-0.8, 0, 2.35), s),
             box("chunk_b", 0.7, 0.75, 0.45, (0.55, 0.03, 2.2), s),
             box("rubble_a", 0.5, 0.5, 0.3, (1.25, 0.1, 0.15), d)]
    finish("wall_broken", parts, 0.42)


def wall_corner():
    s, d = stone(), stone_dark()
    parts = [box("x_arm", 3.2, 0.85, 3.0, (1.2, 0, 1.5), s),
             box("y_arm", 0.85, 3.2, 3.0, (0, 1.2, 1.5), s),
             box("plinth", 1.3, 1.3, 0.55, (0.22, 0.22, 0.27), d)]
    parts += merlons("mx", 3.2, 0.85, 0.55, 0.0, 3.0, s, 4)
    for i in range(4):
        parts.append(box(f"my_{i}", 0.85, 0.6, 0.55, (0.0, 0.4 + i * 0.85, 3.27), s))
    finish("wall_corner", parts, 0.42)


def gatehouse():
    s, d, wd = stone(), stone_dark(), wood_dark()
    parts = [
        box("side_l", 2.3, 3.2, 4.6, (-2.85, 0, 2.3), s),
        box("side_r", 2.3, 3.2, 4.6, (2.85, 0, 2.3), s),
        box("lintel", 3.5, 3.2, 1.6, (0, 0, 4.4), s),
        box("arch_band", 3.9, 3.35, 0.35, (0, 0, 3.5), d),
        box("walk", 8.0, 3.4, 0.25, (0, 0, 5.1), d),
    ]
    parts += merlons("ml", 2.3, 3.2, 0.6, 0.0, 4.6, s, 2)
    parts += merlons("mr", 2.3, 3.2, 0.6, 0.0, 4.6, s, 2)
    for i in range(4):
        parts.append(box(f"mw_{i}", 0.7, 3.2, 0.6, (-2.55 + i * 1.7, 0, 5.35), s))
    for sx in (-1.0, 1.0):
        parts.append(cyl(f"bart_{'l' if sx < 0 else 'r'}", 1.55, 5.6, (sx * 4.9, 0.0, 2.8), s, 14))
        parts.append(cyl(f"bband_{'l' if sx < 0 else 'r'}", 1.68, 0.28, (sx * 4.9, 0.0, 4.6), d, 14))
        for i in range(8):
            a = i / 8.0 * math.tau
            parts.append(box(f"bc_{sx}_{i}", 0.42, 0.42, 0.55,
                             (sx * 4.9 + math.cos(a) * 1.32, math.sin(a) * 1.32, 5.87), s))
        parts.append(box(f"door_{'l' if sx < 0 else 'r'}", 1.9, 0.14, 2.6, (sx * 4.9, -1.62, 1.3), wd))
    parts.append(box("gate_l", 1.6, 0.16, 3.3, (-0.85, -1.55, 1.65), wd))
    parts.append(box("gate_r", 1.6, 0.16, 3.3, (0.85, -1.55, 1.65), wd))
    finish("gatehouse", parts, 0.42, lod=0.35)


def tower_round():
    s, d, r = stone(), stone_dark(), roof()
    parts = [cyl("shaft", 1.9, 6.6, (0, 0, 3.3), s, 16),
             cyl("base", 2.15, 0.7, (0, 0, 0.35), d, 16),
             cyl("band", 2.0, 0.3, (0, 0, 3.4), d, 16),
             cyl("crown", 2.12, 0.3, (0, 0, 6.5), d, 16)]
    for i in range(10):
        a = i / 10.0 * math.tau
        parts.append(box(f"m_{i}", 0.5, 0.5, 0.55,
                         (math.cos(a) * 1.78, math.sin(a) * 1.78, 6.9), s))
    for i, (zz, ang) in enumerate([(4.6, 0.4), (2.9, 2.6), (5.4, 4.4)]):
        parts.append(box(f"slit_{i}", 0.16, 0.5, 0.8,
                         (math.cos(ang) * 1.85, math.sin(ang) * 1.85, zz), d, rot=(0, 0, ang)))
    parts.append(cyl("cap", 2.05, 0.5, (0, 0, 7.35), r, 16, r2=1.4))
    finish("tower_round", parts, 0.42, lod=0.32)


def tower_square():
    s, d, r = stone(), stone_dark(), roof()
    parts = [box("shaft", 3.1, 3.1, 6.2, (0, 0, 3.1), s),
             box("base", 3.45, 3.45, 0.7, (0, 0, 0.35), d),
             box("band", 3.25, 3.25, 0.28, (0, 0, 3.5), d),
             box("walk", 3.7, 3.7, 0.3, (0, 0, 6.35), d)]
    for side in range(4):
        a = side * math.tau / 4.0
        for i in range(3):
            off = (i - 1) * 1.0
            parts.append(box(f"m_{side}_{i}", 0.62, 0.62, 0.6,
                             (math.cos(a) * 1.62 - math.sin(a) * off, math.sin(a) * 1.62 + math.cos(a) * off, 6.8), s))
    for i, (zz, side) in enumerate([(4.4, 0), (2.6, 1), (5.2, 2)]):
        a = side * math.tau / 4.0
        parts.append(box(f"slit_{i}", 0.14, 0.6, 0.85,
                         (math.cos(a) * 1.56, math.sin(a) * 1.56, zz), d, rot=(0, 0, a)))
    parts.append(cyl("cap", 2.35, 0.6, (0, 0, 7.15), r, 4, r2=1.5, rot=(0, 0, math.pi / 4)))
    finish("tower_square", parts, 0.42, lod=0.32)


def buttress():
    s, d = stone(), stone_dark()
    parts = [box("base", 1.0, 0.9, 0.5, (0, 0, 0.25), d),
             box("shaft", 0.9, 0.7, 2.2, (0, 0.12, 1.1), s, rot=(0.16, 0, 0)),
             box("cap", 0.8, 0.6, 0.35, (0, 0.42, 2.25), s, rot=(0.3, 0, 0))]
    finish("buttress", parts, 0.42)


def stairs_stone():
    s = stone()
    parts = []
    for i in range(5):
        parts.append(box(f"step_{i}", 2.0, 0.34, 0.19 * (i + 1), (0, -0.9 + i * 0.34, 0.095 * (i + 1)), s))
    finish("stairs_stone", parts, 0.42)


# ============================================================== WOOD ======
def stand_section():
    w, wd = wood(), wood_dark()
    parts = []
    for i in range(3):
        z = 0.45 + i * 0.5
        y = -0.5 + i * 0.85
        parts.append(box(f"tier_{i}", 4.6, 0.9, 0.12, (0, y, z), w))
        parts.append(box(f"riser_{i}", 4.6, 0.1, 0.5, (0, y - 0.45, z - 0.25), wd))
    for sx in (-2.2, 0.0, 2.2):
        parts.append(box(f"post_{sx}", 0.16, 0.16, 2.0, (sx, -0.55, 1.0), wd))
    parts.append(box("rail", 4.6, 0.1, 0.1, (0, -0.58, 0.95), wd))
    parts.append(box("back", 4.6, 0.12, 1.0, (0, 1.35, 1.2), wd))
    finish("stand_section", parts, 0.5)


def stand_roof():
    wd, r = wood_dark(), roof()
    parts = []
    for sx in (-2.6, 2.6):
        parts.append(box(f"post_{sx}", 0.2, 0.2, 2.9, (sx, 1.3, 1.45), wd))
        parts.append(box(f"brace_{sx}", 0.14, 0.14, 1.5, (sx, 0.0, 2.4), wd, rot=(0.7, 0, 0)))
    parts.append(box("beam", 5.6, 0.18, 0.18, (0, 1.3, 2.95), wd))
    parts += gable("roof", 5.8, 3.4, 1.0, 0.14, 3.0, r)
    finish("stand_roof", parts, 0.5)


def shed():
    wd, p, r = wood_dark(), plaster(), roof()
    parts = [box("back", 3.6, 0.14, 2.3, (0, 1.4, 1.15), p),
             box("side_l", 0.14, 2.9, 2.3, (-1.8, 0, 1.15), wd),
             box("side_r", 0.14, 2.9, 2.3, (1.8, 0, 1.15), wd),
             box("post_l", 0.2, 0.2, 2.5, (-1.7, -1.35, 1.25), wd),
             box("post_r", 0.2, 0.2, 2.5, (1.7, -1.35, 1.25), wd),
             box("beam", 3.9, 0.18, 0.18, (0, -1.35, 2.5), wd)]
    parts += gable("roof", 4.0, 3.2, 1.1, 0.15, 2.55, r)
    finish("shed", parts, 0.5)


def fence_section():
    w, wd = wood(), wood_dark()
    parts = [box("post_l", 0.14, 0.14, 1.15, (-1.15, 0, 0.57), wd),
             box("post_r", 0.14, 0.14, 1.15, (1.15, 0, 0.57), wd),
             box("rail_a", 2.4, 0.09, 0.14, (0, 0, 0.95), w),
             box("rail_b", 2.4, 0.09, 0.14, (0, 0, 0.55), w),
             box("rail_c", 2.4, 0.09, 0.14, (0, 0.02, 0.2), w)]
    finish("fence_section", parts, 0.6)


def palisade_section():
    wd = wood_dark()
    parts = []
    for i in range(5):
        h = 1.9 + random.uniform(-0.12, 0.12)
        parts.append(cyl(f"log_{i}", 0.15, h, (-1.2 + i * 0.6, 0, h * 0.5), wd, 7, r2=0.02))
    parts.append(box("rail", 3.0, 0.1, 0.16, (0, 0.14, 1.1), wd))
    finish("palisade_section", parts, 0.6)


def timber_wall():
    wd, p = wood_dark(), plaster()
    parts = [box("infill", 4.0, 0.14, 2.5, (0, 0, 1.25), p),
             box("sill", 4.1, 0.2, 0.2, (0, 0, 0.1), wd),
             box("head", 4.1, 0.2, 0.2, (0, 0, 2.4), wd),
             box("post_l", 0.2, 0.2, 2.5, (-1.95, 0, 1.25), wd),
             box("post_r", 0.2, 0.2, 2.5, (1.95, 0, 1.25), wd),
             box("brace", 0.18, 0.18, 2.0, (0, 0.02, 1.2), wd, rot=(0, 0.62, 0))]
    finish("timber_wall", parts, 0.5)


def roof_piece():
    wd, r = wood_dark(), roof()
    parts = [box("beam", 3.4, 0.16, 0.16, (0, 0, 2.6), wd)]
    parts += gable("roof", 3.6, 2.6, 0.9, 0.14, 2.6, r)
    finish("roof_piece", parts, 0.5)


def platform():
    wd = wood_dark()
    parts = [box("deck", 2.6, 1.7, 0.14, (0, 0, 1.0), wd)]
    for sx in (-1.1, 1.1):
        for sy in (-0.65, 0.65):
            parts.append(box(f"leg_{sx}_{sy}", 0.15, 0.15, 1.0, (sx, sy, 0.5), wd))
    parts.append(box("step", 1.0, 0.34, 0.5, (0, -1.0, 0.25), wd))
    finish("platform", parts, 0.6)


# ============================================================= PROPS ======
def barrel():
    w, m = wood(), metal()
    parts = [cyl("body", 0.33, 0.78, (0, 0, 0.39), w, 12),
             cyl("hoop_a", 0.345, 0.06, (0, 0, 0.16), m, 12),
             cyl("hoop_b", 0.352, 0.06, (0, 0, 0.39), m, 12),
             cyl("hoop_c", 0.345, 0.06, (0, 0, 0.62), m, 12),
             cyl("lid", 0.3, 0.05, (0, 0, 0.79), w, 12)]
    finish("barrel", parts, 0.8)


def crate():
    w, wd = wood(), wood_dark()
    s = 0.72
    parts = [box("body", s, s, s, (0, 0, s * 0.5), w)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(box(f"edge_{sx}_{sy}", 0.07, 0.07, s + 0.02, (sx * s * 0.5, sy * s * 0.5, s * 0.5), wd))
    parts.append(box("band_top", s + 0.02, s + 0.02, 0.06, (0, 0, s - 0.03), wd))
    parts.append(box("band_bot", s + 0.02, s + 0.02, 0.06, (0, 0, 0.05), wd))
    finish("crate", parts, 0.9)


def cart():
    w, wd, m = wood(), wood_dark(), metal()
    parts = [box("bed", 2.3, 1.2, 0.12, (0, 0, 0.72), w),
             box("side_l", 2.3, 0.09, 0.42, (0, -0.55, 0.95), wd),
             box("side_r", 2.3, 0.09, 0.42, (0, 0.55, 0.95), wd),
             box("front", 0.09, 1.2, 0.42, (-1.1, 0, 0.95), wd),
             box("axle", 0.3, 1.5, 0.12, (0.1, 0, 0.55), wd),
             box("shaft_l", 1.7, 0.1, 0.1, (-1.9, -0.35, 0.72), wd, rot=(0, 0.1, 0)),
             box("shaft_r", 1.7, 0.1, 0.1, (-1.9, 0.35, 0.72), wd, rot=(0, 0.1, 0))]
    for sy in (-1, 1):
        parts.append(cyl(f"wheel_{sy}", 0.62, 0.11, (0.1, sy * 0.72, 0.62), wd, 14, rot=(math.pi * 0.5, 0, 0)))
        parts.append(cyl(f"hub_{sy}", 0.13, 0.16, (0.1, sy * 0.72, 0.62), m, 8, rot=(math.pi * 0.5, 0, 0)))
        for i in range(6):
            a = i / 6.0 * math.tau
            parts.append(box(f"spoke_{sy}_{i}", 0.9, 0.07, 0.07, (0.1, sy * 0.72, 0.62), wd,
                             rot=(a, 0, 0)))
    finish("cart", parts, 0.6)


def cage():
    wd = wood_dark()
    s = 1.05
    parts = [box("base", s, s, 0.12, (0, 0, 0.06), wd),
             box("top", s, s, 0.1, (0, 0, 1.35), wd)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(box(f"post_{sx}_{sy}", 0.09, 0.09, 1.35, (sx * 0.48, sy * 0.48, 0.67), wd))
    for i in range(4):
        off = -0.36 + i * 0.24
        parts.append(box(f"bar_x_{i}", 0.05, s, 0.05, (off, 0, 1.2), wd))
        parts.append(box(f"bar_y_{i}", s, 0.05, 0.05, (0, off, 1.2), wd))
    for i in range(4):
        off = -0.36 + i * 0.24
        parts.append(box(f"sbar_x_{i}", 0.05, s, 0.05, (off, 0, 0.25), wd))
        parts.append(box(f"sbar_y_{i}", s, 0.05, 0.05, (0, off, 0.25), wd))
    finish("cage", parts, 0.7)


def hay_bale():
    st = straw()
    parts = [box("body", 1.35, 0.8, 0.78, (0, 0, 0.39), st),
             box("strap_a", 1.37, 0.06, 0.8, (-0.3, 0, 0.39), wood_dark()),
             box("strap_b", 1.37, 0.06, 0.8, (0.3, 0, 0.39), wood_dark())]
    finish("hay_bale", parts, 1.0)


def sack():
    c = cloth()
    parts = [sphere("body", 0.3, (0, 0, 0.28), c, 10, 7, scale=(1.0, 0.9, 1.15)),
             cyl("neck", 0.1, 0.18, (0, 0, 0.56), c, 8)]
    finish("sack", parts, 1.2)


def firewood():
    wd = wood_dark()
    parts = []
    for i in range(4):
        parts.append(cyl(f"log_a_{i}", 0.055, 0.72, (-0.18 + i * 0.12, 0, 0.055), wd, 7, rot=(0, math.pi * 0.5, 0)))
    for i in range(3):
        parts.append(cyl(f"log_b_{i}", 0.055, 0.72, (-0.12 + i * 0.12, 0, 0.16), wd, 7, rot=(0, math.pi * 0.5, 0)))
    for i in range(2):
        parts.append(cyl(f"log_c_{i}", 0.055, 0.72, (-0.06 + i * 0.12, 0, 0.26), wd, 7, rot=(0, math.pi * 0.5, 0)))
    parts.append(cyl("log_top", 0.055, 0.72, (0, 0, 0.36), wd, 7, rot=(0, math.pi * 0.5, 0)))
    finish("firewood", parts, 1.0)


def log_pile():
    wd = wood_dark()
    parts = []
    for i in range(3):
        parts.append(cyl(f"log_a_{i}", 0.14, 1.9, (-0.3 + i * 0.3, 0, 0.14), wd, 8, rot=(0, math.pi * 0.5, 0)))
    for i in range(2):
        parts.append(cyl(f"log_b_{i}", 0.14, 1.9, (-0.15 + i * 0.3, 0, 0.4), wd, 8, rot=(0, math.pi * 0.5, 0)))
    parts.append(cyl("log_c", 0.14, 1.9, (0, 0, 0.66), wd, 8, rot=(0, math.pi * 0.5, 0)))
    finish("log_pile", parts, 0.8)


def brazier():
    m = metal()
    parts = [cyl("bowl", 0.42, 0.3, (0, 0, 0.78), m, 12, r2=0.5),
             cyl("rim", 0.52, 0.07, (0, 0, 0.95), m, 12)]
    for i in range(3):
        a = i / 3.0 * math.tau
        parts.append(box(f"leg_{i}", 0.08, 0.08, 0.8,
                         (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.4), m, rot=(0.18 * math.sin(a), 0.18 * math.cos(a), 0)))
    parts.append(cyl("base", 0.3, 0.06, (0, 0, 0.03), m, 10))
    finish("brazier", parts, 0.9)


def banner(red=True):
    wd, c = wood_dark(), (cloth_red() if red else cloth_blue())
    name = "banner_red" if red else "banner_blue"
    parts = [cyl("pole", 0.045, 3.6, (0, 0, 1.8), wd, 8),
             cyl("finial", 0.07, 0.16, (0, 0, 3.66), wd, 8),
             box("arm", 0.9, 0.06, 0.06, (0.42, 0, 3.35), wd),
             box("base", 0.36, 0.36, 0.12, (0, 0, 0.06), wd)]
    parts.append(wavy_cloth("cloth", 0.85, 1.7, (0.78, 0.0, 3.3), c))
    finish(name, parts, 0.7)


def weapon_rack():
    wd, m = wood_dark(), metal()
    parts = [box("base_l", 0.12, 1.5, 1.1, (-1.05, 0, 0.55), wd),
             box("base_r", 0.12, 1.5, 1.1, (1.05, 0, 0.55), wd),
             box("rail_a", 2.3, 0.09, 0.09, (0, -0.55, 0.9), wd),
             box("rail_b", 2.3, 0.09, 0.09, (0, 0.55, 0.9), wd),
             box("rail_c", 2.3, 0.09, 0.09, (0, 0, 0.6), wd)]
    for i, (x, tilt) in enumerate([(-0.7, 0.28), (-0.2, 0.24), (0.35, 0.3), (0.8, 0.26)]):
        parts.append(box(f"blade_{i}", 0.045, 0.012, 0.95, (x, -0.5, 1.42), m, rot=(tilt, 0, 0)))
        parts.append(box(f"guard_{i}", 0.2, 0.03, 0.03, (x, -0.5 - math.sin(tilt) * 0.45, 0.98), wd))
        parts.append(box(f"grip_{i}", 0.035, 0.035, 0.2, (x, -0.5 - math.sin(tilt) * 0.55, 0.86), wd))
    parts.append(box("axe_handle", 0.05, 0.05, 1.15, (0.0, 0.5, 1.15), wd, rot=(0.22, 0, 0)))
    parts.append(box("axe_head", 0.06, 0.26, 0.2, (0.0, 0.68, 1.72), m, rot=(0.22, 0, 0)))
    finish("weapon_rack", parts, 0.7)


def training_dummy():
    wd, st, c = wood_dark(), straw(), cloth()
    parts = [cyl("post", 0.09, 2.0, (0, 0, 1.0), wd, 8),
             box("cross", 1.5, 0.08, 0.08, (0, 0, 1.55), wd),
             box("torso", 0.5, 0.34, 0.75, (0, 0, 1.15), st),
             sphere("head", 0.16, (0, 0, 1.72), c, 10, 8),
             box("foot_a", 0.5, 0.09, 0.09, (0, 0, 0.08), wd),
             box("foot_b", 0.09, 0.5, 0.09, (0, 0, 0.08), wd)]
    finish("training_dummy", parts, 0.8)


def table():
    w, wd = wood(), wood_dark()
    parts = [box("top", 2.2, 0.85, 0.07, (0, 0, 0.74), w)]
    for sx in (-0.95, 0.95):
        parts.append(box(f"trestle_{sx}", 0.1, 0.75, 0.72, (sx, 0, 0.36), wd))
        parts.append(box(f"foot_{sx}", 0.14, 0.9, 0.08, (sx, 0, 0.04), wd))
    parts.append(box("brace", 1.7, 0.08, 0.08, (0, 0, 0.35), wd))
    finish("table", parts, 0.7)


def bench():
    w, wd = wood(), wood_dark()
    parts = [box("seat", 1.9, 0.34, 0.06, (0, 0, 0.45), w)]
    for sx in (-0.7, 0.7):
        parts.append(box(f"leg_{sx}", 0.09, 0.3, 0.45, (sx, 0, 0.22), wd))
    finish("bench", parts, 0.8)


def bucket():
    w, m = wood(), metal()
    parts = [cyl("body", 0.15, 0.3, (0, 0, 0.15), w, 10, r2=0.18),
             cyl("hoop", 0.19, 0.04, (0, 0, 0.27), m, 10),
             box("handle", 0.36, 0.03, 0.03, (0, 0, 0.3), m)]
    finish("bucket", parts, 1.0)


def wheel_spare():
    wd, m = wood_dark(), metal()
    parts = [cyl("rim", 0.55, 0.1, (0, 0, 0.55), wd, 14, rot=(math.pi * 0.5, 0, 0)),
             cyl("hub", 0.12, 0.16, (0, 0, 0.55), m, 8, rot=(math.pi * 0.5, 0, 0))]
    for i in range(6):
        a = i / 6.0 * math.tau
        parts.append(box(f"spoke_{i}", 0.82, 0.07, 0.07, (0, 0, 0.55), wd, rot=(a, 0, 0)))
    finish("wheel_spare", parts, 0.8)


def grindstone():
    st, wd = stone_dark(), wood_dark()
    parts = [cyl("stone", 0.32, 0.12, (0, 0, 0.62), st, 14, rot=(math.pi * 0.5, 0, 0)),
             box("frame_l", 0.1, 0.5, 0.75, (-0.3, 0, 0.37), wd),
             box("frame_r", 0.1, 0.5, 0.75, (0.3, 0, 0.37), wd),
             box("base", 0.9, 0.5, 0.1, (0, 0, 0.05), wd)]
    finish("grindstone", parts, 0.8)


# =========================================================== TERRAIN ======
def mud_patch(name, r0, seed):
    random.seed(seed)
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    bm = bmesh.new()
    centre = bm.verts.new((0, 0, 0))
    ring = []
    for i in range(18):
        a = i / 18.0 * math.tau
        r = r0 * random.uniform(0.75, 1.15)
        ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, 0.0)))
    for i in range(18):
        bm.faces.new((centre, ring[i], ring[(i + 1) % 18]))
    bm.to_mesh(me)
    bm.free()
    ob.data.materials.append(mud())
    for v in me.vertices:
        v.co.z += 0.02
    finish(name, [ob], 0.5)


def puddle():
    me = bpy.data.meshes.new("puddle")
    ob = bpy.data.objects.new("puddle", me)
    bpy.context.collection.objects.link(ob)
    bm = bmesh.new()
    centre = bm.verts.new((0, 0, 0))
    ring = []
    for i in range(14):
        a = i / 14.0 * math.tau
        r = 1.0 * random.uniform(0.7, 1.2)
        ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, 0.0)))
    for i in range(14):
        bm.faces.new((centre, ring[i], ring[(i + 1) % 14]))
    bm.to_mesh(me)
    bm.free()
    ob.data.materials.append(water())
    for v in me.vertices:
        v.co.z += 0.015
    finish("puddle", [ob], 0.4)


def rubble_pile(seed=11):
    random.seed(seed)
    d = stone_dark()
    parts = []
    for i in range(14):
        a = random.uniform(0, math.tau)
        r = random.uniform(0.0, 0.85)
        s = random.uniform(0.18, 0.42)
        h = max(0.06, 0.5 - r * 0.5) * random.uniform(0.5, 1.3)
        parts.append(box(f"r_{i}", s, s * random.uniform(0.6, 1.1), h,
                         (math.cos(a) * r, math.sin(a) * r, h * 0.5),
                         d, rot=(random.uniform(-0.3, 0.3), random.uniform(0, math.tau), random.uniform(-0.3, 0.3))))
    finish("rubble_pile", parts, 0.9)


def rock(name, size, seed):
    random.seed(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=size, location=(0, 0, size * 0.55))
    ob = bpy.context.object
    ob.name = name
    for v in ob.data.vertices:
        v.co *= random.uniform(0.75, 1.25)
    ob.scale = (1.0, random.uniform(0.75, 1.1), random.uniform(0.6, 0.85))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(stone_dark())
    finish(name, [ob], 0.8)


def grass_tuft(name, seed):
    random.seed(seed)
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    bm = bmesh.new()
    for i in range(7):
        a = i / 7.0 * math.tau + random.uniform(-0.3, 0.3)
        h = random.uniform(0.22, 0.42)
        w = 0.035
        lean = random.uniform(0.08, 0.22)
        x0, y0 = math.cos(a) * 0.03, math.sin(a) * 0.03
        v1 = bm.verts.new((x0 - math.sin(a) * w, y0 + math.cos(a) * w, 0))
        v2 = bm.verts.new((x0 + math.sin(a) * w, y0 - math.cos(a) * w, 0))
        v3 = bm.verts.new((x0 + math.cos(a) * lean, y0 + math.sin(a) * lean, h))
        bm.faces.new((v1, v2, v3))
    bm.to_mesh(me)
    bm.free()
    ob.data.materials.append(grass())
    finish(name, [ob], 0.5)


def dirt_mound():
    me = bpy.data.meshes.new("dirt_mound")
    ob = bpy.data.objects.new("dirt_mound", me)
    bpy.context.collection.objects.link(ob)
    bm = bmesh.new()
    top = bm.verts.new((0, 0, 0.3))
    mid = []
    for i in range(12):
        a = i / 12.0 * math.tau
        mid.append(bm.verts.new((math.cos(a) * 0.7, math.sin(a) * 0.7, 0.18)))
    for i in range(12):
        bm.faces.new((top, mid[i], mid[(i + 1) % 12]))
    bm.to_mesh(me)
    bm.free()
    ob.data.materials.append(mud())
    finish("dirt_mound", [ob], 0.5)


# =========================================================== VILLAGE ======
def house_a():
    p, wd, r, s = plaster(), wood_dark(), roof(), stone()
    parts = [box("body", 4.2, 3.2, 2.7, (0, 0, 1.35), p),
             box("sill", 4.3, 3.3, 0.25, (0, 0, 0.12), s),
             box("beam_l", 0.18, 3.3, 2.7, (-2.05, 0, 1.35), wd),
             box("beam_r", 0.18, 3.3, 2.7, (2.05, 0, 1.35), wd),
             box("door", 0.9, 0.12, 1.8, (-0.8, -1.62, 0.9), wd)]
    parts += gable("roof", 4.6, 3.6, 1.5, 0.16, 2.7, r)
    parts.append(box("chimney", 0.6, 0.6, 1.6, (1.4, 0.6, 3.4), s))
    finish("house_a", parts, 0.5, lod=0.4)


def house_b():
    wd, th = wood_dark(), thatch()
    parts = [box("body", 5.0, 3.6, 2.5, (0, 0, 1.25), wd),
             box("plinth", 5.1, 3.7, 0.3, (0, 0, 0.15), stone_dark()),
             box("door", 1.0, 0.14, 1.9, (0.6, -1.82, 0.95), wood())]
    parts += gable("roof", 5.6, 4.2, 1.6, 0.2, 2.5, th, overhang=0.3)
    finish("house_b", parts, 0.5, lod=0.4)


def house_c():
    p, wd, r = plaster(), wood_dark(), roof()
    parts = [box("body", 3.4, 3.0, 2.4, (0, 0, 1.2), p),
             box("post_a", 0.16, 0.16, 2.4, (-1.6, -1.4, 1.2), wd),
             box("post_b", 0.16, 0.16, 2.4, (1.6, -1.4, 1.2), wd),
             box("post_c", 0.16, 0.16, 2.4, (-1.6, 1.4, 1.2), wd),
             box("post_d", 0.16, 0.16, 2.4, (1.6, 1.4, 1.2), wd)]
    parts += gable("roof", 3.8, 3.4, 1.2, 0.15, 2.4, r)
    finish("house_c", parts, 0.5, lod=0.4)


# ============================================================== RUN =======
reset_scene()
BUILD = [
    wall_straight, wall_broken, wall_corner, gatehouse, tower_round, tower_square,
    buttress, stairs_stone,
    stand_section, stand_roof, shed, fence_section, palisade_section,
    timber_wall, roof_piece, platform,
    barrel, crate, cart, cage, hay_bale, sack, firewood, log_pile, brazier,
    lambda: banner(True), lambda: banner(False),
    weapon_rack, training_dummy, table, bench, bucket, wheel_spare, grindstone,
    lambda: mud_patch("mud_patch_a", 2.2, 3), lambda: mud_patch("mud_patch_b", 1.6, 9),
    puddle, lambda: rubble_pile(11), lambda: rubble_pile(23),
    lambda: rock("rock_a", 0.55, 5), lambda: rock("rock_b", 0.8, 15), lambda: rock("rock_c", 0.35, 25),
    lambda: grass_tuft("grass_tuft_a", 31), lambda: grass_tuft("grass_tuft_b", 41),
    dirt_mound, house_a, house_b, house_c,
]

for fn in BUILD:
    reset_scene()
    fn()

print("KIT_BUILD_DONE", len(BUILD))
