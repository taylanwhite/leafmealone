extends SceneTree

## Checks the prop catalog (props/prop_catalog.gd) headless:
##   godot --headless --path . --script res://tools/prop_check.gd
## (tools/mesh_check.gd runs it too.) For every kind it builds the mesh and checks
## the triangle budget (Constants.ART_PROP_MAX_TRIANGLES, from the "triangles" meta
## recorded at build time) and that every triangle's winding agrees with its
## stored normal (a face wound backwards is culled from the side it is lit from).
## Then: place() works for every kind, labeled kinds get their words, lamps get
## a lens in "street_lamps"; every kind a neighborhood style names exists; every
## sign key exists in Strings.SIGNS and SIGNS and BOAT_NAMES pass
## net/dev/guardrail.gd and the art rule (no "ice", no agency letters);
## PropBatch chunks, refuses complex kinds, fades small props and hashes the
## same twice; the water materials build. Exits 1 on any failure.

const _Catalog = preload("res://props/prop_catalog.gd")
const _Batch = preload("res://props/prop_batch.gd")
const _Water = preload("res://props/water_surface.gd")
const _HoodStyles = preload("res://levels/town/hood_styles.gd")
const _Strings = preload("res://ui/strings.gd")
const _Guardrail = preload("res://net/dev/guardrail.gd")

## Share of a mesh's triangles allowed to disagree with their normal (smooth
## shading on tight curves can tip a sliver or two).
const WINDING_SLACK := 0.01
## The art spec's own word rule for sign text (stricter than the guardrail).
const ART_WORDS := "(?i)\\b(ice|cbp|dhs|fbi|atf)\\b"


func _init() -> void:
	quit(0 if run() else 1)


static func run() -> bool:
	var ok := true
	ok = _check_meshes() and ok
	ok = _check_place() and ok
	ok = _check_styles() and ok
	ok = _check_words() and ok
	ok = _check_batch() and ok
	ok = _check_water() and ok
	print("[PropCheck] %s" % ("ok" if ok else "FAIL"))
	return ok


static func _check_meshes() -> bool:
	var ok := true
	var most := 0
	var heaviest := ""
	var kinds := _Catalog.kinds()
	for kind: String in kinds:
		var mesh := _Catalog.mesh(kind)
		var triangles := int(mesh.get_meta("triangles", -1))
		var wrong := _misfacing(mesh)
		var good := triangles > 0 and triangles <= Constants.ART_PROP_MAX_TRIANGLES and float(wrong) <= float(triangles) * WINDING_SLACK
		if triangles > most:
			most = triangles
			heaviest = kind
		if not good:
			ok = false
			print("[PropCheck] mesh %-22s FAIL  %d triangles (budget %d), %d wound against their normal" % [kind, triangles, Constants.ART_PROP_MAX_TRIANGLES, wrong])
	# The older YardModels kinds the catalog falls back to predate the budget;
	# list what they cost so a batch of them is a choice, not a surprise.
	var legacy := PackedStringArray()
	for kind: String in _Catalog.FALLBACK_KINDS:
		legacy.append("%s %d" % [kind, int(_Catalog.mesh(kind).get_meta("triangles", -1))])
	print("[PropCheck] fallback kinds (props/yard_models.gd, not budgeted): %s" % ", ".join(legacy))
	print("[PropCheck] meshes %s  %d kinds, heaviest %s at %d triangles" % ["ok  " if ok else "FAIL", kinds.size(), heaviest, most])
	return ok


## Triangles whose winding (Godot's front face, normal (c - a) x (b - a)) points
## away from their stored normal.
static func _misfacing(mesh: ArrayMesh) -> int:
	var wrong := 0
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for tri: int in range(0, vertices.size() - 2, 3):
			var a := vertices[tri]
			var front := (vertices[tri + 2] - a).cross(vertices[tri + 1] - a)
			if front.length_squared() < 1e-12:
				continue
			var stored := normals[tri] + normals[tri + 1] + normals[tri + 2]
			if front.dot(stored) < 0.0:
				wrong += 1
	return wrong


static func _check_place() -> bool:
	var ok := true
	var holder := Node3D.new()
	for kind: String in _Catalog.kinds():
		var placed := _Catalog.place(holder, kind, Transform3D(Basis.IDENTITY, Vector3(3.0, 0.0, 5.0)), Color.WHITE, {"season": 0})
		var problems := PackedStringArray()
		if str(placed.get_meta("prop_kind", "")) != kind:
			problems.append("no prop_kind meta")
		if kind != "wire_span" and placed.find_children("*", "GeometryInstance3D", true, false).is_empty():
			problems.append("nothing drawn")
		if _Catalog.LABELS.has(kind) and str(_Catalog.LABELS[kind].get("sign", "")) != "" and placed.find_children("*", "Label3D", true, false).is_empty():
			problems.append("no words")
		if _Catalog.LAMP_GLOWS.has(kind):
			var lit := false
			for child: Node in placed.get_children():
				lit = lit or child.is_in_group("street_lamps")
			if not lit:
				problems.append("no lens in street_lamps")
		if kind in ["boat_row", "boat_motor"] and placed.find_children("*", "Label3D", true, false).size() != 2:
			problems.append("no name on both sides")
		if not problems.is_empty():
			ok = false
			print("[PropCheck] place %-21s FAIL  %s" % [kind, ", ".join(problems)])
	# Winter freezes the pool and stops the fountain's sheets.
	var pool := _Catalog.place(holder, "pool_inground", Transform3D.IDENTITY, Color.WHITE, {"season": 1})
	var fountain := _Catalog.place(holder, "fountain_tiered", Transform3D.IDENTITY, Color.WHITE, {"season": 1})
	var frozen := false
	for child: Node in pool.get_children():
		frozen = frozen or str(child.get_meta("water", "")) == "frozen"
	if not frozen or fountain.find_child("Sheet1", false, false) != null:
		ok = false
		print("[PropCheck] place winter FAIL  the pool or fountain ignored the season")
	holder.free()
	print("[PropCheck] place %s  every kind placed" % ("ok  " if ok else "FAIL"))
	return ok


