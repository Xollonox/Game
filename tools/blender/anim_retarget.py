"""World-space animation retargeting between humanoid armatures (headless).

Both source and target must share bone NAMES for the bones being transferred
(UE mannequin names: pelvis, spine_01, upperarm_l...), but may differ in bone
roll, rest orientation, object transform (FBX 0.01 scale / 90° X) and limb
proportions. For every frame we take the source bone's world rotation relative
to its own rest, re-apply that delta on top of the target's rest, and rebuild
local pose channels down the hierarchy with plain matrix math — no depsgraph
updates per bone, so a 45-clip library retargets in seconds.

The pelvis also carries translation, scaled by the ratio of rest pelvis
heights, so crouches, lunges and falls keep their weight shift.
"""

import bpy
from mathutils import Matrix


def _rot(m):
    return m.to_3x3().normalized().to_4x4()


def retarget_action(src_arm, action, tgt_arm, name, bone_map=None, frame_step=1, loc_bones=("pelvis",)):
    """Bake `action` (played on src_arm) onto tgt_arm as a new action `name`."""
    src_arm.animation_data_create()
    src_arm.animation_data.action = action
    if action.slots:
        src_arm.animation_data.action_slot = action.slots[0]
    f0, f1 = [int(round(x)) for x in action.frame_range]
    return bake_pose(src_arm, f0, f1, tgt_arm, name, bone_map, frame_step, loc_bones)


def bake_pose(src_arm, f0, f1, tgt_arm, name, bone_map=None, frame_step=1, loc_bones=("pelvis",)):
    """Bake whatever src_arm's evaluated pose is over [f0, f1] (actions,
    constraints, IK — anything) onto tgt_arm as a new action `name`."""
    bone_map = bone_map or {}

    sw = src_arm.matrix_world
    tw = tgt_arm.matrix_world
    tw_inv = tw.inverted()

    tgt_bones = [b for b in tgt_arm.data.bones]  # parents precede children
    src_names = {b.name for b in src_arm.data.bones}

    def src_name(tb):
        return bone_map.get(tb, tb)

    # Rest data.
    t_rest = {b.name: b.matrix_local.copy() for b in tgt_arm.data.bones}
    s_rest_w = {b.name: sw @ b.matrix_local for b in src_arm.data.bones}
    t_rest_w = {n: tw @ m for n, m in t_rest.items()}
    hs = s_rest_w.get(src_name("pelvis"))
    ht = t_rest_w.get("pelvis")
    scale = (ht.translation.z / hs.translation.z) if hs and ht and abs(hs.translation.z) > 1e-4 else 1.0

    new = bpy.data.actions.new(name)
    tgt_arm.animation_data_create()
    tgt_arm.animation_data.action = new
    for pb in tgt_arm.pose.bones:
        pb.rotation_mode = "QUATERNION"

    frames = list(range(f0, f1 + 1, frame_step))
    if frames[-1] != f1:
        frames.append(f1)
    for f in frames:
        bpy.context.scene.frame_set(f)
        pose_arm = {}  # target bone -> armature-space pose matrix
        for b in tgt_bones:
            sn = src_name(b.name)
            parent = b.parent
            if parent is not None:
                rel_rest = t_rest[parent.name].inverted() @ t_rest[b.name]
                base = pose_arm[parent.name] @ rel_rest
            else:
                base = t_rest[b.name].copy()
            if sn in src_names:
                spb = src_arm.pose.bones[sn]
                sw_pose = sw @ spb.matrix
                delta = _rot(sw_pose) @ _rot(s_rest_w[sn]).inverted()
                want_w_rot = delta @ _rot(t_rest_w[b.name])
                want = tw_inv @ want_w_rot
                m = _rot(want)
                if b.name in loc_bones:
                    off_w = (sw_pose.translation - s_rest_w[sn].translation) * scale
                    pos_w = t_rest_w[b.name].translation + off_w
                    m.translation = tw_inv @ pos_w
                else:
                    m.translation = base.translation
            else:
                m = base
            pose_arm[b.name] = m
            # Local basis = (rest-in-parent-pose)^-1 @ pose
            local = base.inverted() @ m if parent is not None else t_rest[b.name].inverted() @ m
            pb = tgt_arm.pose.bones[b.name]
            pb.rotation_quaternion = local.to_quaternion()
            pb.location = local.translation if (b.name in loc_bones or parent is None) else (0, 0, 0)
            pb.keyframe_insert("rotation_quaternion", frame=f - f0 + 1)
            if b.name in loc_bones or parent is None:
                pb.keyframe_insert("location", frame=f - f0 + 1)
    new.use_fake_user = True
    return new
