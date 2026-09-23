"""Builds the fighter character GLB headlessly.

    blender -b --python tools/blender/build_fighter.py -- [--quick] [--out assets/models/characters/fighter]

Pipeline:
1. Base human: Quaternius Universal Base Characters (CC0) male body, eyes,
   eyebrows; hairstyles and beard re-parented to the same UE-style skeleton.
2. Animation library: Quaternius UAL1 (Unreal FBX) + UAL2 (glTF) retargeted in
   world space onto the body (tools/blender/anim_retarget.py), plus this repo's
   own authored melee library (tools/blender/melee_anims.py).
3. Wardrobe: layered XV-century clothing and armour generated around the body
   (tools/blender/wardrobe.py). Every garment is a separate skinned mesh named
   by slot (e.g. `W_Torso_Gambeson`); the Godot side toggles them per loadout.
4. One GLB with the armature, all meshes and every action.
"""

import bpy
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import anim_retarget  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
QUICK = "--quick" in ARGS
OUT = ARGS[ARGS.index("--out") + 1] if "--out" in ARGS else "assets/models/characters/fighter"
SRC = os.environ.get("ASSET_SRC", "/opt/src")
UBC = SRC + "/ubc/Universal Base Characters[Standard]"
UBC_BODY = UBC + "/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf"
HAIR_DIR = UBC + "/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)"
UAL1 = SRC + "/ual1/Animation Library[Standard]/Unreal Engine/AL_Standard.fbx"
UAL2 = SRC + "/ual2/Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb"
os.makedirs(OUT, exist_ok=True)

# Clips we keep from the libraries, renamed to the names the game uses.
UAL1_CLIPS = {
    "Idle_Loop": "Idle", "Walk_Loop": "Walk", "Jog_Fwd_Loop": "Jog", "Sprint_Loop": "Sprint",
    "Sword_Idle": "Sword_Idle", "Sword_Attack": "Sword_Attack", "Hit_Chest": "Hit_Chest",
    "Hit_Head": "Hit_Head", "Death01": "Death01", "Roll": "Roll", "Punch_Jab": "Punch_Jab",
    "Punch_Cross": "Punch_Cross", "Crouch_Idle_Loop": "Crouch_Idle", "Walk_Formal_Loop": "Walk_Formal",
    "Idle_Talking_Loop": "Idle_Talking", "Jump_Start": "Jump_Start", "Jump_Land": "Jump_Land",
    "Sitting_Idle_Loop": "Sitting_Idle", "Interact": "Interact",
}
UAL2_CLIPS = {
    "Sword_Regular_A": "Sword_A", "Sword_Regular_A_Rec": "Sword_A_Rec", "Sword_Regular_B": "Sword_B",
    "Sword_Regular_B_Rec": "Sword_B_Rec", "Sword_Regular_C": "Sword_C", "Sword_Regular_Combo": "Sword_Combo",
    "Sword_Heavy_Combo": "Sword_Heavy_Combo", "Sword_Block": "Sword_Block", "Sword_Dash": "Sword_Dash",
    "Hit_Knockback": "Hit_Knockback", "Idle_Shield_Loop": "Shield_Idle", "Idle_Shield_Break": "Shield_Break",
    "Shield_Dash": "Shield_Dash", "Shield_OneShot": "Shield_Bash", "Melee_Hook": "Melee_Hook",
    "Melee_Hook_Rec": "Melee_Hook_Rec", "LayToIdle": "GetUp_Back", "Idle_FoldArms_Loop": "Idle_FoldArms",
    "Idle_No_Loop": "Idle_No", "Yes": "Cheer", "Zombie_Idle_Loop": "Zombie_Idle",
    "Zombie_Walk_Fwd_Loop": "Zombie_Walk", "Zombie_Scratch": "Zombie_Scratch", "OverhandThrow": "Overhand",
}
if QUICK:
    UAL1_CLIPS = {k: v for k, v in UAL1_CLIPS.items() if v in ("Idle", "Walk", "Sword_Idle")}
    UAL2_CLIPS = {k: v for k, v in UAL2_CLIPS.items() if v in ("Sword_A",)}


def import_new(path):
    before = set(bpy.data.objects)
    if path.endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o, do_unlink=True)
            new.remove(o)
    return new


