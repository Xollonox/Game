"""Real motion capture for the unarmed and kicking moves (headless Blender).

Source: the CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu),
converted ASF/AMC -> BVH by tools/mocap/cmu_to_bvh.py. Boxers throwing jabs,
crosses, hooks and uppercuts; martial artists' front kicks; a punch-kick
combination; blocks. See assets/CREDITS.md.

Each clip is a window of one take, retargeted onto the fighter skeleton:

  * rotations transfer as world-space deltas from each bone's rest, with the
    rest directions aligned first (CMU's rest pose splays the legs 20° and
    lifts the clavicles; the fighter's T-pose does not), so the fighter
    reproduces the actor's limb directions, not the actor's rest offsets;
  * the pelvis carries the actor's weight shift: vertical motion scaled by
    leg length, horizontal motion kept at 40 % and detrended so a clip ends
    where it started (the physics rig, not the clip, moves the fighter);
  * the take is turned so the actor faces the fighter's forward (-Y) at the
    clip's start, and grounded so the lower foot rests on the floor;
  * `mirror` reflects left and right (a right-hand take becomes a left-hand
    one), so every strike exists for both sides without a second actor.

Output: assets/models/characters/fighter/mocap_anims.glb (the Fighter
armature and its actions only, no meshes) plus mocap_anims.json with each
clip's measured strike timing [wind-up, strike, recovery] as fractions of
the clip, which AttackLibrary uses for its hit windows.

  blender -b --python tools/blender/mocap_anims.py
"""

import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
BVH_DIR = os.environ.get("CMU_BVH", "/opt/src/cmu/bvh")
FIGHTER = os.path.join(ROOT, "assets/models/characters/fighter/fighter.glb")
OUT_DIR = os.path.join(ROOT, "assets/models/characters/fighter")

# Target bone <- CMU bone.
BONE_MAP = {
    "pelvis": "root", "spine_01": "lowerback", "spine_02": "upperback", "spine_03": "thorax",
    "neck_01": "lowerneck", "Head": "head",
    "clavicle_l": "lclavicle", "upperarm_l": "lhumerus", "lowerarm_l": "lradius", "hand_l": "lwrist",
    "clavicle_r": "rclavicle", "upperarm_r": "rhumerus", "lowerarm_r": "rradius", "hand_r": "rwrist",
    "thigh_l": "lfemur", "calf_l": "ltibia", "foot_l": "lfoot", "ball_l": "ltoes",
    "thigh_r": "rfemur", "calf_r": "rtibia", "foot_r": "rfoot", "ball_r": "rtoes",
}

# name, take, strike frame (0-based 30 fps frame of the converted BVH, the
# striker's speed peak), frames kept before / after it, mirror, striker (the
# CMU joint whose speed marks the blow; None for guards).
CLIPS = [
    # Boxing (subject 14): guard, jab, cross, hook, uppercut, body shot.
    ("MC_Guard_Box", "14_01", 24, 12, 12, False, None),
    ("MC_Jab", "14_01", 727, 12, 14, False, "lwrist"),
    ("MC_Cross", "14_02", 168, 12, 16, False, "rwrist"),
    ("MC_Hook", "14_02", 252, 14, 16, False, "rwrist"),
    ("MC_Uppercut", "14_03", 356, 14, 16, False, "rwrist"),
    ("MC_Body_Shot", "14_03", 757, 14, 16, False, "rwrist"),
    # Martial-arts front kicks (subject 135), right and left leg.
    ("MC_Kick_Front", "135_04", 91, 20, 24, False, "rfoot"),
    ("MC_Kick_Front_L", "135_04", 143, 20, 22, False, "lfoot"),
    # Blocks (subject 144): the forearm coming up against a blow. A guard is
    # held on its last frame, so each clip ends with the arm raised.
    ("MC_Block_High", "144_26", 80, 14, 1, False, None),
    ("MC_Block_High_L", "144_07", 93, 14, 1, False, None),
    # Ultimate: punch-punch-punch-kick-kick combination (subject 141).
    ("MC_Ultimate_Combo", "141_14", 104, 90, 20, False, "rfoot"),
]


def rot(m):
    return m.to_3x3().normalized().to_4x4()


MIRROR = Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))


def swap_lr(name):
    if name.startswith("l") and name[1:] in ("hipjoint", "femur", "tibia", "foot", "toes", "clavicle", "humerus",
                                             "radius", "wrist", "hand", "fingers", "thumb"):
        return "r" + name[1:]
    if name.startswith("r") and name[1:] in ("hipjoint", "femur", "tibia", "foot", "toes", "clavicle", "humerus",
                                             "radius", "wrist", "hand", "fingers", "thumb"):
        return "l" + name[1:]
    return name


