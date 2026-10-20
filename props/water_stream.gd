extends Node3D

## Authority: local, cosmetic. Water coming out of a hose or pressure washer,
## drawn as drops flying the same arc the host uses to decide what got clean
## (net/work/job_tasks.gd water_arc): aim higher to reach the top windows. The
## holder sees their own stream right away; everyone else sees it while the
## prop says it's spraying (replicated). Hydrant water thrashes all over.

const _Rake = preload("res://equipment/rake.gd")
const _PropLooks = preload("res://props/prop_looks.gd")

var _drops: CPUParticles3D


func _ready() -> void:
	top_level = true
	_drops = CPUParticles3D.new()
	_drops.amount = 160
	_drops.lifetime = 1.6
	_drops.local_coords = false
	_drops.spread = 1.6
	_drops.gravity = Vector3(0.0, -9.8, 0.0)
	_drops.emitting = false
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mesh.radial_segments = 6
	mesh.rings = 3
	_drops.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.68, 0.85, 1.0, 0.75)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.1
	material.metallic_specular = 0.9
	_drops.material_override = material
	_drops.scale_amount_min = 0.6
	_drops.scale_amount_max = 1.3
	add_child(_drops)


func _process(_delta: float) -> void:
	var prop := get_parent() as Node3D
	if prop == null:
		return
	var holder := _holder(prop)
	var kind := str(prop.get("kind"))
	var has_water := (kind == "hose" and str(prop.get("hose_source")) != "") or (kind == "pressure_washer" and float(prop.get("water")) > 0.0)
	var mine := holder != null and holder.name == str(Net.local_peer_id())
	var on := has_water and holder != null and (bool(prop.get("spraying")) or (mine and Input.is_action_pressed("primary") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED))
	_drops.emitting = on
	if not on:
		return
	var head := holder.get_node_or_null("Visual/Head") as Node3D
	var look := -head.global_basis.z if head != null else -holder.global_basis.z
	var aim := _Rake.hose_aim(holder, look) if kind == "hose" else look
	var speed := Constants.WASHER_SPEED if kind == "pressure_washer" else float(Constants.WATER_SPEED.get(str(prop.get("hose_source")), 10.0))
	# Out of the nozzle or wand tip you're holding, the way it points.
	var tip: Variant = _PropLooks.spray_tip(prop)
	if tip != null:
		global_position = (tip as Transform3D).origin
		aim = -(tip as Transform3D).basis.z.normalized()
	else:
		var eye := head.global_position if head != null else holder.global_position + Vector3(0.0, 1.6, 0.0)
		global_position = eye + aim * 0.6
	_drops.direction = aim
	_drops.initial_velocity_min = speed * 0.96
	_drops.initial_velocity_max = speed
	# The washer is a short hard blast; the hose an arc that carries.
	_drops.lifetime = 0.35 if kind == "pressure_washer" else 1.6
	_drops.spread = 5.0 if kind == "pressure_washer" else (4.0 if str(prop.get("hose_source")) == "hydrant" else 1.6)


func _holder(prop: Node3D) -> Node3D:
	var holder_id := int(prop.get("held_by"))
	if holder_id == 0:
		return null
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(holder_id):
			return node as Node3D
	return null
