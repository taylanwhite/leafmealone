class_name LeafLitter
extends RefCounted

## Authority: local, cosmetic. The leaf skin's meshes: one flat grid per field
## chunk, 0.25 m between vertices (33 x 33 vertices, 2,048 triangles), lifted
## and painted by leaves/leaf_shaders.gd LITTER_SHADER from the height and cover
## maps. Built once per field. The skin casts the leaves' shadows (hero leaves
## don't), so piles throw real shadows and give the outline pass a silhouette.

const SPACING: float = 0.25
## How high the skin can rise above its grid, for culling (a full pile is ~0.8 m).
const AABB_HEIGHT: float = 1.0

static var _grids: Dictionary = {}


## The flat grid for a chunk size x size meters, shared by every chunk that size.
static func grid(size: Vector2) -> ArrayMesh:
	var key := "%.3f|%.3f" % [size.x, size.y]
	if _grids.has(key):
		return _grids[key]
	var columns := maxi(1, int(round(size.x / SPACING)))
	var rows := maxi(1, int(round(size.y / SPACING)))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for z: int in rows + 1:
		for x: int in columns + 1:
			vertices.append(Vector3(float(x) * size.x / float(columns), 0.0, float(z) * size.y / float(rows)))
			normals.append(Vector3.UP)
	for z: int in rows:
		for x: int in columns:
			var a := x + z * (columns + 1)
			var b := a + 1
			var c := a + columns + 1
			var d := c + 1
			# Clockwise seen from above (Godot's front face).
			indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(0.0, -0.05, 0.0), Vector3(size.x, AABB_HEIGHT + 0.05, size.y))
	mesh.set_meta("triangles", indices.size() / 3)
	_grids[key] = mesh
	return mesh


## One chunk's skin: a MeshInstance3D at corner (the renderer's local space).
static func chunk(corner: Vector3, size: Vector2, material: Material) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.name = "Litter"
	view.mesh = grid(size)
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# levels/shared_look.gd paints plain meshes; this one keeps its own material.
	view.set_meta("keep_material", true)
	view.position = corner
	return view
