extends SceneTree

## Checks that every mesh-kit and house-kit shape faces the right way, and that
## every house archetype keeps its contract. Run headless:
##   godot --headless --path . --script res://tools/mesh_check.gd
## For each shape it builds one closed mesh around the origin and checks, per
## triangle, that the stored normal points away from the center (lit from the
## outside) and that the winding is Godot's front face (clockwise seen from the
## front), so back-face culling never shows the inside. Then it builds every
## archetype (levels/town/house_archetypes.gd) at the smallest and largest yard
## house widths, one and two stories, full and far detail, two seeds, with
## HouseKit's audit on (each face checked against its own shape's vertex
## centroid, independent of the inside point the kit oriented it by; a
## deliberately wrong box proves the audit can fail), and checks the footprint
## contract, the HouseSpec metas, gutter and eave clearance, and the triangle
## budget (levels/town/house_builder.gd check()); and
## that every neighborhood style (levels/town/hood_styles.gd) only names
## archetypes that exist, none of them neighbors-only for a job house; and every
## tree (props/trees.gd) kind x crown x variant x season, near and far, against
## its triangle budget and the season rules, plus a spawned tree's LOD wiring.
## Exits 1 on any failure.

const _MeshKit: Script = preload("res://props/mesh_kit.gd")
const _HouseKit: Script = preload("res://props/house_kit.gd")
const _HouseBuilder = preload("res://levels/town/house_builder.gd")
const _Archetypes = preload("res://levels/town/house_archetypes.gd")
const _HoodStyles = preload("res://levels/town/hood_styles.gd")


func _init() -> void:
	var shapes := {
		"blob": func(kit: RefCounted) -> void: kit.call("blob", Vector3.ZERO, Vector3(1.0, 0.8, 1.2), Color.WHITE, {"seed": 3}),
		"blob_smooth": func(kit: RefCounted) -> void: kit.call("blob", Vector3.ZERO, Vector3.ONE, Color.WHITE, {"flat": false, "detail": 2}),
		"rbox": func(kit: RefCounted) -> void: kit.call("rbox", Vector3.ZERO, Vector3(1.0, 0.5, 0.7), Color.WHITE, 5.0),
		"box": func(kit: RefCounted) -> void: kit.call("box", Vector3.ZERO, Vector3(1.0, 2.0, 0.5), Color.WHITE),
		"cone": func(kit: RefCounted) -> void: kit.call("cone", Vector3(0.0, -1.0, 0.0), 1.0, 2.0, Color.WHITE),
		"tube": func(kit: RefCounted) -> void: kit.call("tube", PackedVector3Array([Vector3(0, -1, 0), Vector3(0, 0, 0), Vector3(0, 1, 0)]), PackedFloat32Array([0.4, 0.4, 0.4]), Color.WHITE),
	}
	var house_shapes := {
		"hk_box": func(kit: RefCounted) -> void: kit.call("box", Vector3(2.0, 1.0, 3.0), Vector3.ZERO, Color.WHITE, "siding", Basis(Vector3(0.3, 1.0, 0.2).normalized(), 0.7)),
		"hk_prism": func(kit: RefCounted) -> void: kit.call("prism", Vector3(3.0, 1.5, 4.0), Vector3.ZERO, Color.WHITE, "shingles", Basis(Vector3.UP, PI * 0.5)),
		"hk_hip": func(kit: RefCounted) -> void: kit.call("hip", Vector3(4.0, 0.0, 2.5), Vector3(0.0, -0.4, 0.0), 1.2, Color.WHITE, "roof_tiles"),
		"hk_hip_deep": func(kit: RefCounted) -> void: kit.call("hip", Vector3(2.0, 0.0, 5.0), Vector3(0.0, -0.4, 0.0), 1.0, Color.WHITE, "roof_tiles"),
		"hk_pyramid": func(kit: RefCounted) -> void: kit.call("hip", Vector3(3.0, 0.0, 3.0), Vector3(0.0, -0.4, 0.0), 1.5, Color.WHITE, "roof_tiles"),
		"hk_cylinder": func(kit: RefCounted) -> void: kit.call("cylinder", 0.5, 2.0, Vector3.ZERO, Color.WHITE, "stucco", 12),
		"hk_frustum": func(kit: RefCounted) -> void: kit.call("cylinder", 0.5, 2.0, Vector3.ZERO, Color.WHITE, "planks", 4, {"top_radius": 0.3, "turn": PI * 0.25}),
		"hk_cone": func(kit: RefCounted) -> void: kit.call("cylinder", 0.5, 1.0, Vector3.ZERO, Color.WHITE, "plain", 8, {"top_radius": 0.0}),
		"hk_framed": func(kit: RefCounted) -> void:
			kit.set("frame", Transform3D(Basis(Vector3.UP, 1.1), Vector3(3.0, 1.0, -2.0)))
			kit.call("box", Vector3(1.0, 1.0, 1.0), Vector3(0.5, 0.0, 0.0), Color.WHITE, "brick", Basis(Vector3.RIGHT, 0.4))
			kit.set("frame", Transform3D.IDENTITY),
	}
	var failed := false
	for shape_name: String in shapes:
		var kit: RefCounted = _MeshKit.new()
		(shapes[shape_name] as Callable).call(kit)
		failed = not _check_closed(shape_name, kit.call("commit")) or failed
	for shape_name: String in house_shapes:
		var kit: RefCounted = _HouseKit.new()
		(house_shapes[shape_name] as Callable).call(kit)
		failed = not _check_closed(shape_name, kit.call("commit_mesh")) or failed
	_HouseKit.set("audit", true)
	failed = not _check_audit() or failed
	failed = not _check_houses() or failed
	_HouseKit.set("audit", false)
	failed = not _check_styles() or failed
	failed = not _check_trees() or failed
	quit(1 if failed else 0)


