class_name ArmourItem
extends RigidBody3D
## A piece of armour or clothing lying in the world: on the armourer's bench,
## knocked off a head, dropped when a man changes kit.
##
## The visual is the garment's own meshes, taken from the fighter model in
## its rest pose (every segment of it, see tools/blender/segments.py) and
## recentred, so a kettle hat on the bench is the kettle hat he will wear.
## It is a real rigid body (box collider from the meshes' bounds, mass from
## the garments' weight) that settles, can be knocked about, and sleeps when
## still. Taking it up: KickbackActor.equip_armour().

const FIGHTER := preload("res://assets/models/characters/fighter/fighter.glb")
static var _source: Node3D  # one instanced fighter model, meshes shared

var item_id := ""  # Shop.ARMOUR id (e.g. "kettle", "gambeson")


static func create(id: String) -> ArmourItem:
	if not Shop.ARMOUR.has(id):
		return null
	var it := ArmourItem.new()
	it.item_id = id
	it.name = "Armour_" + id
	var garments: Array = Shop.ARMOUR[id][2]
	if _source == null or not is_instance_valid(_source):
		_source = FIGHTER.instantiate()  # never added to the tree: a mesh library
	var holder := Node3D.new()
	it.add_child(holder)
	var aabb := AABB()
	var first := true
	var spec := {"garments": garments, "colors": {}}
	for node in _source.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var base := String(mi.name).get_slice("__", 0)
		if not base in garments:
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var slot := src.resource_name.get_slice(".", 0) if src else ""
			var m := FighterLook.material_for(slot, spec, {})
			if m:
				copy.set_surface_override_material(s, m)
		holder.add_child(copy)
		var b := mi.mesh.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	if first:
		it.queue_free()
		return null
	# Recentre on the bounds; collide with a box of the same size.
	holder.position = -aabb.get_center()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size.max(Vector3(0.06, 0.06, 0.06))
	cs.shape = box
	it.add_child(cs)
	it.mass = maxf(0.3, Armory.worn_weight(garments))
	it.collision_layer = 2  # an object, like a dropped weapon
	it.collision_mask = 1 | 2 | 8
	it.can_sleep = true
	var mat := PhysicsMaterial.new()
	mat.friction = 0.9
	mat.bounce = 0.05
	it.physics_material_override = mat
	it.add_to_group(&"armour_items")
	return it


## The slot this piece fills (Shop), for swapping.
func slot() -> String:
	return Shop.slot_of(item_id)


func display_name() -> String:
	return Shop.item_name(item_id)
