extends RigidBody3D

## Authority: local, cosmetic. A foot that came off under the mower: a shoe with
## a little pink foot sticking out of it, launched out of the mower's chute,
## bouncing across the lawn and lying there for the rest of the job. Each peer
## launches its own copy. Silly, never gory.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")


static func launch(parent: Node, at: Vector3, heading: Vector3, shoe: Color, skin: Color) -> void:
	var foot: RigidBody3D = load("res://props/lost_foot.gd").new()
	foot.collision_layer = 0
	foot.collision_mask = 1
	foot.mass = 1.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.16, 0.12, 0.3)
	shape.shape = box
	foot.add_child(shape)
	var kit := _MeshKit.new()
	kit.blob(Vector3(0.0, 0.0, -0.03), Vector3(0.075, 0.055, 0.14), shoe, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.blob(Vector3(0.0, -0.035, -0.03), Vector3(0.077, 0.018, 0.142), Color(0.82, 0.78, 0.7), {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
	kit.tube(PackedVector3Array([Vector3(0.0, 0.03, 0.06), Vector3(0.0, 0.16, 0.08)]), PackedFloat32Array([0.05, 0.048]), skin, 10, {"jitter": 0.0})
	kit.blob(Vector3(0.0, 0.17, 0.08), Vector3(0.06, 0.02, 0.06), Color(0.96, 0.95, 0.92), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	foot.add_child(_Stylized.instance(kit.commit(), {"roughness": 0.7}))
	parent.add_child(foot)
	foot.global_position = at + Vector3(0.0, 0.3, 0.0)
	foot.linear_velocity = heading.normalized() * 3.0 + Vector3.UP * 5.5 + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	foot.angular_velocity = Vector3(randf_range(-12.0, 12.0), randf_range(-8.0, 8.0), randf_range(-12.0, 12.0))