def import_bvh(take):
    before = set(bpy.data.objects)
    bpy.ops.import_anim.bvh(filepath=os.path.join(BVH_DIR, take + ".bvh"), global_scale=1.0,
                            frame_start=1, use_fps_scale=False, rotate_mode="NATIVE")
    arm = next(o for o in bpy.data.objects if o not in before and o.type == "ARMATURE")
    return arm


def src_world(src, name, mirror):
    """Source bone world matrix at the current frame (mirrored if asked)."""
    if mirror:
        name = swap_lr(name)
    m = src.matrix_world @ src.pose.bones[name].matrix
    return MIRROR @ m @ MIRROR if mirror else m


def src_rest(src, name, mirror):
    if mirror:
        name = swap_lr(name)
    m = src.matrix_world @ src.data.bones[name].matrix_local
    return MIRROR @ m @ MIRROR if mirror else m


def heading_fix(src, f, mirror):
    """Yaw about Z turning the actor to face -Y (left hip on +X) at frame f."""
    bpy.context.scene.frame_set(f)
    l = src_world(src, "lfemur", mirror).translation
    r = src_world(src, "rfemur", mirror).translation
    v = (l - r)
    ang = math.atan2(v.y, v.x)  # want v along +X
    return Matrix.Rotation(-ang, 4, "Z")


def bake(src, tgt, name, f0, f1, mirror, dry=False, z_shift=0.0):
    tw_inv = tgt.matrix_world.inverted()
    t_rest = {b.name: b.matrix_local.copy() for b in tgt.data.bones}
    t_rest_w = {n: tgt.matrix_world @ m for n, m in t_rest.items()}
    yaw = heading_fix(src, f0, mirror)

    # Rest alignment: rotate each target rest onto the source rest direction.
    align = {}
    for tb, sb in BONE_MAP.items():
        if tb == "pelvis":
            align[tb] = Matrix.Identity(4)
            continue
        td = (t_rest_w[tb].to_3x3() @ Vector((0, 1, 0))).normalized()
        sd = (yaw @ src_rest(src, sb, mirror)).to_3x3() @ Vector((0, 1, 0))
        align[tb] = td.rotation_difference(sd.normalized()).to_matrix().to_4x4()

    # Leg-length scale for the pelvis translation.
    s_leg = (src_rest(src, "lfemur", False).translation - src_rest(src, "ltoes", False).translation).length
    t_leg = (t_rest_w["thigh_l"].translation - t_rest_w["ball_l"].translation).length
    scale = t_leg / max(s_leg, 1e-3)

    bpy.context.scene.frame_set(f0)
    p_start = (yaw @ src_world(src, "root", mirror)).translation.copy()
    bpy.context.scene.frame_set(f1)
    p_end = (yaw @ src_world(src, "root", mirror)).translation.copy()

    act = None
    if not dry:
        act = bpy.data.actions.new(name)
        tgt.animation_data_create()
        tgt.animation_data.action = act
    for pb in tgt.pose.bones:
        pb.rotation_mode = "QUATERNION"
    feet_low = []
    bones = list(tgt.data.bones)
    n = max(1, f1 - f0)
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        u = (f - f0) / n
        pose = {}
        for b in bones:
            parent = b.parent
            base = pose[parent.name] @ (t_rest[parent.name].inverted() @ t_rest[b.name]) if parent else t_rest[b.name].copy()
            sn = BONE_MAP.get(b.name)
            if sn:
                sw = yaw @ src_world(src, sn, mirror)
                delta = rot(sw) @ rot(yaw @ src_rest(src, sn, mirror)).inverted()
                want = tw_inv @ (delta @ align[b.name] @ rot(t_rest_w[b.name]))
                m = rot(want)
                if b.name == "pelvis":
                    p = sw.translation
                    trend = p_start.lerp(p_end, u)
                    off = Vector(((p.x - trend.x) * 0.4, (p.y - trend.y) * 0.4, p.z * scale + z_shift))
                    pw = Vector((t_rest_w["pelvis"].translation.x, t_rest_w["pelvis"].translation.y, 0.0)) + off
                    m.translation = tw_inv @ pw
                else:
                    m.translation = base.translation
            else:
                m = base
            pose[b.name] = m
        feet_low.append(min((tgt.matrix_world @ pose[k]).translation.z for k in ("ball_l", "ball_r", "foot_l", "foot_r")))
        if dry:
            continue
        for b in bones:
            parent = b.parent
            base = pose[parent.name] @ (t_rest[parent.name].inverted() @ t_rest[b.name]) if parent else t_rest[b.name]
            local = base.inverted() @ pose[b.name]
            pb = tgt.pose.bones[b.name]
            pb.rotation_quaternion = local.to_quaternion()
            fr = f - f0 + 1
            pb.keyframe_insert("rotation_quaternion", frame=fr)
            if b.name == "pelvis" or parent is None:
                pb.location = local.translation
                pb.keyframe_insert("location", frame=fr)
    return act, feet_low


