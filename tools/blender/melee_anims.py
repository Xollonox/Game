"""Authored melee animation library, built on an IK rig in headless Blender.

Every key pose is described the way a fencing master would describe it — where
the WEAPON is (grip point, blade direction, which way the true edge faces),
where the feet are, how the hips and shoulders are turned and where the weight
sits — and the rig solves the arms and legs to get there:

* Hands: the right hand is placed so the weapon's anatomical grip frame (fist
  centre, blade out of the thumb side, edge along the knuckles — identical to
  KickbackActor.grip_offset in Godot) lands exactly on the requested weapon
  frame. Two-handed weapons put the left hand on the second grip of the same
  weapon; shields put the left hand behind the shield boss.
* Body: cuts are driven from the ground up (Liechtenauer mechanics): a passing
  or gathering step, the weight moving onto the front leg, hips then shoulders
  turning into the line of the cut, arms extending late, and a follow-through
  that carries the blade past the target instead of stopping on it.

Coordinates in the key tables are in CHARACTER space: r = to the fighter's
right, f = forward, u = up (metres from the floor). The rest-pose character
faces Blender -Y, so r -> -X, f -> -Y.
"""

import bpy
import math
import os
import sys
from mathutils import Matrix, Vector, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import anim_retarget  # noqa: E402

FPS = 30


def C(r, f, u):
    return Vector((-r, -f, u))


def D(r, f, u):
    v = Vector((-r, -f, u))
    return v.normalized() if v.length > 1e-6 else Vector((0, -1, 0))


# ----------------------------------------------------------- grip frames ---
def _frame(center, blade, edge):
    z = -blade.normalized()
    y = (edge - blade * edge.dot(blade)).normalized()
    x = y.cross(z)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = center
    return m


def grip_rest(arm, side, shield=False):
    """World grip frame at rest for hand `side` ('r'/'l') — same formula as
    KickbackActor.grip_offset."""
    b = arm.data.bones
    mw = arm.matrix_world
    hand = mw @ b["hand_" + side].head_local
    f = ((mw @ b["middle_01_" + side].head_local) - hand).normalized()
    t0 = (mw @ b["index_01_" + side].head_local) - (mw @ b["pinky_01_" + side].head_local)
    t = (t0 - f * t0.dot(f)).normalized()
    palm = (t.cross(f) if side == "r" else f.cross(t)).normalized()
    center = hand + f * 0.068 + palm * 0.028
    if shield:
        x = -f
        z = -t
        y = z.cross(x)
        m = Matrix((x, y, z)).transposed().to_4x4()
        m.translation = center + f * 0.02
        return m
    blade = (t + f * 0.18).normalized()
    z = -blade
    y = (f - blade * f.dot(blade)).normalized()
    m = Matrix((y.cross(z), y, z)).transposed().to_4x4()
    m.translation = center
    return m


