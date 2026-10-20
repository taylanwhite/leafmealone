extends RefCounted

## Authority: local, cosmetic, the same on every peer. Fills a zone's sidewalks
## with people out for a walk (npcs/pedestrian.gd). Routes and looks come from
## the seed, and where each walker is comes from the shared clock, so every peer
## builds and moves the same people under the same names, which is how the host's
## bonk messages find them.


## routes: pairs of zone-space points, one sidewalk each. count walkers share them.
static func populate(zone: Node3D, routes: Array, count: int, seed_value: int) -> void:
	var root := Node3D.new()
	root.name = "Pedestrians"
	zone.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index: int in count:
		var route: Array = routes[index % routes.size()]
		var walker: Node3D = preload("res://npcs/pedestrian.gd").new()
		walker.name = "Pedestrian%d" % index
		walker.set("route_from", route[0])
		walker.set("route_to", route[1])
		walker.set("speed", rng.randf_range(1.0, 1.6))
		walker.set("phase", rng.randf_range(0.0, 400.0))
		walker.set("seed_value", seed_value * 100 + index)
		root.add_child(walker)