# Clips played as loops (a stance): their tail is blended onto the first frame.
LOOPS = {"MC_Guard_Box"}


def _fcurves(act):
    if hasattr(act, "fcurves") and len(act.fcurves):
        return list(act.fcurves)
    out = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                out += list(bag.fcurves)
    return out


def make_loop(act, tail=0.45):
    """Blends the last `tail` of every channel onto its first key."""
    for fc in _fcurves(act):
        kps = fc.keyframe_points
        n = len(kps)
        if n < 4:
            continue
        v0 = kps[0].co[1]
        k0 = int(n * (1.0 - tail))
        for i in range(k0, n):
            w = (i - k0) / float(max(1, n - 1 - k0))
            w = w * w * (3.0 - 2.0 * w)
            kps[i].co[1] = kps[i].co[1] * (1.0 - w) + v0 * w
            kps[i].handle_left[1] = kps[i].co[1]
            kps[i].handle_right[1] = kps[i].co[1]
        fc.update()


def strike_timing(src, f0, f1, joint, mirror):
    """[wind-up, strike, recovery] as clip fractions from the striker's speed."""
    if not joint:
        return None
    pts = []
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        root = src_world(src, "root", mirror).translation
        pts.append(src_world(src, joint, mirror).translation - root)
    sp = [(pts[i + 1] - pts[i]).length * 30.0 for i in range(len(pts) - 1)]
    peak = max(range(len(sp)), key=lambda i: sp[i])
    # The blow lands as the limb reaches full extension: just after peak speed.
    ext = [(p).length for p in pts]
    land = peak
    for i in range(peak, min(len(ext) - 1, peak + 6)):
        if ext[i + 1] < ext[i]:
            break
        land = i + 1
    start = peak
    while start > 0 and sp[start - 1] > sp[peak] * 0.2:
        start -= 1
    end = land
    while end < len(sp) - 1 and sp[end] > sp[peak] * 0.25:
        end += 1
    n = float(f1 - f0)
    return [round(start / n, 3), round(land / n, 3), round(min(1.0, (end + 2) / n), 3)]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=FIGHTER)
    tgt = bpy.data.objects["Fighter"]
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    tgt.animation_data_create()
    tgt.animation_data.action = None
    for tr in list(tgt.animation_data.nla_tracks):
        tgt.animation_data.nla_tracks.remove(tr)

    rest_floor = min((tgt.matrix_world @ tgt.data.bones[k].matrix_local).translation.z
                     for k in ("ball_l", "ball_r", "foot_l", "foot_r"))
    meta = {}
    kept = []
    cache = {}
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name, take, peak, pre, post, mirror, striker in CLIPS:
        if only and name not in only:
            continue
        f0 = max(1, peak + 1 - pre)  # Blender frames start at 1
        f1 = peak + 1 + post
        if take not in cache:
            cache[take] = import_bvh(take)
        src = cache[take]
        src.animation_data.action.use_fake_user = True
        _, lows = bake(src, tgt, name, f0, f1, mirror, dry=True)
        lows.sort()
        # Ground on the lower quartile: a kick or a hop lifts the feet, the
        # rest of the clip stands.
        shift = rest_floor - lows[len(lows) // 4]
        act, _ = bake(src, tgt, name, f0, f1, mirror, z_shift=shift)
        act.use_fake_user = True
        if name in LOOPS:
            make_loop(act)
        kept.append(act)
        timing = strike_timing(src, f0, f1, striker, mirror)
        meta[name] = {"frames": f1 - f0 + 1, "fps": 30, "take": take, "phases": timing}
        print("MOCAP", name, take, f0, f1, "shift %.3f" % shift, timing)

    tgt.animation_data.action = None
    for a in kept:
        tr = tgt.animation_data.nla_tracks.new()
        tr.name = a.name
        tr.strips.new(a.name, 1, a)
        tr.mute = True
    for o in list(bpy.data.objects):
        if o is not tgt and o.type == "ARMATURE":
            bpy.data.objects.remove(o, do_unlink=True)
    for pb in tgt.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    for a in list(bpy.data.actions):
        if a not in kept:
            bpy.data.actions.remove(a)
    path = os.path.join(OUT_DIR, "mocap_anims.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_apply=False)
    with open(os.path.join(OUT_DIR, "mocap_anims.json"), "w") as fh:
        json.dump(meta, fh, indent=1, sort_keys=True)
    print("MOCAP_EXPORTED", path, len(kept))


main()