## Every tree kind x crown x variant (negative ones too) x season (props/trees.gd): the near
## mesh within Constants.ART_TREE_MAX_TRIANGLES and the far one within
## ART_TREE_FAR_MAX_TRIANGLES (and cheaper than the near one); the season rules
## (broadleaf kinds bare in winter, evergreens never bare, spring blossoms, summer
## greens, autumn as asked); and a spawned tree's LOD wiring and season swap.
func _check_trees() -> bool:
	var ok := true
	var trees: Script = preload("res://props/trees.gd")
	var kinds: Array = trees.get("KINDS")
	var evergreen: Array = trees.get("EVERGREEN")
	var crowns: Array = (trees.get("CROWNS") as Dictionary).keys()
	for kind: String in kinds:
		var most := 0
		var most_far := 0
		var problems := PackedStringArray()
		var forms := {}
		# Evergreens ignore the crown's colors, but the crown is part of their seed
		# (countryside.gd hands pines random autumn crowns), so every one is a shape.
		var kind_crowns: Array = [""] + crowns if evergreen.has(kind) else crowns
		var variants: int = trees.get("VARIANTS")
		for crown: String in kind_crowns:
			# Callers pass negative variants too (store and town dressing), and
			# variant % VARIANTS keeps the sign: -3..-1 are shapes of their own.
			for variant: int in range(1 - variants, variants):
				for season: int in 4:
					var near: ArrayMesh = trees.call("mesh_for", kind, crown, variant, season)
					var far: ArrayMesh = trees.call("mesh_for", kind, crown, variant, season, true)
					var near_triangles := int(near.get_meta("triangles", -1))
					var far_triangles := int(far.get_meta("triangles", -1))
					var form: Array = trees.call("seasonal_form", kind, crown, season)
					forms[form[2]] = true
					most = maxi(most, near_triangles)
					most_far = maxi(most_far, far_triangles)
					var label := "%s %s v%d s%d" % [kind, crown, variant, season]
					if near_triangles <= 0 or near_triangles > Constants.ART_TREE_MAX_TRIANGLES:
						problems.append("%s near %d triangles" % [label, near_triangles])
					if far_triangles <= 0 or far_triangles > Constants.ART_TREE_FAR_MAX_TRIANGLES or far_triangles >= near_triangles:
						problems.append("%s far %d triangles (near %d)" % [label, far_triangles, near_triangles])
					problems.append_array(_tree_rule(trees, kind, crown, season, form))
					for mesh: ArrayMesh in [near, far]:
						var bad := _bad_vertices(mesh)
						if bad > 0:
							problems.append("%s %d vertices with a zero or non-finite normal or position" % [label, bad])
		var good := problems.is_empty()
		ok = ok and good
		print("[MeshCheck] tree %-10s %s  up to %d triangles near, %d far, forms %s" % [kind, "ok  " if good else "FAIL", most, most_far, ",".join(PackedStringArray(forms.keys()))])
		for problem: String in problems.slice(0, 8):
			print("[MeshCheck]   %s" % problem)
	ok = _check_tree_node(trees) and ok
	return ok


## Vertices a shader would turn into NaN (a zero normal normalizes to NaN on the
## GPU, and glow smears one NaN pixel into a white blob), or positions that are
## not finite.
func _bad_vertices(mesh: ArrayMesh) -> int:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var bad := 0
	for index: int in vertices.size():
		var color := colors[index]
		var color_ok := is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a) and minf(minf(color.r, color.g), color.b) >= 0.0
		if not vertices[index].is_finite() or not normals[index].is_finite() or normals[index].length() < 0.5 or not color_ok:
			bad += 1
	return bad


