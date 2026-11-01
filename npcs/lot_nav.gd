extends RefCounted

## Authority: host. The yard's navigation mesh, baked from the lot's static
## colliders so NPCs (the NICE BOYS, hired hands) path around the house, fences,
## cover, and hide spots of whichever yard is loaded. Baked once per yard; the
## first NPC to need it makes it.

const NAV_NAME := "CrewNav"


## The lot zone's navigation region, baking it if this yard has none yet.
## fresh = true re-bakes even if one exists (a new yard was loaded).
static func ensure(lot_zone: Node3D, fresh: bool = false) -> NavigationRegion3D:
	if lot_zone == null:
		return null
	# The lot zone outlives every yard: a mesh baked for an earlier yard is stale.
	var yard := lot_zone.get_tree().get_first_node_in_group("job_lot")
	var yard_name := String(yard.name) if yard != null else ""
	var old := lot_zone.get_node_or_null(NAV_NAME) as NavigationRegion3D
	if old != null and not fresh and not old.is_queued_for_deletion() and str(old.get_meta("yard", "")) == yard_name:
		return old
	if old != null:
		old.name = NAV_NAME + "_old"
		old.queue_free()
	var mesh := NavigationMesh.new()
	# Whole voxels, so the bake doesn't round them. Cell size matches the default navigation map.
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.agent_radius = 0.5
	mesh.agent_height = 1.75
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	# Only the yard: the street's ground goes on for hundreds of meters.
	var pad: Rect2 = Constants.PAD_RECTS["LotZone"]
	mesh.filter_baking_aabb = AABB(Vector3(pad.position.x - 1.0, -2.0, pad.position.y - 1.0), Vector3(pad.size.x + 2.0, 8.0, pad.size.y + 2.0))
	var source := NavigationMeshSourceGeometryData3D.new()
	# Geometry is gathered relative to the lot zone, so the region sits at the lot zone too.
	NavigationServer3D.parse_source_geometry_data(mesh, source, lot_zone)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	var region := NavigationRegion3D.new()
	region.name = NAV_NAME
	region.add_to_group("lot_nav")
	region.navigation_mesh = mesh
	region.set_meta("yard", yard_name)
	lot_zone.add_child(region)
	return region