# --------------------------------------------------------------- the rig ---
class Rig:
    def __init__(self, arm):
        self.arm = arm
        src = arm.copy()
        src.data = arm.data.copy()
        src.animation_data_clear()
        bpy.context.collection.objects.link(src)
        src.name = "AuthorRig"
        self.src = src
        mw = arm.matrix_world
        bones = arm.data.bones
        self.hand_rest = {s: mw @ bones["hand_" + s].matrix_local for s in "rl"}
        self.grip_rest = {s: grip_rest(arm, s) for s in "rl"}
        self.shield_rest = grip_rest(arm, "l", shield=True)
        # hand-in-grip-space: hand_world = weapon_frame @ inv
        self.hand_from_grip = {s: self.grip_rest[s].inverted() @ self.hand_rest[s] for s in "rl"}
        self.hand_from_shield = self.shield_rest.inverted() @ self.hand_rest["l"]
        self.foot_rest = {s: mw @ bones["foot_" + s].matrix_local for s in "lr"}
        self.targets = {}
        for n in ("hand_r", "hand_l", "foot_l", "foot_r", "pole_r", "pole_l", "knee_l", "knee_r"):
            e = bpy.data.objects.new("T_" + n, None)
            bpy.context.collection.objects.link(e)
            e.rotation_mode = "QUATERNION"
            self.targets[n] = e
        pb = src.pose.bones
        for s in "rl":
            ik = pb["lowerarm_" + s].constraints.new("IK")
            ik.target = self.targets["hand_" + s]
            ik.pole_target = self.targets["pole_" + s]
            ik.pole_angle = math.radians(-90 if s == "r" else -90)
            ik.chain_count = 2
            ik.use_tail = True
            cr = pb["hand_" + s].constraints.new("COPY_ROTATION")
            cr.target = self.targets["hand_" + s]
            self.arm_ik = getattr(self, "arm_ik", {})
            self.arm_ik[s] = (ik, cr)
        for s in "lr":
            ik = pb["calf_" + s].constraints.new("IK")
            ik.target = self.targets["foot_" + s]
            ik.pole_target = self.targets["knee_" + s]
            ik.pole_angle = math.radians(-90)
            ik.chain_count = 2
            cr = pb["foot_" + s].constraints.new("COPY_ROTATION")
            cr.target = self.targets["foot_" + s]
        for p in pb:
            p.rotation_mode = "QUATERNION"
        self._curl = {s: self._finger_curls(s) for s in "rl"}

    def _finger_curls(self, s):
        """Local-space rotations that close each finger toward the palm, from
        rest-pose anatomy: axis = finger direction x palm normal."""
        arm = self.arm
        b = arm.data.bones
        hand = b["hand_" + s].head_local
        f = (b["middle_01_" + s].head_local - hand).normalized()
        t0 = b["index_01_" + s].head_local - b["pinky_01_" + s].head_local
        t = (t0 - f * t0.dot(f)).normalized()
        palm = (t.cross(f) if s == "r" else f.cross(t)).normalized()
        out = {}
        for finger in ("index", "middle", "ring", "pinky", "thumb"):
            for j, ang in ((1, 72), (2, 88), (3, 60)):
                bn = "%s_%02d_%s" % (finger, j, s)
                if bn not in b:
                    continue
                bone = b[bn]
                d = (bone.tail_local - bone.head_local).normalized()
                if finger == "thumb":
                    ang = (18, 32, 30)[j - 1]
                axis_w = d.cross(palm)
                if axis_w.length < 1e-4:
                    continue
                axis_l = (bone.matrix_local.to_3x3().inverted() @ axis_w).normalized()
                out[bn] = (axis_l, math.radians(ang))
        return out

    def _key_fingers(self, frame, grip_r=1.0, grip_l=1.0):
        pb = self.src.pose.bones
        for s, amt in (("r", grip_r), ("l", grip_l)):
            for bn, (axis, ang) in self._curl[s].items():
                pb[bn].rotation_quaternion = Quaternion(axis, ang * amt)
                pb[bn].keyframe_insert("rotation_quaternion", frame=frame)

    def clear(self):
        for e in self.targets.values():
            e.animation_data_clear()
        self.src.animation_data_clear()
        for p in self.src.pose.bones:
            p.rotation_quaternion = (1, 0, 0, 0)
            p.location = (0, 0, 0)

    # ----- keying -----
    def _key_empty(self, name, m, frame):
        e = self.targets[name]
        e.matrix_world = m
        e.keyframe_insert("location", frame=frame)
        e.keyframe_insert("rotation_quaternion", frame=frame)

    def _set_world_rot(self, bone, rot_delta, pivot):
        """Rotate pose bone (world) by rot_delta about pivot."""
        pb = self.src.pose.bones[bone]
        bpy.context.view_layer.update()
        mw = self.src.matrix_world
        cur = mw @ pb.matrix
        T = Matrix.Translation(pivot)
        new = T @ rot_delta.to_matrix().to_4x4() @ T.inverted() @ cur
        pb.matrix = mw.inverted() @ new
        bpy.context.view_layer.update()

    def key_pose(self, frame, P):
        src = self.src
        pb = src.pose.bones
        for p in pb:
            p.rotation_quaternion = (1, 0, 0, 0)
            p.location = (0, 0, 0)
        bpy.context.view_layer.update()
        mw = src.matrix_world

        def R(yaw=0.0, pitch=0.0, roll=0.0):
            # yaw>0 turns to the fighter's right, pitch>0 bends forward,
            # roll>0 leans right.
            return (Matrix.Rotation(math.radians(-yaw), 3, "Z") @
                    Matrix.Rotation(math.radians(pitch), 3, "X") @
                    Matrix.Rotation(math.radians(-roll), 3, "Y")).to_quaternion()

        pel = P.get("pelvis", (0, 0, 0))
        prot = P.get("hips", (0, 0, 0))
        pelvis_head = mw @ src.data.bones["pelvis"].head_local
        # Hips: translate then rotate about the hip joint.
        pbp = pb["pelvis"]
        cur = mw @ pbp.matrix
        off = C(*pel)
        new = Matrix.Translation(off) @ cur
        pbp.matrix = mw.inverted() @ new
        bpy.context.view_layer.update()
        self._set_world_rot("pelvis", R(*prot), pelvis_head + off)
        # Torso on top of the hips: spread over the three spine bones.
        sy, sp, sr = P.get("torso", (0, 0, 0))
        for bone, w in (("spine_01", 0.3), ("spine_02", 0.35), ("spine_03", 0.35)):
            head = (mw @ pb[bone].matrix).translation
            self._set_world_rot(bone, R(sy * w, sp * w, sr * w), head)
        # Head keeps the eyes on the opponent: undo most of the torso+hip turn.
        hy, hp = P.get("head", (0, 0))
        total_yaw = sy + prot[0]
        total_pitch = sp + prot[1]
        for bone, w in (("neck_01", 0.45), ("Head", 0.55)):
            head = (mw @ pb[bone].matrix).translation
            self._set_world_rot(bone, R((-total_yaw * 0.85 + hy) * w, (-total_pitch * 0.7 + hp) * w, -sr * w), head)
        # Shoulders: reach and draw.
        for s, key in (("r", "sh_r"), ("l", "sh_l")):
            reach = P.get(key, 0.0)
            if reach:
                bone = "clavicle_" + s
                head = (mw @ pb[bone].matrix).translation
                self._set_world_rot(bone, R(yaw=(-reach if s == "r" else reach)), head)
        for bone in ("pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head", "clavicle_r", "clavicle_l"):
            pb[bone].keyframe_insert("rotation_quaternion", frame=frame)
            if bone == "pelvis":
                pb[bone].keyframe_insert("location", frame=frame)

        lh0 = P.get("lhand")
        self._key_fingers(frame, 1.0, 1.0 if (lh0 == "grip2" or (isinstance(lh0, tuple) and lh0[0] == "shield")) else 0.55)
        # Weapon and hands.
        w = P.get("weapon")
        if w is not None:
            wf = _frame(C(*w[0]), D(*w[1]), D(*w[2]))
            self._key_empty("hand_r", wf @ self.hand_from_grip["r"], frame)
            lh = P.get("lhand")
            if lh == "grip2":
                g2 = P["_grip2"]  # weapon-local offset along the blade axis
                wf2 = wf @ Matrix.Translation(Vector((0, 0, g2)))
                self._key_empty("hand_l", wf2 @ self.hand_from_grip["l"], frame)
            elif isinstance(lh, tuple) and lh[0] == "shield":
                sf = _shield_frame(C(*lh[1]), D(*lh[2]), D(*lh[3]))
                self._key_empty("hand_l", sf @ self.hand_from_shield, frame)
            else:
                lp = lh if lh is not None else ((-0.12, 0.25, 1.12), (0.3, 0.7, 0.5), (0, 0, 1))
                lf = _frame(C(*lp[0]), D(*lp[1]), D(*lp[2]))
                self._key_empty("hand_l", lf @ self.hand_from_grip["l"], frame)
        # Elbow poles: down and out behind each elbow.
        er = P.get("elbow_r", (0.55, -0.25, 0.9))
        el = P.get("elbow_l", (-0.55, -0.2, 0.9))
        self._key_empty("pole_r", Matrix.Translation(C(*er)), frame)
        self._key_empty("pole_l", Matrix.Translation(C(*el)), frame)
        # Feet (ankle positions) and knees.
        for s, key, dflt in (("l", "foot_l", (-0.12, 0.12, 0)), ("r", "foot_r", (0.14, -0.12, 25))):
            fr, ff, fyaw = P.get(key, dflt)[:3]
            lift = P.get(key, dflt)[3] if len(P.get(key, dflt)) > 3 else 0.0
            rest = self.foot_rest[s]
            m = Matrix.Rotation(math.radians(-fyaw), 4, "Z") @ Matrix(rest.to_3x3()).to_4x4()
            m.translation = C(fr, ff + 0.0, rest.translation.z + lift)
            self._key_empty("foot_" + s, m, frame)
            knee = C(fr * 1.1, ff - 0.9 + 0.0, 0.55)
            knee = C(fr * 1.1 + (0.1 if s == "r" else -0.1) * 0.5, ff + 0.9, 0.55)
            self._key_empty("knee_" + s, Matrix.Translation(knee), frame)

    def author(self, name, keys, grip2=None, loop=False):
        """keys: [(seconds, pose_dict)]. Bakes onto the fighter armature."""
        self.clear()
        last = 0
        for t, P in keys:
            if grip2 is not None:
                P = dict(P)
                P["_grip2"] = grip2
                P["lhand"] = "grip2"
                P["elbow_l"] = P.get("elbow_l2", (-0.45, 0.1, 0.85))
            fr = int(round(t * FPS)) + 1
            self.key_pose(fr, P)
            last = fr
        for obj in [self.src] + list(self.targets.values()):
            ad = obj.animation_data
            if ad and ad.action:
                for fc in _fcurves(ad.action):
                    for kp in fc.keyframe_points:
                        kp.interpolation = "BEZIER"
                        kp.easing = "AUTO"
        act = anim_retarget.bake_pose(self.src, 1, last, self.arm, name)
        print("AUTHORED", name, last, "frames")
        return act