## The exact season mapping (docs/GAME.md, "trees through the year"), written out
## here on its own so a swapped or loosened rule in trees.gd fails.
func _tree_rule(trees: Script, kind: String, crown: String, season: int, form: Array) -> PackedStringArray:
	var problems := PackedStringArray()
	var evergreen: bool = (trees.get("EVERGREEN") as Array).has(kind)
	var want_crown := crown
	var want_form := "full"
	match season:
		1:
			want_form = "snowy" if evergreen else "bare"
		2:
			if not evergreen:
				# Only broadleaves blossom: red ones pink, yellow ones white.
				want_crown = "spring_green"
				if kind == "broadleaf" and crown == "red":
					want_crown = "blossom_pink"
				elif kind == "broadleaf" and crown == "yellow":
					want_crown = "blossom_white"
		3:
			if not evergreen:
				want_crown = "deep_green" if ["red", "rust", "orange"].has(crown) else "green"
	if str(form[0]) != kind or str(form[1]) != want_crown or str(form[2]) != want_form:
		problems.append("%s %s season %d -> %s, want [%s, %s, %s]" % [kind, crown, season, str(form), kind, want_crown, want_form])
	# (A blossom crown asked for outright is shown as asked; the seasons never give one.)
	if (kind == "birch" or kind == "willow") and str(form[1]).begins_with("blossom") and str(form[1]) != crown:
		problems.append("%s %s season %d: birches and willows never blossom" % [kind, crown, season])
	return problems


## A spawned tree: a "seasonal" root with metas, Look depending on LookFar, the
## far mesh from ART_TREE_LOD_DISTANCE out, and apply_season swapping both meshes.
func _check_tree_node(trees: Script) -> bool:
	var problems := PackedStringArray()
	var holder := Node3D.new()
	var tree: Node3D = trees.call("spawn", holder, Vector3.ZERO, 9.0, "broadleaf", "red", 2, true)
	var look := tree.get_node_or_null("Look") as MeshInstance3D
	var far := tree.get_node_or_null("LookFar") as MeshInstance3D
	if look == null or far == null:
		problems.append("no Look or LookFar")
	else:
		if not is_equal_approx(far.visibility_range_begin, Constants.ART_TREE_LOD_DISTANCE) or far.visibility_range_begin_margin <= 0.0:
			problems.append("LookFar range %.1f margin %.1f" % [far.visibility_range_begin, far.visibility_range_begin_margin])
		if look.visibility_parent != NodePath("../LookFar") or look.visibility_range_end != 0.0:
			problems.append("Look must depend on LookFar only (%s, end %.1f)" % [look.visibility_parent, look.visibility_range_end])
		if str(tree.get_meta("form", "")) != "full" or str(tree.get_meta("crown", "")) != "red":
			problems.append("autumn metas %s %s" % [tree.get_meta("form", ""), tree.get_meta("crown", "")])
		var autumn_mesh := look.mesh
		tree.call("apply_season", 1)
		if str(tree.get_meta("form", "")) != "bare" or look.mesh == autumn_mesh or look.mesh != trees.call("mesh_for", "broadleaf", "red", 2, 1) or far.mesh != trees.call("mesh_for", "broadleaf", "red", 2, 1, true):
			problems.append("winter swap: form %s" % tree.get_meta("form", ""))
		tree.call("apply_season", 2)
		if str(tree.get_meta("crown", "")) != "blossom_pink":
			problems.append("spring swap: crown %s" % tree.get_meta("crown", ""))
		tree.call("apply_season", 0)
		if look.mesh != autumn_mesh:
			problems.append("back to autumn: a different mesh")
	if tree.find_children("*", "StaticBody3D", true, false).size() != 1:
		problems.append("solid tree without its trunk collider")
	# Prewarm: the day before a turn a tree builds the next season into the cache
	# (one frame's budget always fits one tree), so the turn itself builds nothing.
	trees.set("_cache", {})
	var warm: Node3D = trees.call("spawn", holder, Vector3(20.0, 0.0, 0.0), 7.0, "willow", "orange", -2)
	var built := (trees.get("_cache") as Dictionary).size()
	warm.call("prewarm_season", 3)
	warm.call("_process", 0.0)
	var warmed := (trees.get("_cache") as Dictionary).size()
	if warmed != built + 1 or warm.is_processing():
		problems.append("prewarm built %d meshes (want 1), still processing %s" % [warmed - built, warm.is_processing()])
	warm.call("apply_season", 3)
	if (trees.get("_cache") as Dictionary).size() != warmed or str(warm.get_meta("crown", "")) != "deep_green":
		problems.append("the summer turn after a prewarm built again or wore %s" % warm.get_meta("crown", ""))
	holder.free()
	print("[MeshCheck] tree node    %s  LOD at %.0f m, season swap, prewarm" % ["ok  " if problems.is_empty() else "FAIL", Constants.ART_TREE_LOD_DISTANCE])
	for problem: String in problems:
		print("[MeshCheck]   %s" % problem)
	return problems.is_empty()


