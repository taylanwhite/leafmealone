extends SceneTree

## Checks that every mesh-kit shape faces the right way. Run headless:
##   godot --headless --path . --script res://tools/mesh_check.gd
## For each shape it builds one closed mesh around the origin and checks, per
## triangle, that the stored normal points away from the center (lit from the
## outside) and that the winding is Godot's front face (clockwise seen from the
## front), so back-face culling never shows the inside. Exits 1 on any failure.

const _MeshKit: Script = preload("res://props/mesh_kit.gd")


func _init() -> void:
	var shapes := {
		"blob": func(kit: RefCounted) -> void: kit.call("blob", Vector3.ZERO, Vector3(1.0, 0.8, 1.2), Color.WHITE, {"seed": 3}),
		"blob_smooth": func(kit: RefCounted) -> void: kit.call("blob", Vector3.ZERO, Vector3.ONE, Color.WHITE, {"flat": false, "detail": 2}),
		"rbox": func(kit: RefCounted) -> void: kit.call("rbox", Vector3.ZERO, Vector3(1.0, 0.5, 0.7), Color.WHITE, 5.0),
		"box": func(kit: RefCounted) -> void: kit.call("box", Vector3.ZERO, Vector3(1.0, 2.0, 0.5), Color.WHITE),
		"cone": func(kit: RefCounted) -> void: kit.call("cone", Vector3(0.0, -1.0, 0.0), 1.0, 2.0, Color.WHITE),
		"tube": func(kit: RefCounted) -> void: kit.call("tube", PackedVector3Array([Vector3(0, -1, 0), Vector3(0, 0, 0), Vector3(0, 1, 0)]), PackedFloat32Array([0.4, 0.4, 0.4]), Color.WHITE),
	}
	var failed := false
	for shape_name: String in shapes:
		var kit: RefCounted = _MeshKit.new()
		(shapes[shape_name] as Callable).call(kit)
		var mesh: ArrayMesh = kit.call("commit")
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var center := Vector3.ZERO
		for v: Vector3 in vertices:
			center += v
		center /= maxf(float(vertices.size()), 1.0)
		var count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
		var inward_normals := 0
		var back_facing := 0
		for tri: int in count:
			var ia := indices[tri * 3] if not indices.is_empty() else tri * 3
			var ib := indices[tri * 3 + 1] if not indices.is_empty() else tri * 3 + 1
			var ic := indices[tri * 3 + 2] if not indices.is_empty() else tri * 3 + 2
			var a := vertices[ia]
			var b := vertices[ib]
			var c := vertices[ic]
			var middle := (a + b + c) / 3.0
			var outward := middle - center
			var stored := (normals[ia] + normals[ib] + normals[ic]).normalized()
			if stored.dot(outward) < 0.0:
				inward_normals += 1
			# Godot culls counter-clockwise faces: the front-face normal is (c - a) x (b - a).
			var front := (c - a).cross(b - a)
			if front.dot(outward) < 0.0:
				back_facing += 1
		var ok := inward_normals == 0 and back_facing == 0
		failed = failed or not ok
		print("[MeshCheck] %-12s %s  triangles %d, inward normals %d, back-facing %d" % [shape_name, "ok  " if ok else "FAIL", count, inward_normals, back_facing])
	quit(1 if failed else 0)
