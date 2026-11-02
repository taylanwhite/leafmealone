extends RefCounted

## Authority: local, cosmetic. A batched builder for architecture: boxes,
## prisms, hip roofs, cylinders, windows, and glows, merged into one mesh per
## pattern (and params), every color painted per vertex (paint_per_vertex), so a
## whole house is five to nine draw calls instead of seventy MeshInstance3Ds.
## Painted by the procedural surface shader (props/surfaces.gd, painted());
## glass and glows keep their own materials.
##
## Usage:
##   var kit := HouseKit.new()
##   kit.box(Vector3(8, 3, 6), Vector3(0, 1.5, 0), wall, "siding")
##   kit.prism(Vector3(7.4, 2.3, 9), Vector3(0, 4.15, 0), roof, "shingles", Basis(Vector3.UP, PI * 0.5))
##   var look := kit.commit(house_root, "Look")
##
## Every face is flat-shaded and wound clockwise seen from outside (Godot's
## front face); tools/mesh_check.gd checks it with `audit` (each face against its
## shape's own vertex centroid). Shapes go through `frame`, so a
## part built in its own frame (a porch turned to face a side) can be placed by
## setting kit.frame first. Patterns are measured in the committed mesh's own
## space, which is the holder's (the house root's), so bricks line up across
## neighboring boxes.
##
## style (the last argument of each shape) may hold "params" (Vector4),
## "accent" (Color), and "snow" (0-1, default 1: pass 0 under a roof). Surface
## "glass" puts the shape in the window-glass bucket.

const _Surfaces = preload("res://props/surfaces.gd")

## Window glass: a shiny, slightly see-into-able sky tint (props/low_poly.gd's glass).
const GLASS_COLOR := Color(0.42, 0.58, 0.72)

## One material's geometry.
class Bucket extends RefCounted:
	var kind := "surface"
	var surface := ""
	var color := Color.WHITE
	var accent := Color(0, 0, 0, 0)
	var params := Vector4.ZERO
	var snow := 1.0
	var energy := 1.0
	## Painted per vertex: every color of this pattern shares the bucket.
	var painted := false
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var accents := PackedFloat32Array()

static var _glass: StandardMaterial3D
static var _glows: Dictionary = {}

## tools/mesh_check.gd's independent facing check: while audit is on, every
## shape (box, prism, hip, cylinder, glow) checks each of its triangles against
## the centroid of its own vertices (inside any convex shape), not the inside
## point the shape handed _face, and audit_inward counts the triangles that face
## the centroid. A wrong inside point shows up here; nothing reads it in game.
static var audit := false
static var audit_inward := 0

var _audit_points := PackedVector3Array()
var _audit_tris: Array = []

## Everything after this transform: set it to build a part in its own frame.
var frame := Transform3D.IDENTITY
## Paint per vertex (the default): every color, accent, and snow amount of one
## pattern (and params) goes into one mesh, painted by Surfaces.painted(), so a
## house is about eight draw calls. Off, each color is its own mesh and
## material (Surfaces.material()), for something repainted by swapping its
## material, like a fence panel the paint task refreshes.
var paint_per_vertex := true

## What the shape being added is painted with (set by _bucket, read by _face).
var _paint := Color.WHITE
var _paint_accent := Color.BLACK
var _paint_snow := 1.0

var _buckets: Dictionary = {}
var _bounds := AABB()
var _has_bounds := false
var _vertex_total := 0


## A box of size centered at at, turned by basis.
func box(size: Vector3, at: Vector3, color: Color, surface: String, basis: Basis = Basis.IDENTITY, style: Dictionary = {}) -> void:
	var half := size * 0.5
	var corners: Array[Vector3] = []
	for index: int in 8:
		var sign_x := 1.0 if index & 1 else -1.0
		var sign_y := 1.0 if index & 2 else -1.0
		var sign_z := 1.0 if index & 4 else -1.0
		corners.append(frame * (at + basis * Vector3(half.x * sign_x, half.y * sign_y, half.z * sign_z)))
	var center := frame * at
	var bucket := _bucket(surface, color, style)
	for face: Array in [[1, 3, 7, 5], [0, 4, 6, 2], [2, 6, 7, 3], [0, 1, 5, 4], [4, 5, 7, 6], [0, 2, 3, 1]]:
		_face(bucket, [corners[face[0]], corners[face[1]], corners[face[2]], corners[face[3]]], center)
	_audit_shape()


