class_name BodyAnatomy
extends RefCounted
## Anatomical corrections to Kickback's generic humanoid joint table, applied
## to the profile before the rig is built. Frames are Kickback's ANATOMICAL
## joint frame: X = flexion, Y = twist about the child bone, Z = lateral;
## 0 = rest pose; degrees.
##
## Kickback's table is generous so any skeleton stands up; a fighter needs
## joints that fail like joints: knees and elbows are hinges (almost no
## twist or side bend), wrists deviate far less sideways than they flex, the
## neck does not turn a full quarter each way under a blow.

const LIMITS := {
	# child rig: [x (flex), y (twist), z (lateral)]
	"LowerArm_L": [Vector2(-5, 145), Vector2(-75, 75), Vector2(-6, 6)],
	"LowerArm_R": [Vector2(-5, 145), Vector2(-75, 75), Vector2(-6, 6)],
	"LowerLeg_L": [Vector2(-5, 140), Vector2(-8, 8), Vector2(-4, 4)],
	"LowerLeg_R": [Vector2(-5, 140), Vector2(-8, 8), Vector2(-4, 4)],
	"Hand_L": [Vector2(-70, 75), Vector2(-10, 10), Vector2(-30, 25)],
	"Hand_R": [Vector2(-70, 75), Vector2(-10, 10), Vector2(-30, 25)],
	"Foot_L": [Vector2(-40, 45), Vector2(-15, 15), Vector2(-25, 25)],
	"Foot_R": [Vector2(-40, 45), Vector2(-15, 15), Vector2(-25, 25)],
	"Head": [Vector2(-55, 60), Vector2(-70, 70), Vector2(-40, 40)],
	"UpperLeg_L": [Vector2(-25, 120), Vector2(-35, 35), Vector2(-40, 45)],
	"UpperLeg_R": [Vector2(-25, 120), Vector2(-35, 35), Vector2(-40, 45)],
}


static func apply(profile: RagdollProfile) -> void:
	for jd: JointDefinition in profile.joints:
		var l = LIMITS.get(jd.child_rig)
		if l == null:
			continue
		jd.limit_x = l[0]
		jd.limit_y = l[1]
		jd.limit_z = l[2]


## Capture-point balance thresholds (see ActiveRagdollController's
## BalanceState note): ratio 1 = capture point on the edge of the feet.
static func tune_balance(t: RagdollTuning) -> void:
	t.balance_stagger_threshold = 0.8
	t.balance_ragdoll_threshold = 1.35
	t.balance_recovery_threshold = 0.6