def _fcurves(action):
    try:
        return list(action.fcurves)
    except AttributeError:
        out = []
        for layer in action.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    out += list(cb.fcurves)
        return out


def _shield_frame(center, normal, up):
    x = -normal.normalized()
    z = -(up - normal * up.dot(normal)).normalized()
    y = z.cross(x)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = center
    return m


# ---------------------------------------------------------------- poses ---
# Base fighting stance (one-handed): left foot forward, right foot turned out
# behind, knees soft, hips bladed a little to the right, blade held in front
# with the point at the opponent's face (a single-sword Ochs/Pflug hybrid).
STANCE = {
    "pelvis": (0.0, 0.0, -0.06), "hips": (18, 0, 0), "torso": (-6, 6, 0),
    "weapon": ((0.16, 0.32, 1.12), (-0.2, 0.85, 0.45), (0.0, 0.2, 1.0)),
    "lhand": ((-0.2, 0.1, 1.0), (0.3, 0.5, -0.8), (0.2, 0.9, 0.3)),
    "elbow_l": (-0.5, -0.1, 0.9),
    "foot_l": (-0.13, 0.16, -8), "foot_r": (0.17, -0.18, 35),
}


def pose(base, **kw):
    p = dict(base)
    p.update(kw)
    return p


def sword_moves(rig):
    acts = []
    S = STANCE
    breathe = pose(S, pelvis=(0.0, 0.0, -0.075), torso=(-5, 8, 0),
                   weapon=((0.17, 0.31, 1.1), (-0.2, 0.85, 0.42), (0.0, 0.2, 1.0)))
    acts.append(rig.author("Stance_Sword", [(0, S), (1.1, breathe), (2.2, S)]))
    # Guard for blocking: blade across above the head/face, edge up (Hängen).
    guard = pose(S, torso=(-12, 4, 0), hips=(10, 0, 0),
                 weapon=((0.18, 0.3, 1.5), (-0.95, 0.25, 0.2), (0, 0.3, 1)),
                 lhand=((-0.1, 0.3, 1.25), (0.3, 0.8, 0.3), (0, 0, 1)), elbow_r=(0.6, 0.0, 1.2))
    guard2 = pose(guard, pelvis=(0, 0, -0.08))
    acts.append(rig.author("Guard_High", [(0, guard), (0.8, guard2), (1.6, guard)]))

    # Oberhau (Zornhau): from the right shoulder, diagonal down through the
    # opponent's left shoulder, with a passing step of the right foot.
    wind = pose(S, pelvis=(0.02, -0.05, -0.05), hips=(35, -4, 0), torso=(25, -6, 3), sh_r=12,
                weapon=((0.24, -0.02, 1.62), (0.15, -0.55, 0.82), (-0.1, 0.8, 0.3)), elbow_r=(0.6, -0.1, 1.5))
    hit = pose(S, pelvis=(0.0, 0.2, -0.1), hips=(-10, 6, 0), torso=(-18, 14, -2), sh_r=-12,
               weapon=((0.04, 0.55, 1.3), (-0.3, 0.85, 0.2), (-0.25, 0.2, -0.95)),
               foot_r=(0.06, 0.3, 10, 0.0), foot_l=(-0.14, 0.12, -10), elbow_r=(0.45, 0.1, 1.0))
    follow = pose(hit, torso=(-35, 22, -4), hips=(-22, 8, 0),
                  weapon=((-0.2, 0.36, 0.85), (-0.55, 0.55, -0.6), (-0.4, -0.2, -0.9)), elbow_r=(0.2, 0.1, 0.8))
    acts.append(rig.author("Cut_Oberhau", [(0, S), (0.28, wind), (0.47, hit), (0.66, follow), (1.2, S)]))
    # Heavy: bigger windup, full commitment.
    wind_h = pose(wind, hips=(45, -8, 0), torso=(35, -10, 4),
                  weapon=((0.2, -0.12, 1.72), (0.1, -0.75, 0.6), (0, 0.7, 0.7)))
    acts.append(rig.author("Cut_Heavy", [(0, S), (0.45, wind_h), (0.66, hit), (0.9, follow), (1.55, S)]))

    # Mittelhau from the right: level cut, hips lead, edge travelling left.
    w_r = pose(S, hips=(40, 0, 0), torso=(30, 0, 0), sh_r=10,
               weapon=((0.4, 0.02, 1.35), (0.55, -0.55, 0.35), (-0.3, 0.9, 0)), elbow_r=(0.6, -0.4, 1.1))
    h_r = pose(S, pelvis=(0, 0.16, -0.08), hips=(-8, 4, 0), torso=(-14, 6, 0), sh_r=-10,
               weapon=((0.02, 0.55, 1.28), (-0.35, 0.94, 0.02), (-1, 0.0, 0)),
               foot_r=(0.1, 0.2, 15), elbow_r=(0.4, 0.1, 0.9))
    f_r = pose(h_r, hips=(-30, 4, 0), torso=(-32, 8, 0),
               weapon=((-0.32, 0.3, 1.2), (-0.92, -0.05, 0.05), (-0.3, -0.9, 0)), elbow_r=(0.1, 0.2, 0.9))
    acts.append(rig.author("Cut_Mittel_R", [(0, S), (0.27, w_r), (0.45, h_r), (0.63, f_r), (1.15, S)]))
    # Mittelhau from the left (backhand): cross the body first.
    w_l = pose(S, hips=(-25, 0, 0), torso=(-30, 4, 0),
               weapon=((-0.22, 0.2, 1.32), (-0.75, -0.35, 0.3), (0.3, 0.9, 0)), elbow_r=(0.1, 0.3, 1.1))
    h_l = pose(S, pelvis=(0, 0.12, -0.08), hips=(12, 4, 0), torso=(12, 6, 0),
               weapon=((0.12, 0.55, 1.28), (0.3, 0.95, 0.02), (1, 0, 0)), elbow_r=(0.6, 0.0, 1.0))
    f_l = pose(h_l, hips=(30, 2, 0), torso=(28, 4, 0),
               weapon=((0.42, 0.3, 1.22), (0.92, -0.1, 0.05), (0.3, -0.9, 0)), elbow_r=(0.7, -0.2, 1.0))
    acts.append(rig.author("Cut_Mittel_L", [(0, S), (0.25, w_l), (0.43, h_l), (0.6, f_l), (1.1, S)]))
    # Unterhau: rising from below the right hip into the arms and face.
    w_u = pose(S, pelvis=(0, -0.04, -0.12), hips=(32, 10, 0), torso=(20, 14, 0),
               weapon=((0.28, 0.02, 0.8), (0.3, -0.35, -0.85), (0, 0.9, -0.3)), elbow_r=(0.6, -0.2, 0.6))
    h_u = pose(S, pelvis=(0, 0.14, -0.05), hips=(-6, 0, 0), torso=(-10, -4, 0),
               weapon=((0.02, 0.55, 1.3), (-0.2, 0.75, 0.62), (-0.1, -0.5, 0.85)), foot_r=(0.08, 0.18, 15))
    f_u = pose(h_u, torso=(-18, -10, 0),
               weapon=((-0.12, 0.35, 1.65), (-0.35, 0.2, 0.9), (-0.2, -0.9, 0.3)), elbow_r=(0.4, 0.2, 1.4))
    acts.append(rig.author("Cut_Unterhau", [(0, S), (0.27, w_u), (0.45, h_u), (0.62, f_u), (1.15, S)]))
    # Thrust: draw the hilt back to the right hip, then lunge on the front
    # foot with arm, blade and rear leg in one line.
    w_t = pose(S, pelvis=(0, -0.06, -0.06), hips=(30, 0, 0), torso=(22, 0, 0),
               weapon=((0.22, 0.02, 1.18), (0.0, 1.0, 0.08), (0, 0, 1)), elbow_r=(0.6, -0.4, 1.0))
    h_t = pose(S, pelvis=(0, 0.26, -0.13), hips=(-10, 10, 0), torso=(-14, 10, 0), sh_r=-16,
               weapon=((0.06, 0.78, 1.28), (-0.05, 1.0, 0.02), (0, 0, 1)),
               foot_l=(-0.13, 0.5, -10), foot_r=(0.17, -0.22, 40), elbow_r=(0.5, 0.2, 1.1))
    acts.append(rig.author("Thrust_Mid", [(0, S), (0.25, w_t), (0.43, h_t), (0.62, h_t), (1.1, S)]))
    return acts