## A triangular prism like PrismMesh: size.x across the base, size.y tall,
## size.z long, centered at at, the ridge along local z (turn it with basis).
func prism(size: Vector3, at: Vector3, color: Color, surface: String, basis: Basis = Basis.IDENTITY, style: Dictionary = {}) -> void:
	var w := size.x * 0.5
	var h := size.y * 0.5
	var l := size.z * 0.5
	var local: Array[Vector3] = [
		Vector3(-w, -h, -l), Vector3(w, -h, -l), Vector3(0.0, h, -l),
		Vector3(-w, -h, l), Vector3(w, -h, l), Vector3(0.0, h, l),
	]
	var p: Array[Vector3] = []
	for point: Vector3 in local:
		p.append(frame * (at + basis * point))
	var center := frame * (at + basis * Vector3(0.0, -h / 3.0, 0.0))
	var bucket := _bucket(surface, color, style)
	_face(bucket, [p[0], p[1], p[2]], center)
	_face(bucket, [p[3], p[4], p[5]], center)
	_face(bucket, [p[0], p[2], p[5], p[3]], center)
	_face(bucket, [p[1], p[4], p[5], p[2]], center)
	_face(bucket, [p[0], p[3], p[4], p[1]], center)
	_audit_shape()


## A hip roof: a size.x by size.z base with its bottom at at, sloping up on all
## four sides to a ridge rise above it along the longer side (a pyramid when
## square). style "basis" turns it.
func hip(size: Vector3, at: Vector3, rise: float, color: Color, surface: String, style: Dictionary = {}) -> void:
	var basis: Basis = style.get("basis", Basis.IDENTITY)
	var sx := size.x
	var sz := size.z
	if sz > sx:
		basis = basis * Basis(Vector3.UP, PI * 0.5)
		sx = size.z
		sz = size.x
	var ridge := (sx - sz) * 0.5
	var local: Array[Vector3] = [
		Vector3(-sx * 0.5, 0.0, -sz * 0.5), Vector3(sx * 0.5, 0.0, -sz * 0.5),
		Vector3(sx * 0.5, 0.0, sz * 0.5), Vector3(-sx * 0.5, 0.0, sz * 0.5),
		Vector3(-ridge, rise, 0.0), Vector3(ridge, rise, 0.0),
	]
	var p: Array[Vector3] = []
	for point: Vector3 in local:
		p.append(frame * (at + basis * point))
	var center := frame * (at + basis * Vector3(0.0, rise * 0.25, 0.0))
	var bucket := _bucket(surface, color, style)
	_face(bucket, [p[3], p[2], p[5], p[4]], center)
	_face(bucket, [p[0], p[4], p[5], p[1]], center)
	_face(bucket, [p[0], p[3], p[4]], center)
	_face(bucket, [p[1], p[5], p[2]], center)
	_face(bucket, [p[0], p[1], p[2], p[3]], center)
	_audit_shape()


## A cylinder (or a frustum, with style "top_radius"; a cone at 0) of height
## centered at at, upright, with sides flat facets. style "turn" spins the facets
## (radians): four sides turned PI/4 is a square post.
func cylinder(radius: float, height: float, at: Vector3, color: Color, surface: String, sides: int = 8, style: Dictionary = {}) -> void:
	sides = maxi(sides, 3)
	var top_radius := float(style.get("top_radius", radius))
	var turn := float(style.get("turn", 0.0))
	var basis: Basis = style.get("basis", Basis.IDENTITY)
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for step: int in sides:
		var angle := turn + TAU * float(step) / float(sides)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		bottom.append(frame * (at + basis * (out * radius + Vector3(0.0, -height * 0.5, 0.0))))
		top.append(frame * (at + basis * (out * top_radius + Vector3(0.0, height * 0.5, 0.0))))
	var center := frame * at
	var bucket := _bucket(surface, color, style)
	for step: int in sides:
		var next := (step + 1) % sides
		_face(bucket, [bottom[step], bottom[next], top[next], top[step]], center)
	_face(bucket, bottom, center)
	if top_radius > 0.001:
		_face(bucket, top, center)
	_audit_shape()


