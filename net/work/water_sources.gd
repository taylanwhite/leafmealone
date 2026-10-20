extends RefCounted

## Authority: none; every peer has the same sources. Places to hook a hose up or
## refill a pressure washer (Constants.WATER_SPEED): Chefty's tank (free), the
## house's spigot (the homeowner bills you), and the fire hydrant on the sidewalk
## (way too much pressure). Each is a Node3D in the "water_sources" group with
## meta "kind", placed by props/vehicles.gd and levels/lots/lot_generator.gd at
## the point the hose hooks onto.


static func make(parent: Node3D, kind: String, at: Vector3) -> Node3D:
	var marker := Node3D.new()
	marker.name = "WaterSource_%s" % kind
	marker.set_meta("kind", kind)
	marker.add_to_group("water_sources")
	parent.add_child(marker)
	marker.position = at
	return marker


static func find(tree: SceneTree, kind: String) -> Node3D:
	for node: Node in tree.get_nodes_in_group("water_sources"):
		if str(node.get_meta("kind", "")) == kind and node.is_inside_tree():
			return node as Node3D
	return null


## The closest source within reach of a point, or null.
static func nearest(tree: SceneTree, at: Vector3, within: float) -> Node3D:
	var best: Node3D = null
	var best_distance := within
	for node: Node in tree.get_nodes_in_group("water_sources"):
		var source := node as Node3D
		if source == null or not source.is_inside_tree():
			continue
		var distance := source.global_position.distance_to(at)
		if distance < best_distance:
			best = source
			best_distance = distance
	return best