def blunt_moves(rig):
    """Axes, maces and clubs: shorter, heavier arcs from higher up, the
    wrist locked and the whole body dropping into the blow."""
    acts = []
    S = pose(STANCE, weapon=((0.2, 0.2, 1.15), (0.1, 0.5, 0.86), (0, 0.9, -0.2)))
    acts.append(rig.author("Stance_Blunt", [(0, S), (1.2, pose(S, pelvis=(0, 0, -0.075))), (2.4, S)]))
    w = pose(S, pelvis=(0, -0.06, -0.03), hips=(30, -8, 0), torso=(22, -12, 4), sh_r=14,
             weapon=((0.24, -0.1, 1.72), (0.05, -0.2, 0.98), (0, 0.98, 0.1)), elbow_r=(0.6, 0.1, 1.6))
    h = pose(S, pelvis=(0, 0.2, -0.16), hips=(-8, 12, 0), torso=(-12, 24, 0),
             weapon=((0.08, 0.5, 1.15), (-0.05, 0.75, -0.65), (0, -0.6, -0.8)), foot_r=(0.08, 0.22, 15))
    f = pose(h, torso=(-20, 30, 0), weapon=((0.0, 0.35, 0.8), (-0.2, 0.35, -0.92), (0, -0.9, -0.3)))
    acts.append(rig.author("Blunt_Overhead", [(0, S), (0.34, w), (0.52, h), (0.68, f), (1.25, S)]))
    ws = pose(S, hips=(42, 0, 0), torso=(32, 2, 0),
              weapon=((0.42, -0.05, 1.45), (0.6, -0.5, 0.6), (-0.3, 0.9, 0)))
    hs = pose(S, pelvis=(0, 0.14, -0.1), hips=(-12, 6, 0), torso=(-14, 8, 0),
              weapon=((0.02, 0.5, 1.3), (-0.55, 0.8, 0.2), (-0.9, 0.1, 0)), foot_r=(0.1, 0.18, 15))
    fs = pose(hs, hips=(-30, 4, 0), torso=(-32, 10, 0), weapon=((-0.3, 0.25, 1.1), (-0.9, -0.1, -0.3), (-0.2, -0.9, 0)))
    acts.append(rig.author("Blunt_Side_R", [(0, S), (0.3, ws), (0.48, hs), (0.65, fs), (1.2, S)]))
    wl = pose(S, hips=(-28, 0, 0), torso=(-30, 4, 0),
              weapon=((-0.25, 0.15, 1.45), (-0.7, -0.4, 0.5), (0.3, 0.9, 0)))
    hl = pose(S, pelvis=(0, 0.1, -0.08), hips=(14, 4, 0), torso=(14, 6, 0),
              weapon=((0.14, 0.5, 1.3), (0.5, 0.85, 0.15), (0.9, 0.1, 0)))
    fl = pose(hl, hips=(30, 2, 0), torso=(28, 6, 0), weapon=((0.42, 0.25, 1.15), (0.9, -0.1, -0.3), (0.2, -0.9, 0)))
    acts.append(rig.author("Blunt_Side_L", [(0, S), (0.28, wl), (0.46, hl), (0.62, fl), (1.15, S)]))
    return acts