## A closed convex-ish shape: every normal points away from its center, and every
## triangle's winding agrees.
func _check_closed(shape_name: String, mesh: ArrayMesh) -> bool:
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
	var ok := inward_normals == 0 and back_facing == 0 and count > 0
	print("[MeshCheck] %-12s %s  triangles %d, inward normals %d, back-facing %d" % [shape_name, "ok  " if ok else "FAIL", count, inward_normals, back_facing])
	return ok


## Every archetype at the yard's smallest and largest house widths.
func _check_houses() -> bool:
	var ok := true
	var holder := Node3D.new()
	var widths: Array = Constants.YARD_HOUSE_WIDTH
	var smallest := (widths[0] as Vector2).x
	var largest := (widths[widths.size() - 1] as Vector2).y
	for archetype: String in _Archetypes.ALL:
		var most := 0
		var calls := 0
		var problems := PackedStringArray()
		var inward := 0
		for size: Vector2 in [Vector2(smallest, 6.5), Vector2(largest, 10.0)]:
			for stories: int in [1, 2]:
				for detail: String in ["full", "far"]:
					for house_seed: int in [7, 8]:
						_HouseKit.set("audit_inward", 0)
						var house := _HouseBuilder.build(holder, Vector3.ZERO, {"archetype": archetype, "width": size.x, "depth": size.y, "stories": stories, "seed": house_seed, "detail": detail, "garage": true})
						inward += int(_HouseKit.get("audit_inward"))
						if detail == "full":
							problems.append_array(_HouseBuilder.check(house))
							most = maxi(most, int(house.get_meta("triangles", 0)))
							calls = maxi(calls, int(house.get_meta("draw_calls", 0)))
						holder.remove_child(house)
						house.free()
		var good := problems.is_empty() and inward == 0
		ok = ok and good
		print("[MeshCheck] house %-13s %s  up to %d triangles, %d draw calls, %d inward faces" % [archetype, "ok  " if good else "FAIL", most, calls, inward])
		for problem: String in problems:
			print("[MeshCheck]   %s" % problem)
	holder.free()
	return ok


## The audit itself can fail: a box whose faces were oriented from a point
## outside it must count inward faces.
func _check_audit() -> bool:
	var kit: RefCounted = _HouseKit.new()
	_HouseKit.set("audit_inward", 0)
	var bucket: RefCounted = kit.call("_bucket", "plain", Color.WHITE, {})
	var c: Array[Vector3] = []
	for index: int in 8:
		c.append(Vector3(1.0 if index & 1 else -1.0, 1.0 if index & 2 else -1.0, 1.0 if index & 4 else -1.0) * 0.5)
	for face: Array in [[1, 3, 7, 5], [0, 4, 6, 2], [2, 6, 7, 3], [0, 1, 5, 4], [4, 5, 7, 6], [0, 2, 3, 1]]:
		kit.call("_face", bucket, [c[face[0]], c[face[1]], c[face[2]], c[face[3]]], Vector3(10.0, 0.0, 0.0))
	kit.call("_audit_shape")
	var caught := int(_HouseKit.get("audit_inward"))
	_HouseKit.set("audit_inward", 0)
	print("[MeshCheck] audit        %s  a box faced from outside shows %d inward faces" % ["ok  " if caught > 0 else "FAIL", caught])
	return caught > 0


func _check_styles() -> bool:
	var ok := true
	for hood: String in _HoodStyles.ids():
		var look: Dictionary = _HoodStyles.style(hood)
		for stories: int in [1, 2]:
			for archetype: String in _HoodStyles.archetypes_for(hood, stories):
				if not _Archetypes.ALL.has(archetype) or _Archetypes.NEIGHBOR_ONLY.has(archetype):
					ok = false
					print("[MeshCheck] style %s FAIL  job archetype %s" % [hood, archetype])
			for entry: Array in _HoodStyles.neighbor_archetype_weights(hood, stories):
				if not _Archetypes.ALL.has(str(entry[0])):
					ok = false
					print("[MeshCheck] style %s FAIL  neighbor archetype %s" % [hood, entry[0]])
		if bool(look["fallback"]):
			ok = false
			print("[MeshCheck] style %s FAIL  fell back" % hood)
	# One style per neighborhood the town has (net/town/neighborhoods.gd).
	for entry: Dictionary in preload("res://net/town/neighborhoods.gd").HOODS:
		if not _HoodStyles.ids().has(str(entry["id"])):
			ok = false
			print("[MeshCheck] style %s FAIL  has no look in hood_styles.gd" % entry["id"])
	print("[MeshCheck] styles %s  %d neighborhoods" % ["ok  " if ok else "FAIL", _HoodStyles.ids().size()])
	return ok