## A window set into a wall that faces +Z when yaw is 0, centered on the wall's
## surface at at: glass, a painted frame, a crossbar, and a sill (props/low_poly.gd
## window(), batched). style: "mullions" (default true), "sill" (default true),
## "far" (glass only).
func window(width: float, height: float, at: Vector3, frame_color: Color, yaw: float = 0.0, style: Dictionary = {}) -> void:
	var saved := frame
	frame = frame * Transform3D(Basis(Vector3.UP, yaw), at)
	box(Vector3(width, height, 0.04), Vector3(0.0, 0.0, 0.02), GLASS_COLOR, "glass")
	if bool(style.get("far", false)):
		frame = saved
		return
	var bar := 0.09
	for side: float in [-1.0, 1.0]:
		box(Vector3(bar, height + bar * 2.0, 0.1), Vector3(side * (width * 0.5 + bar * 0.5), 0.0, 0.05), frame_color, "planks")
		box(Vector3(width + bar * 2.0, bar, 0.1), Vector3(0.0, side * (height * 0.5 + bar * 0.5), 0.05), frame_color, "planks")
	if bool(style.get("mullions", true)):
		box(Vector3(0.05, height, 0.07), Vector3(0.0, 0.0, 0.05), frame_color, "planks")
		box(Vector3(width, 0.05, 0.07), Vector3(0.0, 0.0, 0.05), frame_color, "planks")
	if bool(style.get("sill", true)):
		box(Vector3(width + 0.35, 0.08, 0.22), Vector3(0.0, -height * 0.5 - bar - 0.03, 0.11), frame_color.darkened(0.1), "planks")
	frame = saved


## Something that glows, like a lamp or a lit window. Kept out of the shared look.
func glow(size: Vector3, at: Vector3, color: Color, energy: float = 1.5) -> void:
	var key := "glow|%s|%s" % [color.to_html(), energy]
	if not _buckets.has(key):
		var made := Bucket.new()
		made.kind = "glow"
		made.color = color
		made.energy = energy
		_buckets[key] = made
	var saved: Bucket = _buckets[key]
	var half := size * 0.5
	var corners: Array[Vector3] = []
	for index: int in 8:
		corners.append(frame * (at + Vector3(half.x * (1.0 if index & 1 else -1.0), half.y * (1.0 if index & 2 else -1.0), half.z * (1.0 if index & 4 else -1.0))))
	for face: Array in [[1, 3, 7, 5], [0, 4, 6, 2], [2, 6, 7, 3], [0, 1, 5, 4], [4, 5, 7, 6], [0, 2, 3, 1]]:
		_face(saved, [corners[face[0]], corners[face[1]], corners[face[2]], corners[face[3]]], frame * at)
	_audit_shape()


func vertex_count() -> int:
	return _vertex_total


func triangle_count() -> int:
	return _vertex_total / 3


## How many meshes commit() will make: one draw call each.
func bucket_count() -> int:
	var count := 0
	for key: String in _buckets:
		if not (_buckets[key] as Bucket).vertices.is_empty():
			count += 1
	return count


## Everything built so far, in the holder's space.
func bounds() -> AABB:
	return _bounds if _has_bounds else AABB()


## The finished look: a Node3D called name under parent, with one MeshInstance3D
## per material. Meshes carry the surface metas levels/shared_look.gd reads
## (surface, surface_base, surface_params, surface_accent, surface_snow); glass
## joins group "window_glass" (for a future night glow). The holder's meta
## "triangles" is the triangle count, "draw_calls" the mesh count.
func commit(parent: Node3D, name: String) -> Node3D:
	var holder := Node3D.new()
	holder.name = name
	parent.add_child(holder)
	var made := 0
	for key: String in _buckets:
		var bucket: Bucket = _buckets[key]
		var vertices := bucket.vertices
		if vertices.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = bucket.normals
		var flags := 0
		if bucket.painted:
			arrays[Mesh.ARRAY_COLOR] = bucket.colors
			arrays[Mesh.ARRAY_CUSTOM0] = bucket.accents
			flags = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		var view := MeshInstance3D.new()
		view.mesh = mesh
		view.set_meta("triangles", vertices.size() / 3)
		match bucket.kind:
			"glass":
				view.name = "Glass"
				view.material_override = _glass_material()
				view.set_meta("keep_material", true)
				view.add_to_group("window_glass")
			"glow":
				view.name = "Glow%d" % made
				view.material_override = _glow_material(bucket.color, bucket.energy)
				view.set_meta("keep_material", true)
			_:
				view.name = "%s%d" % [bucket.surface.capitalize().replace(" ", ""), made]
				view.set_meta("surface", bucket.surface)
				view.set_meta("surface_base", bucket.color)
				view.set_meta("surface_params", bucket.params)
				view.set_meta("surface_accent", bucket.accent)
				view.set_meta("surface_snow", bucket.snow)
				if bucket.painted:
					# Colors live in the vertices: levels/shared_look.gd must not repaint it flat.
					view.set_meta("surface_painted", true)
					view.set_meta("keep_material", true)
					view.material_override = _Surfaces.painted(bucket.surface, bucket.params)
				else:
					view.material_override = _Surfaces.material(bucket.surface, bucket.color, bucket.accent, bucket.params, bucket.snow)
		holder.add_child(view)
		made += 1
	holder.set_meta("triangles", triangle_count())
	holder.set_meta("draw_calls", made)
	return holder