def dagger_moves(rig):
    acts = []
    S = pose(STANCE, weapon=((0.14, 0.3, 1.1), (0.0, 0.9, 0.4), (0, -0.3, 1)),
             lhand=((-0.14, 0.32, 1.2), (0.3, 0.8, 0.4), (0, 0, 1)), pelvis=(0, 0, -0.1))
    acts.append(rig.author("Stance_Dagger", [(0, S), (1.0, pose(S, pelvis=(0, 0, -0.115))), (2.0, S)]))
    w = pose(S, hips=(25, 0, 0), torso=(18, 0, 0), weapon=((0.24, 0.0, 1.35), (0.1, 0.8, 0.55), (0, -0.5, 1)))
    h = pose(S, pelvis=(0, 0.22, -0.12), hips=(-12, 8, 0), torso=(-12, 10, 0), sh_r=-15,
             weapon=((0.04, 0.6, 1.35), (-0.05, 0.95, 0.25), (0, -0.2, 1)), foot_l=(-0.13, 0.42, -10))
    acts.append(rig.author("Dagger_Stab_High", [(0, S), (0.18, w), (0.34, h), (0.5, h), (0.85, S)]))
    wl = pose(S, pelvis=(0, -0.04, -0.14), hips=(28, 6, 0), weapon=((0.22, 0.02, 0.95), (0.0, 0.95, 0.2), (0, 0, 1)))
    hl = pose(S, pelvis=(0, 0.24, -0.16), hips=(-10, 12, 0), torso=(-10, 14, 0),
              weapon=((0.04, 0.62, 1.05), (-0.05, 0.95, 0.25), (0, 0, 1)), foot_l=(-0.13, 0.44, -10))
    acts.append(rig.author("Dagger_Stab_Low", [(0, S), (0.18, wl), (0.34, hl), (0.5, hl), (0.85, S)]))
    return acts