def find_action(prefix_name):
    for a in bpy.data.actions:
        if a.name == prefix_name or a.name.endswith("|" + prefix_name):
            return a
    return None


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    body_objs = import_new(UBC_BODY)
    arm = next(o for o in body_objs if o.type == "ARMATURE")
    arm.name = "Fighter"
    for o in body_objs:
        if o.type == "MESH":
            o.name = {"SuperHero_Male": "Body"}.get(o.name, o.name)

    # Hair: each hair GLTF brings its own armature; re-bind to ours.
    for hair in ("Hair_SimpleParted", "Hair_Buzzed", "Hair_Long", "Hair_Beard"):
        objs = import_new(os.path.join(HAIR_DIR, hair + ".gltf"))
        for o in objs:
            if o.type == "MESH":
                mw = o.matrix_world.copy()
                o.parent = arm
                o.matrix_world = mw
                for m in o.modifiers:
                    if m.type == "ARMATURE":
                        m.object = arm
                if not any(m.type == "ARMATURE" for m in o.modifiers):
                    mod = o.modifiers.new("Armature", "ARMATURE")
                    mod.object = arm
                o.name = hair
        for o in objs:
            if o.type in ("ARMATURE", "EMPTY"):
                bpy.data.objects.remove(o, do_unlink=True)

    existing_actions = set(bpy.data.actions)
    kept = []

    # UAL1 via FBX (UE names).
    src = import_new(UAL1)
    src_arm = next(o for o in src if o.type == "ARMATURE")
    for clip, name in UAL1_CLIPS.items():
        act = find_action(clip)
        if act is None:
            print("MISSING", clip)
            continue
        kept.append(anim_retarget.retarget_action(src_arm, act, arm, name))
        print("RETARGET", clip, "->", name)
    for o in src:
        bpy.data.objects.remove(o, do_unlink=True)

    # UAL2 glTF.
    src = import_new(UAL2)
    src_arm = next(o for o in src if o.type == "ARMATURE")
    for clip, name in UAL2_CLIPS.items():
        act = find_action(clip)
        if act is None:
            print("MISSING", clip)
            continue
        kept.append(anim_retarget.retarget_action(src_arm, act, arm, name))
        print("RETARGET", clip, "->", name)
    for o in src:
        bpy.data.objects.remove(o, do_unlink=True)

    # Drop everything that came along with the imports.
    for a in list(bpy.data.actions):
        if a not in kept:
            bpy.data.actions.remove(a)

    try:
        import melee_anims
        kept += melee_anims.author_all(arm)
    except ImportError:
        pass
    try:
        import wardrobe
        wardrobe.build(arm, quick=QUICK)
        bpy.data.objects.remove(bpy.data.objects["Body"], do_unlink=True)
        # Web budget: no garment over ~3k faces (collapse keeps skin weights).
        for ob in list(bpy.data.objects):
            if ob.type != "MESH" or ob.name[:2] not in ("G_", "A_", "H_", "X_"):
                continue
            n = len(ob.data.polygons)
            if n > 3200:
                m = ob.modifiers.new("Dec", "DECIMATE")
                m.ratio = 3000.0 / n
                bpy.context.view_layer.objects.active = ob
                bpy.ops.object.modifier_move_to_index(modifier="Dec", index=0)
                bpy.ops.object.modifier_apply(modifier="Dec")
                print("DECIMATE", ob.name, n, "->", len(ob.data.polygons))
    except ImportError as e:
        print("NO_WARDROBE", e)

    # Every action as its own NLA track so the exporter emits them all.
    arm.animation_data_create()
    arm.animation_data.action = None
    for a in kept:
        tr = arm.animation_data.nla_tracks.new()
        tr.name = a.name
        st = tr.strips.new(a.name, 1, a)
        tr.mute = True
    bpy.context.scene.frame_set(1)
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)

    # Web budget: embedded skin/hair/eye textures at 1K.
    for img in bpy.data.images:
        if img.size[0] > 1024:
            img.scale(1024, 1024)

    path = os.path.join(OUT, "fighter.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_image_format="NONE",
                              export_apply=False)
    print("FIGHTER_EXPORTED", path, len(kept), "actions")


main()