## Every triangle in one surface, for tools/mesh_check.gd.
func commit_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for key: String in _buckets:
		vertices.append_array((_buckets[key] as Bucket).vertices)
		normals.append_array((_buckets[key] as Bucket).normals)
	if vertices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _bucket(surface: String, color: Color, style: Dictionary) -> Bucket:
	if surface == "glass":
		if not _buckets.has("glass"):
			var glass := Bucket.new()
			glass.kind = "glass"
			_buckets["glass"] = glass
		return _buckets["glass"]
	var params: Vector4 = style.get("params", Vector4.ZERO)
	var accent: Color = style.get("accent", Color(0, 0, 0, 0))
	var snow := clampf(float(style.get("snow", 1.0)), 0.0, 1.0)
	_paint = color
	_paint_accent = _Surfaces.accent_for(surface, color, accent)
	_paint_snow = snow
	var key := "%s|%s" % [surface, params] if paint_per_vertex else "%s|%s|%s|%s|%s" % [surface, color.to_html(), accent.to_html(), params, snow]
	if not _buckets.has(key):
		var made := Bucket.new()
		made.surface = surface
		made.color = color
		made.accent = accent
		made.params = params
		made.snow = snow
		made.painted = paint_per_vertex
		_buckets[key] = made
	return _buckets[key]


## One flat convex face, fanned into triangles that face away from inside (a
## point inside the shape), clockwise seen from outside.
func _face(bucket: Bucket, points: Array, inside: Vector3) -> void:
	var middle := Vector3.ZERO
	for point: Vector3 in points:
		middle += point
	middle /= float(points.size())
	var outward := middle - inside
	for index: int in range(1, points.size() - 1):
		var a: Vector3 = points[0]
		var b: Vector3 = points[index]
		var c: Vector3 = points[index + 1]
		# Godot's front face is clockwise: its normal is (c - a) x (b - a).
		var normal := (c - a).cross(b - a)
		if normal.length_squared() < 1e-10:
			continue
		if normal.dot(outward) < 0.0:
			var swap := b
			b = c
			c = swap
			normal = -normal
		normal = normal.normalized()
		for corner: Vector3 in [a, b, c]:
			bucket.vertices.append(corner)
			bucket.normals.append(normal)
			if bucket.painted:
				bucket.colors.append(Color(_paint.r, _paint.g, _paint.b, _paint_snow))
				bucket.accents.append_array([_paint_accent.r, _paint_accent.g, _paint_accent.b, 1.0])
			_grow(corner)
		_vertex_total += 3
		if audit:
			_audit_tris.append([(a + b + c) / 3.0, normal])
	if audit:
		for point: Vector3 in points:
			_audit_points.append(point)


## Ends one shape for the audit: counts its triangles that face its own centroid.
func _audit_shape() -> void:
	if not audit or _audit_points.is_empty():
		_audit_points.clear()
		_audit_tris.clear()
		return
	var centroid := Vector3.ZERO
	for point: Vector3 in _audit_points:
		centroid += point
	centroid /= float(_audit_points.size())
	for tri: Array in _audit_tris:
		if (tri[1] as Vector3).dot((tri[0] as Vector3) - centroid) <= 0.0:
			audit_inward += 1
	_audit_points.clear()
	_audit_tris.clear()


func _grow(point: Vector3) -> void:
	if not _has_bounds:
		_bounds = AABB(point, Vector3.ZERO)
		_has_bounds = true
	else:
		_bounds = _bounds.expand(point)


static func _glass_material() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.albedo_color = GLASS_COLOR
		_glass.metallic = 0.4
		_glass.roughness = 0.08
		_glass.metallic_specular = 0.9
	return _glass


static func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var key := "%s|%s" % [color.to_html(), energy]
	if not _glows.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = energy
		_glows[key] = material
	return _glows[key]