def shield_moves(rig):
    """One-handed weapon with a heater shield on the left arm."""
    acts = []
    sh = ("shield", (-0.08, 0.36, 1.18), (0.1, 1, 0.05), (0.1, 0.1, 1))
    S = pose(STANCE, lhand=sh, weapon=((0.24, 0.12, 1.3), (0.1, 0.5, 0.86), (0, 0.8, -0.3)),
             hips=(10, 0, 0), torso=(0, 6, 0))
    acts.append(rig.author("Stance_Shield", [(0, S), (1.2, pose(S, pelvis=(0, 0, -0.075))), (2.4, S)]))
    shg = ("shield", (-0.02, 0.4, 1.35), (0.0, 1, 0.1), (0.2, 0.15, 1))
    G = pose(S, lhand=shg, torso=(8, 8, 0), pelvis=(0, 0, -0.1))
    acts.append(rig.author("Guard_Shield", [(0, G), (0.8, pose(G, pelvis=(0, 0, -0.11))), (1.6, G)]))
    bash = ("shield", (0.0, 0.62, 1.3), (0.0, 1, 0.1), (0.2, 0.1, 1))
    B = pose(S, lhand=bash, pelvis=(0, 0.2, -0.1), hips=(-15, 6, 0), torso=(-18, 8, 0), foot_l=(-0.13, 0.4, -10))
    acts.append(rig.author("Shield_Push", [(0, S), (0.2, pose(S, hips=(20, 0, 0), torso=(15, 0, 0))), (0.38, B), (0.8, S)]))
    return acts


