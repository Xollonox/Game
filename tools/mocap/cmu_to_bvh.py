"""CMU Graphics Lab mocap (ASF skeleton + AMC motion) -> BVH.

Blender imports BVH natively but not ASF/AMC, so the CMU takes the fighter
uses are converted here first (plain Python + numpy, no Blender needed).

ASF semantics (Acclaim, as used by the CMU database):
  * every bone has a rest `direction` (world space), a `length`, and an
    `axis` frame C given as XYZ Euler degrees;
  * the AMC frame gives the bone's `dof` rotations M (applied rx, ry, rz);
  * the bone's global rotation is  G = G_parent · C · M · C⁻¹  and the bone
    runs from its parent's end along  G · direction · length.

The BVH written here has identity rest orientations and world-space rest
offsets (the ASF T-pose), so each BVH joint's local rotation is simply
G_parent⁻¹ · G. Lengths are converted to metres ((1/0.45) inch units).

Usage:
  python3 cmu_to_bvh.py SKEL.asf MOTION.amc OUT.bvh [--fps 30] [--start F] [--end F]
"""

import math
import sys

import numpy as np

UNIT = (1.0 / 0.45) * 0.0254  # ASF length unit -> metres


def rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def euler_xyz(x, y, z):
    """Static XYZ (x first): Rz · Ry · Rx."""
    return rz(z) @ ry(y) @ rx(x)


def parse_asf(path):
    bones = {"root": {"name": "root", "dir": np.zeros(3), "len": 0.0, "C": np.eye(3), "dof": ["rx", "ry", "rz"]}}
    children = {}
    lines = [l.strip() for l in open(path, errors="ignore")]
    i = 0
    section = None
    cur = None
    while i < len(lines):
        l = lines[i]
        i += 1
        if not l or l.startswith("#"):
            continue
        if l.startswith(":"):
            section = l.split()[0]
            continue
        tok = l.split()
        if section == ":root":
            if tok[0] == "axis" and tok[1] != "XYZ":
                raise ValueError("root axis order %s unsupported" % tok[1])
            if tok[0] == "orientation":
                bones["root"]["C"] = euler_xyz(*[math.radians(float(v)) for v in tok[1:4]])
        elif section == ":bonedata":
            if tok[0] == "begin":
                cur = {"dof": []}
            elif tok[0] == "end":
                bones[cur["name"]] = cur
                cur = None
            elif tok[0] == "name":
                cur["name"] = tok[1]
            elif tok[0] == "direction":
                cur["dir"] = np.array([float(v) for v in tok[1:4]])
            elif tok[0] == "length":
                cur["len"] = float(tok[1]) * UNIT
            elif tok[0] == "axis":
                if tok[4] != "XYZ":
                    raise ValueError("axis order %s unsupported" % tok[4])
                cur["C"] = euler_xyz(*[math.radians(float(v)) for v in tok[1:4]])
            elif tok[0] == "dof":
                cur["dof"] = tok[1:]
        elif section == ":hierarchy":
            if tok[0] in ("begin", "end"):
                continue
            children[tok[0]] = tok[1:]
    parent = {c: p for p, cs in children.items() for c in cs}
    return bones, children, parent


def parse_amc(path, bones):
    frames = []
    cur = None
    for l in open(path, errors="ignore"):
        l = l.strip()
        if not l or l.startswith("#") or l.startswith(":"):
            continue
        tok = l.split()
        if tok[0].isdigit() and len(tok) == 1:
            cur = {}
            frames.append(cur)
            continue
        cur[tok[0]] = [float(v) for v in tok[1:]]
    return frames


def global_rotations(bones, children, frame):
    """bone -> global 3x3 rotation, plus root translation (metres)."""
    out = {}
    vals = frame.get("root", [0.0] * 6)
    root_pos = np.array(vals[0:3]) * UNIT
    r = [math.radians(v) for v in vals[3:6]]
    C = bones["root"]["C"]
    out["root"] = C @ euler_xyz(*r) @ C.T

    def walk(name):
        for c in children.get(name, []):
            b = bones[c]
            ang = {"rx": 0.0, "ry": 0.0, "rz": 0.0}
            for d, v in zip(b["dof"], frame.get(c, [])):
                if d in ang:
                    ang[d] = math.radians(v)
            M = euler_xyz(ang["rx"], ang["ry"], ang["rz"])
            out[c] = out[name] @ b["C"] @ M @ b["C"].T
            walk(c)

    walk("root")
    return root_pos, out


def to_zxy(R):
    """Euler (z, x, y) degrees with R = Rz · Rx · Ry (BVH 'Zrotation Xrotation Yrotation')."""
    x = math.asin(max(-1.0, min(1.0, R[2, 1])))
    if abs(R[2, 1]) < 0.99999:
        y = math.atan2(-R[2, 0], R[2, 2])
        z = math.atan2(-R[0, 1], R[1, 1])
    else:  # gimbal: fold y into z
        y = 0.0
        z = math.atan2(R[1, 0], R[0, 0])
    return math.degrees(z), math.degrees(x), math.degrees(y)


def write_bvh(asf, amc, out, fps=30.0, start=0, end=None):
    bones, children, parent = parse_asf(asf)
    frames = parse_amc(amc, bones)
    step = max(1, int(round(120.0 / fps)))
    frames = frames[start:end:step]
    order = []  # joint names, depth-first, as written

    lines = ["HIERARCHY"]

    def offset(name):
        if name == "root":
            return np.zeros(3)
        p = parent[name]
        return bones[p]["dir"] * bones[p]["len"] if p != "root" else np.zeros(3)

    def emit(name, depth):
        ind = "  " * depth
        o = offset(name)
        kw = "ROOT" if name == "root" else "JOINT"
        lines.append("%s%s %s" % (ind, kw, name))
        lines.append(ind + "{")
        lines.append("%s  OFFSET %.6f %.6f %.6f" % (ind, *o))
        if name == "root":
            lines.append(ind + "  CHANNELS 6 Xposition Yposition Zposition Zrotation Xrotation Yrotation")
        else:
            lines.append(ind + "  CHANNELS 3 Zrotation Xrotation Yrotation")
        order.append(name)
        kids = children.get(name, [])
        for c in kids:
            emit(c, depth + 1)
        if not kids:
            e = bones[name]["dir"] * bones[name]["len"]
            lines.append(ind + "  End Site")
            lines.append(ind + "  {")
            lines.append("%s    OFFSET %.6f %.6f %.6f" % (ind, *e))
            lines.append(ind + "  }")
        lines.append(ind + "}")

    emit("root", 0)
    lines.append("MOTION")
    lines.append("Frames: %d" % len(frames))
    lines.append("Frame Time: %.6f" % (step / 120.0))
    for f in frames:
        pos, G = global_rotations(bones, children, f)
        row = ["%.5f %.5f %.5f" % tuple(pos)]
        for n in order:
            p = parent.get(n)
            L = G[n] if p is None else G[p].T @ G[n]
            row.append("%.4f %.4f %.4f" % to_zxy(L))
        lines.append(" ".join(row))
    with open(out, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    return len(frames)


if __name__ == "__main__":
    a = sys.argv[1:]
    fps = float(a[a.index("--fps") + 1]) if "--fps" in a else 30.0
    start = int(a[a.index("--start") + 1]) if "--start" in a else 0
    end = int(a[a.index("--end") + 1]) if "--end" in a else None
    n = write_bvh(a[0], a[1], a[2], fps, start, end)
    print("BVH", a[2], n, "frames")