## Every prop kind, car and mailbox a neighborhood style names is in the catalog.
static func _check_styles() -> bool:
	var ok := true
	for hood: String in _HoodStyles.ids():
		var look: Dictionary = _HoodStyles.style(hood)
		var wanted: Array = [str(look["mailbox"])]
		for entry: Array in look["yard_props"]:
			wanted.append(str(entry[0]))
		for entry: Array in look["cars"]:
			wanted.append(str(entry[0]))
		for kind: String in wanted:
			if not _Catalog.has(kind):
				ok = false
				print("[PropCheck] style %s FAIL  names %s, which the catalog doesn't build" % [hood, kind])
		for key: String in look["signs"]:
			if not _Strings.SIGNS.has(key):
				ok = false
				print("[PropCheck] style %s FAIL  sign %s is not in Strings.SIGNS" % [hood, key])
	print("[PropCheck] styles %s" % ("ok  " if ok else "FAIL"))
	return ok


static func _check_words() -> bool:
	var ok := true
	for kind: String in _Catalog.LABELS:
		var key := str(_Catalog.LABELS[kind].get("sign", ""))
		if key != "" and not _Strings.SIGNS.has(key):
			ok = false
			print("[PropCheck] words FAIL  %s's sign %s is not in Strings.SIGNS" % [kind, key])
	var hits: Array = _Guardrail.sweep(_Strings.SIGNS, "SIGNS")
	hits.append_array(_Guardrail.sweep(_Strings.BOAT_NAMES, "BOAT_NAMES"))
	var strict := RegEx.create_from_string(ART_WORDS)
	for key: String in _Strings.SIGNS:
		if strict.search(str(_Strings.SIGNS[key])) != null:
			hits.append("SIGNS.%s: the art word rule" % key)
	for boat: String in _Strings.BOAT_NAMES:
		if strict.search(boat) != null:
			hits.append("BOAT_NAMES: '%s': the art word rule" % boat)
	if _Strings.BOAT_NAMES.size() < 3:
		hits.append("BOAT_NAMES has fewer than 3 names")
	for hit: String in hits:
		ok = false
		print("[PropCheck] words FAIL  %s" % hit)
	print("[PropCheck] words %s  %d signs, %d boat names" % ["ok  " if ok else "FAIL", _Strings.SIGNS.size(), _Strings.BOAT_NAMES.size()])
	return ok


static func _check_batch() -> bool:
	var ok := true
	var digests: Array[int] = []
	for run_index: int in 2:
		var root := Node3D.new()
		var batch: RefCounted = _Batch.new(root)
		batch.call("add", "pumpkin", Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 1.0)))
		batch.call("add", "pumpkin", Transform3D(Basis(Vector3.UP, 0.5), Vector3(5.0, 0.0, 2.0)))
		batch.call("add", "pumpkin", Transform3D(Basis.IDENTITY, Vector3(40.0, 0.0, 1.0)))
		batch.call("add", "privacy_fence_run", Transform3D(Basis.IDENTITY, Vector3(10.0, 0.0, -3.0)), Color.WHITE, Vector3(12.0, 1.8, 0.0))
		batch.call("add", "car_suv", Transform3D(Basis.IDENTITY, Vector3(12.0, 0.0, 30.0)), Color(0.5, 0.1, 0.1))
		var placed := int(batch.call("commit"))
		digests.append(int(batch.call("hash")))
		var views: Array = root.find_children("*", "MultiMeshInstance3D", false, false)
		var small_chunks := 0
		var small_ok := true
		var counted := 0
		for view: MultiMeshInstance3D in views:
			counted += int(view.get_meta("prop_instances", 0))
			if str(view.get_meta("prop_kind", "")) == "pumpkin":
				small_chunks += 1
				small_ok = small_ok and is_equal_approx(view.visibility_range_end, Constants.ART_SMALL_PROP_RANGE) and view.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if placed != 5 or counted != 5 or views.size() != 4 or small_chunks != 2 or not small_ok or int(batch.call("instance_count")) != 5:
			ok = false
			print("[PropCheck] batch FAIL  placed %d, counted %d in %d views (%d pumpkin chunks), small fade %s" % [placed, counted, views.size(), small_chunks, small_ok])
		root.free()
	if digests[0] != digests[1] or digests[0] == 0:
		ok = false
		print("[PropCheck] batch FAIL  hash %d then %d" % [digests[0], digests[1]])
	print("[PropCheck] batch %s  %d simple kinds batchable" % ["ok  " if ok else "FAIL", _Catalog.SIMPLE.size()])
	return ok


static func _check_water() -> bool:
	var ok := true
	for kind: String in _Water.KINDS:
		var made: ShaderMaterial = _Water.material(kind)
		if made == null or made.shader == null or made.shader.code.is_empty() or _Water.material(kind) != made:
			ok = false
			print("[PropCheck] water FAIL  %s" % kind)
	var sheet := _Water.sheet(0.8, 1.4, 1.1, 0.5)
	if sheet.get_surface_count() != 1 or sheet.surface_get_array_len(0) == 0:
		ok = false
		print("[PropCheck] water FAIL  the fountain sheet is empty")
	print("[PropCheck] water %s  %d kinds" % ["ok  " if ok else "FAIL", _Water.KINDS.size()])
	return ok