def longsword_moves(rig, grip2):
    """Two-handed longsword, Liechtenauer-style: Vom Tag at the shoulder,
    Zornhau, Zwerchhau (thumb-side horizontal from above), Unterhau and a
    thrust from Pflug."""
    acts = []
    # Pflug-ish ready: hilt at the right hip, point at the face.
    S = pose(STANCE, hips=(20, 0, 0), torso=(-4, 6, 0),
             weapon=((0.1, 0.34, 1.12), (-0.12, 0.85, 0.5), (0, 0.3, 1)))
    acts.append(rig.author("Guard_Longsword", [(0, S), (1.1, pose(S, pelvis=(0, 0, -0.075))), (2.2, S)], grip2=grip2))
    tag = pose(S, hips=(30, -3, 0), torso=(18, -5, 0), weapon=((0.16, 0.12, 1.55), (0.05, -0.2, 0.98), (0, 0.98, 0.2)),
               elbow_r=(0.6, 0.0, 1.4), elbow_l=(-0.3, 0.0, 1.2))
    guard = pose(S, weapon=((0.12, 0.32, 1.52), (-0.95, 0.25, 0.2), (0, 0.3, 1)), elbow_r=(0.6, 0, 1.3))
    acts.append(rig.author("Guard_Longsword_High", [(0, guard), (0.8, pose(guard, pelvis=(0, 0, -0.08))), (1.6, guard)],
                           grip2=grip2))
    hit = pose(S, pelvis=(0, 0.22, -0.1), hips=(-14, 6, 0), torso=(-16, 14, 0),
               weapon=((0.0, 0.52, 1.28), (-0.3, 0.88, 0.1), (-0.3, 0.1, -0.95)), foot_r=(0.06, 0.3, 10))
    fol = pose(hit, torso=(-30, 22, 0), hips=(-22, 8, 0),
               weapon=((-0.18, 0.38, 0.9), (-0.55, 0.6, -0.55), (-0.3, -0.3, -0.9)))
    acts.append(rig.author("LS_Oberhau", [(0, S), (0.3, tag), (0.52, hit), (0.7, fol), (1.3, S)], grip2=grip2))
    zw_w = pose(S, hips=(35, 0, 0), torso=(25, -2, 0), weapon=((0.2, 0.05, 1.58), (0.65, -0.5, 0.55), (0.1, 0.4, 0.9)))
    zw_h = pose(S, pelvis=(0, 0.18, -0.08), hips=(-10, 2, 0), torso=(-14, 4, 0),
                weapon=((0.08, 0.5, 1.5), (-0.4, 0.9, -0.1), (-0.95, 0, -0.2)), foot_r=(0.08, 0.24, 15))
    zw_f = pose(zw_h, hips=(-28, 2, 0), torso=(-30, 6, 0),
                weapon=((-0.25, 0.3, 1.45), (-0.95, -0.2, -0.1), (-0.2, -0.95, 0)))
    acts.append(rig.author("LS_Zwerch_R", [(0, S), (0.28, zw_w), (0.47, zw_h), (0.65, zw_f), (1.2, S)], grip2=grip2))
    zl_w = pose(S, hips=(-25, 0, 0), torso=(-28, 0, 0), weapon=((-0.15, 0.1, 1.5), (-0.7, -0.4, 0.5), (0.3, 0.5, 0.8)))
    zl_h = pose(S, pelvis=(0, 0.14, -0.08), hips=(12, 2, 0), torso=(14, 4, 0),
                weapon=((0.14, 0.5, 1.45), (0.45, 0.88, -0.1), (0.95, 0, -0.2)))
    zl_f = pose(zl_h, hips=(28, 2, 0), torso=(28, 4, 0),
                weapon=((0.36, 0.3, 1.4), (0.95, -0.2, -0.1), (0.2, -0.95, 0)))
    acts.append(rig.author("LS_Zwerch_L", [(0, S), (0.27, zl_w), (0.45, zl_h), (0.62, zl_f), (1.15, S)], grip2=grip2))
    un_w = pose(S, pelvis=(0, -0.04, -0.13), hips=(32, 10, 0), torso=(22, 14, 0),
                weapon=((0.22, 0.05, 0.85), (0.3, -0.3, -0.9), (0, 0.9, -0.3)))
    un_h = pose(S, pelvis=(0, 0.15, -0.05), hips=(-8, 0, 0), torso=(-10, -4, 0),
                weapon=((0.02, 0.5, 1.3), (-0.2, 0.72, 0.66), (-0.1, -0.6, 0.8)), foot_r=(0.08, 0.2, 15))
    acts.append(rig.author("LS_Unterhau", [(0, S), (0.28, un_w), (0.47, un_h), (0.66, pose(un_h, torso=(-16, -8, 0),
        weapon=((-0.1, 0.35, 1.62), (-0.3, 0.25, 0.92), (-0.2, -0.9, 0.3)))), (1.2, S)], grip2=grip2))
    th_w = pose(S, pelvis=(0, -0.05, -0.08), hips=(25, 0, 0), weapon=((0.14, 0.12, 1.15), (0, 1, 0.1), (0, 0, 1)))
    th_h = pose(S, pelvis=(0, 0.26, -0.14), hips=(-8, 10, 0), torso=(-10, 10, 0),
                weapon=((0.04, 0.72, 1.3), (-0.03, 1, 0.02), (0, 0, 1)), foot_l=(-0.13, 0.5, -10))
    acts.append(rig.author("LS_Thrust", [(0, S), (0.24, th_w), (0.42, th_h), (0.6, th_h), (1.1, S)], grip2=grip2))
    return acts


