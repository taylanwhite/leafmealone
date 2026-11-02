extends RefCounted

## Authority: local, cosmetic. Draws many copies of the catalog's simple props
## (props/prop_catalog.gd SIMPLE) as MultiMeshes: one MultiMeshInstance3D per
## square chunk of the ground (Constants.ART_PROP_CHUNK, 32 m) and per mesh
## (kind, color, size), so a whole street block of flamingos, bins, mailboxes and
## fence runs costs a few dozen draw calls and still gets culled chunk by chunk.
##
##   var batch := PropBatch.new(block_root)
##   batch.add("flamingo", Transform3D(Basis(Vector3.UP, 0.4), Vector3(3, 0, 8)))
##   batch.add("privacy_fence_run", run_xform, Color.WHITE, Vector3(12, 1.8, 0))
##   var placed := batch.commit()   # instances committed
##
## Transforms are in root's space. Each MultiMeshInstance3D sits at its
## chunk's center (so its visibility range is measured from there), fades like
## PropCatalog.node() (small props at ART_SMALL_PROP_RANGE with no shadow,
## the rest at ART_MEDIUM_PROP_RANGE), and carries metas prop_kind and
## prop_instances (and instance_xforms, each instance's transform in the view's
## space, for headless checks); signature kinds join their "art_signature:<id>" group.
## hash() is a stable digest of everything added, in order, for the art hash.
## Nothing here is networked; every peer adds the same props in the same order.

const _Catalog = preload("res://props/prop_catalog.gd")
const _Stylized = preload("res://props/stylized.gd")

var _root: Node3D
var _chunk := 32.0
## Pending groups by key (chunk, kind, color, size), in the order first added.
var _groups: Dictionary = {}
var _order: Array[String] = []
var _count := 0
var _digest := 0
var _views: Array[MultiMeshInstance3D] = []


func _init(root: Node3D, chunk: float = Constants.ART_PROP_CHUNK) -> void:
	_root = root
	_chunk = maxf(chunk, 1.0)


## Queues one prop at xform (root space). Only SIMPLE kinds batch; anything
## else is refused with an error (use PropCatalog.place()).
func add(kind: String, xform: Transform3D, color: Color = Color.WHITE, size: Vector3 = Vector3.ONE) -> void:
	if not _Catalog.is_simple(kind):
		push_error("[PropBatch] %s can't be batched; use PropCatalog.place()" % kind)
		return
	var used := size.snapped(Vector3(0.1, 0.1, 0.1)) if _Catalog.is_sized(kind) else Vector3.ONE
	var cell := Vector2i(floori(xform.origin.x / _chunk), floori(xform.origin.z / _chunk))
	var key := "%d|%d|%s|%s|%s" % [cell.x, cell.y, kind, color.to_html(), used]
	if not _groups.has(key):
		_groups[key] = {"kind": kind, "color": color, "size": used, "cell": cell, "xforms": []}
		_order.append(key)
	(_groups[key]["xforms"] as Array).append(xform)
	var snap := Vector3(0.01, 0.01, 0.01)
	_digest = [_digest, kind, color.to_html(), used, xform.origin.snapped(snap), xform.basis.x.snapped(snap), xform.basis.y.snapped(snap), xform.basis.z.snapped(snap)].hash()
	_count += 1


## Builds a MultiMeshInstance3D for every pending group under root and returns
## how many instances it committed. Safe to call again after more add()s.
func commit() -> int:
	var placed := 0
	for key: String in _order:
		var group: Dictionary = _groups[key]
		var kind: String = group["kind"]
		var xforms: Array = group["xforms"]
		var cell: Vector2i = group["cell"]
		var mesh := _Catalog.mesh(kind, group["color"], group["size"])
		var center := Vector3((float(cell.x) + 0.5) * _chunk, 0.0, (float(cell.y) + 0.5) * _chunk)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = false
		multimesh.mesh = mesh
		multimesh.instance_count = xforms.size()
		# Kept on the node too: a headless (dummy) renderer forgets MultiMesh data,
		# and the art checks read where each instance stands.
		var local: Array[Transform3D] = []
		for index: int in xforms.size():
			var xform: Transform3D = xforms[index]
			local.append(Transform3D(xform.basis, xform.origin - center))
			multimesh.set_instance_transform(index, local[index])
		var view := MultiMeshInstance3D.new()
		view.name = "%s_%d_%d" % [kind.to_pascal_case(), cell.x, cell.y]
		view.multimesh = multimesh
		view.position = center
		view.material_override = _Stylized.material(_Catalog.options(kind))
		view.set_meta("keep_material", true)
		view.set_meta("prop_kind", kind)
		view.set_meta("prop_instances", xforms.size())
		view.set_meta("instance_xforms", local)
		view.set_meta("triangles", int(mesh.get_meta("triangles", 0)) * xforms.size())
		_Catalog.fade(view, mesh.get_meta("aabb", mesh.get_aabb()))
		_Catalog.tag(view, kind)
		_root.add_child(view)
		_views.append(view)
		placed += xforms.size()
	_groups.clear()
	_order.clear()
	return placed


## Every instance added so far (committed or not).
func instance_count() -> int:
	return _count


## The MultiMeshInstance3Ds committed so far.
func views() -> Array[MultiMeshInstance3D]:
	return _views


## A stable digest of every add() so far: kind, color, size and transform, in order.
func hash() -> int:
	return _digest
