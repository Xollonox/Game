class_name SwordTrail
extends MeshInstance3D
## The arc a swing leaves behind: a ribbon stitched between the blade's base
## and tip positions over the last few physics frames.
##
## This is what makes a swing read as a cut rather than a model moving. The
## blade is a free RigidBody3D spring-following the hand, so its path is
## genuinely simulated — the trail traces real motion, which is why it thins
## out on a checked swing and flares on a committed one without any of that
## being animated.
##
## Rebuilt every frame into an ImmediateMesh in world space (top_level), since
## the geometry is a history of where the blade *was*, not where it is.

const MAX_SAMPLES := 16
## Below this tip speed (m/s) a swing isn't committed enough to leave an arc.
const MIN_SPEED := 3.5
const FADE_SPEED := 7.0

@export var base_local := Vector3(0.0, 0.0, -0.08)
@export var tip_local := Vector3(0.0, -0.05, -0.66)
@export var color := Color(0.85, 0.88, 1.0)

var source: Node3D

var _base_pts: PackedVector3Array = []
var _tip_pts: PackedVector3Array = []
var _im := ImmediateMesh.new()
var _strength := 0.0


func _ready() -> void:
	top_level = true
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The ribbon overlaps itself constantly on a fast arc; writing depth would
	# make those overlaps punch holes in each other.
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material_override = mat


func _physics_process(delta: float) -> void:
	if not source:
		return

	var xf := source.global_transform
	_base_pts.append(xf * base_local)
	_tip_pts.append(xf * tip_local)
	while _base_pts.size() > MAX_SAMPLES:
		_base_pts.remove_at(0)
		_tip_pts.remove_at(0)

	# Drive visibility off how fast the tip is actually travelling, measured
	# from the samples themselves so this works for anything with a transform.
	var speed := 0.0
	if _tip_pts.size() >= 2 and delta > 0.0:
		speed = _tip_pts[-1].distance_to(_tip_pts[-2]) / delta
	var want := clampf((speed - MIN_SPEED) / 12.0, 0.0, 1.0)
	_strength = maxf(want, _strength - FADE_SPEED * delta)
	_strength = clampf(_strength, 0.0, 1.0)

	_rebuild()


func _rebuild() -> void:
	_im.clear_surfaces()
	if _strength <= 0.01 or _base_pts.size() < 2:
		return

	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var count := _base_pts.size()
	for i in count:
		# Oldest samples are the faint end of the arc.
		var along := float(i) / float(count - 1)
		var a := pow(along, 1.6) * 0.55 * _strength
		_im.surface_set_color(Color(color.r, color.g, color.b, a))
		_im.surface_add_vertex(_base_pts[i])
		_im.surface_set_color(Color(color.r, color.g, color.b, a * 0.35))
		_im.surface_add_vertex(_tip_pts[i])
	_im.surface_end()