def spear_moves(rig, grip2):
    """Spear held low with both hands, the rear (right) hand at the hip, the
    point level with the opponent's chest."""
    acts = []
    S = pose(STANCE, hips=(30, 0, 0), torso=(12, 4, 0),
             weapon=((0.18, 0.0, 1.02), (-0.1, 0.98, 0.18), (0, 0, 1)), elbow_r=(0.6, -0.3, 0.8),
             elbow_l=(-0.5, 0.3, 0.8))
    acts.append(rig.author("Guard_Spear", [(0, S), (1.2, pose(S, pelvis=(0, 0, -0.075))), (2.4, S)], grip2=grip2))
    hi = pose(S, weapon=((0.16, 0.05, 1.45), (-0.1, 0.9, -0.1), (0, 0, 1)), elbow_r=(0.6, -0.2, 1.2))
    acts.append(rig.author("Guard_Spear_High", [(0, hi), (0.8, pose(hi, pelvis=(0, 0, -0.08))), (1.6, hi)], grip2=grip2))
    w = pose(S, pelvis=(0, -0.08, -0.05), weapon=((0.2, -0.12, 1.04), (-0.08, 0.98, 0.15), (0, 0, 1)))
    h = pose(S, pelvis=(0, 0.28, -0.14), hips=(5, 10, 0), torso=(0, 10, 0),
             weapon=((0.12, 0.42, 1.12), (-0.08, 1, 0.05), (0, 0, 1)), foot_l=(-0.13, 0.52, -10))
    acts.append(rig.author("Spear_Thrust", [(0, S), (0.25, w), (0.42, h), (0.58, h), (1.1, S)], grip2=grip2))
    wh = pose(hi, pelvis=(0, -0.08, -0.05), weapon=((0.2, -0.1, 1.5), (-0.05, 0.95, -0.15), (0, 0, 1)))
    hh = pose(hi, pelvis=(0, 0.26, -0.12), hips=(5, 8, 0), weapon=((0.12, 0.42, 1.48), (-0.05, 0.98, -0.2), (0, 0, 1)),
              foot_l=(-0.13, 0.5, -10))
    acts.append(rig.author("Spear_Thrust_High", [(0, S), (0.28, wh), (0.46, hh), (0.62, hh), (1.2, S)], grip2=grip2))
    sw_w = pose(S, hips=(40, 0, 0), torso=(28, 0, 0), weapon=((0.3, -0.05, 1.3), (0.6, 0.75, 0.2), (-0.8, 0.6, 0)))
    sw_h = pose(S, hips=(-20, 4, 0), torso=(-22, 6, 0), pelvis=(0, 0.14, -0.1),
                weapon=((0.0, 0.3, 1.3), (-0.8, 0.6, 0.05), (-0.6, -0.8, 0)))
    acts.append(rig.author("Spear_Swing", [(0, S), (0.3, sw_w), (0.5, sw_h), (0.7, sw_h), (1.25, S)], grip2=grip2))
    return acts


def unarmed_moves(rig):
    acts = []
    S = pose(STANCE, weapon=((0.14, 0.26, 1.35), (0.0, 0.2, 1.0), (0, 1, 0)),
             lhand=((-0.12, 0.3, 1.4), (0, 0.2, 1), (0, 1, 0)))
    acts.append(rig.author("Stance_Idle", [(0, S), (1.3, pose(S, pelvis=(0, 0, -0.07))), (2.6, S)]))
    return acts


def author_all(arm):
    import json
    rig = Rig(arm)
    acts = []
    acts += sword_moves(rig)
    acts += blunt_moves(rig)
    acts += dagger_moves(rig)
    acts += shield_moves(rig)
    arsenal = os.path.join(os.path.dirname(HERE), "..", "assets", "models", "weapons", "arsenal")

    def grip2_of(wid, default):
        try:
            with open(os.path.join(arsenal, wid + ".json")) as f:
                g2 = json.load(f).get("grip2")
            # grip2 is in Godot weapon-local coordinates; the blade runs along
            # local -Z, so its Z component is the offset along the axis.
            return float(g2[2])
        except Exception:
            return default
    acts += longsword_moves(rig, grip2_of("longsword", 0.19))
    acts += spear_moves(rig, grip2_of("war_spear", 0.45))
    acts += unarmed_moves(rig)
    bpy.data.objects.remove(rig.src, do_unlink=True)
    for e in rig.targets.values():
        bpy.data.objects.remove(e, do_unlink=True)
    return acts
