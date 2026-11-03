extends RefCounted

## Authority: local, cosmetic. The hats the shops sell (docs/GAME.md
## "Cosmetics"; gap-specs shops chunk 7), built in code with props/mesh_kit.gd
## for player/cartoon_body.gd's head (CartoonBody.hat_style), Homie Depot's hat
## rack (levels/dressing/wardrobe.gd, props/shelf_stock.gd) and the studio.
##
## Each hat is drawn in its own "hat space" and sits on the head at `at` (in the
## CartoonHead's space: y up, the face toward -Z). Most hats sit tilted back on
## a band round the head (SEAT, SEAT_TILT): there the head's cross-section is
## about SEAT_RADIUS across and its crown rises SEAT_DOME above the band, so a
## hat's crown clears those and its band sits above the brows at the front and
## above the ears at the sides. The caps (hd_cap, trucker) use the old cap's
## head-space shape, which R2b fixed to sit above the eyes, and the crown perches
## on top of the player's own hair. Every hat brings the hair that peeks out
## under it at the back (in the player's hair color), except the crown, which
## keeps the whole mop.
##
## Detail: every blob is detail 1 or 0, the hair under a hat included; tubes stay
## at 14 sides or fewer; never rbox (gap-specs/critic.md C20: the body is already
## over its triangle budget). net/dev/shop_test.gd checks every hat stays under
## MAX_TRIANGLES and clear of the eyes.

const _MeshKit = preload("res://props/mesh_kit.gd")

## Every style a hat item can wear (Catalog "style"), in rack order.
const STYLES: Array[String] = ["hd_cap", "beanie", "bucket", "hard", "cowboy", "chef", "crown", "cone", "propeller", "viking", "trucker"]
## The band a tilted hat sits on, in the head's space: its middle, how far it
## tips back (rad), the head's half-width there, and how high the head's crown
## rises over it.
## The middle is where the tilted band's plane cuts the head's middle (the head
## is centered at y 0.02), so the band hugs the forehead instead of standing off
## it; the head is a little narrower front to back, so hats are too (SEAT_DEPTH).
const SEAT := Vector3(0.0, 0.145, 0.035)
const SEAT_TILT: float = 0.3
const SEAT_DEPTH: float = 0.95
const SEAT_RADIUS: float = 0.245
const SEAT_DOME: float = 0.14
## How much higher the shop's caps sit than the cap your name gives you (m).
const CAP_LIFT: float = 0.032
## Where the trucker cap's foam front meets its mesh back (head space z).
const TRUCKER_SEAM_Z: float = -0.06
## The crown perches on the hair, tipped a little to one side.
const CROWN_AT := Vector3(0.0, 0.262, 0.045)
## Where the propeller's hub sits, in hat space.
const PROPELLER_HUB := Vector3(0.0, 0.272, 0.0)
## No hat may cost more than this many triangles (with its hair): less than the
## cap your name gives you (about 1,040, which it replaces), so a hat never adds
## to a body that is already over budget (critic C20).
const MAX_TRIANGLES: int = 700
## The eyes, in the head's space (cartoon_body.gd _build_head): no hat may come
## lower than EYE_TOP within EYE_HALF_WIDTH of the middle, in front of the face.
const EYE_TOP: float = 0.145
const EYE_HALF_WIDTH: float = 0.17

const HD_ORANGE := Color(0.93, 0.47, 0.13)
const WHITE := Color(0.97, 0.96, 0.93)
const KNIT := Color(0.24, 0.5, 0.34)
const KHAKI := Color(0.74, 0.67, 0.48)
const SAFETY := Color(0.98, 0.79, 0.12)
const LEATHER := Color(0.55, 0.36, 0.2)
const BAND_DARK := Color(0.2, 0.14, 0.1)
const CONE_ORANGE := Color(0.98, 0.43, 0.1)
const RUBBER := Color(0.12, 0.12, 0.13)
const STEEL := Color(0.62, 0.64, 0.68)
const BRONZE := Color(0.74, 0.52, 0.24)
const HORN := Color(0.94, 0.9, 0.78)
const GOLD := Color(0.96, 0.77, 0.22)
const RUBY := Color(0.86, 0.1, 0.16)
const SAPPHIRE := Color(0.18, 0.38, 0.92)
const MUSTARD := Color(0.98, 0.76, 0.24)
const KETCHUP := Color(0.8, 0.2, 0.14)
const CHEFTY_RED := Color(0.75, 0.22, 0.15)
const PROPELLER_COLORS: Array[Color] = [Color(0.88, 0.2, 0.18), Color(0.98, 0.8, 0.2), Color(0.2, 0.45, 0.88), Color(0.3, 0.68, 0.32)]

const _SMOOTH: Dictionary = {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0}
const _ROUND: Dictionary = {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0}

static var _cache: Dictionary = {}


static func has_style(style: String) -> bool:
	return STYLES.has(style)


## Put a shop look ({hat, shirt}: catalog ids, "" for your own) on a
## CartoonBody's properties, over what dress_from_seed gave it: the hat's style,
## a dyed shirt (Constants.SHIRT_DYES), or the hi-vis vest over your own shirt.
## Then build() or rebuild() it.
static func wear(body: Node, look: Dictionary) -> void:
	var hat := Catalog.item(str(look.get("hat", "")))
	if str(hat.get("slot", "")) == "hat" and has_style(str(hat.get("style", ""))):
		body.set("hat_style", str(hat["style"]))
	body.set("vest", "")
	var shirt := Catalog.item(str(look.get("shirt", "")))
	if str(shirt.get("slot", "")) == "shirt":
		var which: Variant = shirt.get("shirt", 0)
		if str(which) == "hivis":
			body.set("vest", "hivis")
		elif typeof(which) == TYPE_INT and int(which) >= 0 and int(which) < Constants.SHIRT_DYES.size():
			body.set("shirt", Constants.SHIRT_DYES[int(which)])


## A hat for a head: {mesh: in hat space, at: where hat space sits in the head's
## space, spin: the propeller's blades or null, spin_at: their hub in hat space,
## hair: the hair that peeks out under it (in the head's space) or null}. Cached
## by style and hair color.
static func build(style: String, hair: Color) -> Dictionary:
	var key := "%s|%s" % [style, hair.to_html()]
	if _cache.has(key):
		return _cache[key]
	var kit := _MeshKit.new()
	var at := Transform3D(Basis(Vector3.RIGHT, SEAT_TILT) * Basis.from_scale(Vector3(1.0, 1.0, SEAT_DEPTH)), SEAT)
	var spin: ArrayMesh = null
	var hair_kit := _MeshKit.new()
	var back_hair := true
	match style:
		"hd_cap":
			at = Transform3D.IDENTITY
			_cap(kit, HD_ORANGE, HD_ORANGE.darkened(0.12), true)
		"trucker":
			at = Transform3D.IDENTITY
			_trucker(kit)
		"beanie":
			_beanie(kit, KNIT, WHITE)
		"propeller":
			_beanie(kit, PROPELLER_COLORS[0], PROPELLER_COLORS[1], false)
			kit.tube(PackedVector3Array([Vector3(0.0, 0.2, 0.0), PROPELLER_HUB]), PackedFloat32Array([0.014, 0.011]), Color(0.8, 0.8, 0.82), 6, {"jitter": 0.0})
			spin = _propeller()
		"bucket":
			_bucket(kit)
		"hard":
			_hard(kit)
		"cowboy":
			_cowboy(kit)
		"chef":
			_chef(kit)
		"cone":
			_cone(kit)
		"viking":
			_viking(kit)
		"crown":
			at = Transform3D(Basis(Vector3.BACK, 0.12) * Basis(Vector3.RIGHT, 0.08), CROWN_AT)
			_crown(kit)
			back_hair = false
	var mesh := kit.commit()
	if style == "propeller":
		mesh = _quartered(mesh, PROPELLER_COLORS, 0.12)
	elif style == "trucker":
		mesh = _trucker_front(mesh)
	if back_hair:
		# Hair at the back and sides, under the hat (the cap's, R2b).
		hair_kit.blob(Vector3(0.0, -0.02, 0.12), Vector3(0.25, 0.12, 0.17), hair, {"detail": 1, "lumps": 0.15, "lump_scale": 3.0, "outward": true, "flat": false, "jitter": 0.0})
	else:
		hair_kit.blob(Vector3(0.0, 0.14, 0.06), Vector3(0.28, 0.19, 0.27), hair, {"detail": 1, "lumps": 0.16, "lump_scale": 2.6, "outward": true, "flat": false, "jitter": 0.0, "seed": int(hair.r * 100.0)})
	var made := {"mesh": mesh, "at": at, "spin": spin, "spin_at": PROPELLER_HUB, "hair": hair_kit.commit()}
	_cache[key] = made
	return made


## A hat on a plain foam head, as one mesh, for the hat rack and the studio:
## the head's middle at the origin, the face toward -Z.
static func display_mesh(style: String) -> ArrayMesh:
	var key := "display|" + style
	if _cache.has(key):
		return _cache[key]
	var hat := build(style, Color(0.3, 0.3, 0.32))
	var form := _MeshKit.new()
	form.blob(Vector3(0.0, 0.02, 0.0), Vector3(0.25, 0.26, 0.245), Color(0.86, 0.84, 0.8), _ROUND)
	# A neck on a little stand, so it reads as a display head.
	form.tube(PackedVector3Array([Vector3(0.0, -0.32, 0.0), Vector3(0.0, -0.16, 0.0)]), PackedFloat32Array([0.07, 0.08]), Color(0.86, 0.84, 0.8), 8, {"jitter": 0.0})
	var parts: Array = [[form.commit(), Transform3D.IDENTITY], [hat["mesh"], hat["at"]]]
	if hat["spin"] != null:
		parts.append([hat["spin"], (hat["at"] as Transform3D) * Transform3D(Basis(Vector3.UP, 0.6), hat["spin_at"])])
	var mesh := merged(parts)
	_cache[key] = mesh
	return mesh


## Meshes put together into one, each moved by its transform: [[mesh, xform], ...].
static func merged(parts: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for part: Array in parts:
		var mesh := part[0] as ArrayMesh
		if mesh == null:
			continue
		var xform: Transform3D = part[1]
		var arrays := mesh.surface_get_arrays(0)
		var basis := xform.basis.inverse().transposed()
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			vertices.append(xform * vertex)
		for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array:
			normals.append((basis * normal).normalized())
		colors.append_array(arrays[Mesh.ARRAY_COLOR] as PackedColorArray)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = vertices
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


## How many triangles a hat costs, hair and blades included (for the test).
static func triangles(style: String) -> int:
	var hat := build(style, Color.BLACK)
	var count := 0
	for key: String in ["mesh", "spin", "hair"]:
		var mesh := hat[key] as ArrayMesh
		if mesh != null:
			count += (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return count


## The lowest point (head space y) any of a hat's own surface reaches in front of
## the eyes (within EYE_HALF_WIDTH of the middle and ahead of the face, z < -0.12),
## for the test: it must stay above EYE_TOP.
static func lowest_over_eyes(style: String) -> float:
	var hat := build(style, Color.BLACK)
	var lowest := INF
	var at: Transform3D = hat["at"]
	for vertex: Vector3 in (hat["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		var p := at * vertex
		if absf(p.x) <= EYE_HALF_WIDTH and p.z < -0.12 and _outside_head(p):
			lowest = minf(lowest, p.y)
	return lowest


## Whether a point (head space) is outside the head: a hat's parts inside it
## never show, so they don't count.
static func _outside_head(p: Vector3) -> bool:
	var q := (p - Vector3(0.0, 0.02, 0.0)) / Vector3(0.265, 0.27, 0.255)
	return q.length() > 1.0


# ---------------------------------------------------------------- the hats

## A baseball cap in the head's own space: the old cap's shape (R2b), sat
## CAP_LIFT higher, so the brim's underside clears the eyes' tops even from
## straight ahead. A white patch on the front for Homie Depot's.
static func _cap(kit: RefCounted, crown: Color, brim: Color, logo: bool) -> void:
	var up := Vector3(0.0, CAP_LIFT, 0.0)
	kit.call("blob", Vector3(0.0, 0.2, 0.01) + up, Vector3(0.285, 0.16, 0.285), crown, _ROUND)
	kit.call("blob", Vector3(0.0, 0.135, -0.29) + up, Vector3(0.17, 0.018, 0.12), brim, _ROUND)
	kit.call("blob", Vector3(0.0, 0.36, 0.01) + up, Vector3(0.03, 0.015, 0.03), crown.darkened(0.15), _SMOOTH)
	if logo:
		# Homie Depot's mark: a white patch with an orange bar through it.
		kit.call("blob", Vector3(0.0, 0.262, -0.262) + up, Vector3(0.07, 0.05, 0.014), WHITE, _SMOOTH)
		kit.call("blob", Vector3(0.0, 0.262, -0.274) + up, Vector3(0.045, 0.012, 0.006), HD_ORANGE, {"detail": 0, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})


## Dot's Lunch Money trucker cap: a red mesh back and brim; its front panel is
## mustard foam (_trucker_front), with a ketchup squiggle across it.
static func _trucker(kit: RefCounted) -> void:
	_cap(kit, KETCHUP.lightened(0.05), KETCHUP, false)


## The trucker cap's crown, mustard over the front half (above the brim), with
## a ketchup squiggle on it.
static func _trucker_front(mesh: ArrayMesh) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tints: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for index: int in vertices.size():
		var at := vertices[index]
		# The crown's front, not the brim (under 0.158) or the button on top.
		if at.z < TRUCKER_SEAM_Z and at.y > 0.158 + CAP_LIFT and at.y < 0.35 + CAP_LIFT:
			var shade := tints[index].v / maxf(KETCHUP.lightened(0.05).v, 0.01)
			var tint := MUSTARD * clampf(shade, 0.5, 1.2)
			tint.a = tints[index].a
			tints[index] = tint
	arrays[Mesh.ARRAY_COLOR] = tints
	var front := ArrayMesh.new()
	front.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var squiggle := _MeshKit.new()
	var line := PackedVector3Array()
	for step: int in 9:
		var t := float(step) / 8.0
		var x := lerpf(-0.11, 0.11, t)
		var y := 0.262 + CAP_LIFT + 0.018 * sin(t * TAU * 1.5)
		# On the crown's surface there (center (0, 0.2, 0.01), radii 0.285, 0.16, 0.285).
		var q := 1.0 - pow(x / 0.285, 2.0) - pow((y - 0.2 - CAP_LIFT) / 0.16, 2.0)
		line.append(Vector3(x, y, 0.01 - 0.285 * sqrt(maxf(q, 0.0)) - 0.006))
	squiggle.tube(line, PackedFloat32Array([0.011]), KETCHUP, 5, {"jitter": 0.0})
	# Piping over the seam between the foam front and the mesh back, round the
	# crown where it's cut at TRUCKER_SEAM_Z, so the colors meet on a line.
	var cut := 1.0 - pow((TRUCKER_SEAM_Z - 0.01) / 0.285, 2.0)
	var piping := PackedVector3Array()
	for step: int in 17:
		var angle := PI * float(step) / 16.0
		var x := cos(angle) * 0.285 * sqrt(cut) * 1.02
		var y := 0.2 + CAP_LIFT + sin(angle) * 0.16 * sqrt(cut) * 1.03
		if y >= 0.15 + CAP_LIFT:
			piping.append(Vector3(x, y, TRUCKER_SEAM_Z))
	squiggle.tube(piping, PackedFloat32Array([0.009]), MUSTARD.darkened(0.3), 5, {"jitter": 0.0, "wobble": 0.0})
	return merged([[front, Transform3D.IDENTITY], [squiggle.commit(), Transform3D.IDENTITY]])


## A knit beanie with a folded cuff, and a pom-pom unless it's the propeller's.
static func _beanie(kit: RefCounted, knit: Color, pom: Color, with_pom: bool = true) -> void:
	kit.call("blob", Vector3.ZERO, Vector3(0.256, 0.212, 0.251), knit, {"detail": 1, "lumps": 0.04, "lump_scale": 7.0, "outward": true, "flat": false, "jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0.0, -0.025, 0.0), Vector3(0.0, 0.065, 0.0)]), PackedFloat32Array([0.272, 0.268]), knit.darkened(0.16), 14, {"jitter": 0.0, "cap": false, "wobble": 0.0})
	if with_pom:
		kit.call("blob", Vector3(0.0, 0.235, 0.0), Vector3(0.075, 0.068, 0.075), pom, {"detail": 1, "lumps": 0.35, "lump_scale": 4.0, "outward": true, "flat": false, "jitter": 0.0})


## A floppy khaki bucket hat: a short crown with a rounded top, a brim sloping down.
static func _bucket(kit: RefCounted) -> void:
	kit.call("tube", PackedVector3Array([Vector3(0.0, -0.03, 0.0), Vector3(0.0, 0.13, 0.0)]), PackedFloat32Array([0.264, 0.238]), KHAKI, 14, {"jitter": 0.0, "cap": false, "wobble": 0.0})
	kit.call("blob", Vector3(0.0, 0.13, 0.0), Vector3(0.238, 0.05, 0.238), KHAKI, _ROUND)
	# A stitched band round the crown.
	kit.call("tube", PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.03, 0.0)]), PackedFloat32Array([0.266, 0.264]), KHAKI.darkened(0.25), 14, {"jitter": 0.0, "cap": false, "wobble": 0.0})
	kit.call("cone", Vector3(0.0, -0.075, 0.0), 0.42, 0.06, KHAKI.darkened(0.08), 16, {"top_radius": 0.26, "lumps": 0.0})


## A yellow hard hat: a dome with a ridge, a thin rim and a short visor in front.
static func _hard(kit: RefCounted) -> void:
	kit.call("blob", Vector3.ZERO, Vector3(0.27, 0.225, 0.27), SAFETY, _ROUND)
	kit.call("blob", Vector3(0.0, 0.19, 0.02), Vector3(0.042, 0.055, 0.225), SAFETY.lightened(0.08), _SMOOTH)
	kit.call("cone", Vector3(0.0, -0.05, 0.0), 0.315, 0.05, SAFETY.darkened(0.06), 14, {"top_radius": 0.268, "lumps": 0.0})
	kit.call("blob", Vector3(0.0, -0.04, -0.265), Vector3(0.19, 0.022, 0.1), SAFETY.darkened(0.06), _SMOOTH)


## A cowboy hat: a tall pinched crown with a dark band, and a wide brim whose
## sides curl up.
static func _cowboy(kit: RefCounted) -> void:
	kit.call("tube", PackedVector3Array([Vector3(0.0, -0.03, 0.0), Vector3(0.0, 0.12, 0.0), Vector3(0.0, 0.2, 0.0)]), PackedFloat32Array([0.252, 0.238, 0.205]), LEATHER, 14, {"jitter": 0.0, "cap": false, "wobble": 0.0})
	kit.call("blob", Vector3(0.0, 0.2, 0.0), Vector3(0.205, 0.05, 0.212), LEATHER.lightened(0.04), _ROUND)
	# The crease along the top.
	kit.call("blob", Vector3(0.0, 0.238, 0.0), Vector3(0.03, 0.016, 0.17), LEATHER.darkened(0.25), _SMOOTH)
	kit.call("tube", PackedVector3Array([Vector3(0.0, -0.005, 0.0), Vector3(0.0, 0.045, 0.0)]), PackedFloat32Array([0.255, 0.252]), BAND_DARK, 14, {"jitter": 0.0, "cap": false, "wobble": 0.0})
	_curled_brim(kit, 0.245, 0.45, LEATHER.darkened(0.06))


## The cowboy brim: a ring from inner to outer radius, its sides (along x)
## curling up and its front and back dipping, two-sided.
static func _curled_brim(kit: RefCounted, inner: float, outer: float, color: Color) -> void:
	var steps := 24
	var rings := [0.0, 0.5, 1.0]
	var points: Array[PackedVector3Array] = []
	for t: float in rings:
		var ring := PackedVector3Array()
		for step: int in steps:
			var angle := TAU * float(step) / float(steps)
			var side := cos(angle)
			var radius := lerpf(inner, outer + 0.03 * side * side, t)
			var y := -0.03 + t * t * 0.13 * side * side - t * 0.03 * sin(angle) * sin(angle)
			ring.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
		points.append(ring)
	for band: int in rings.size() - 1:
		for step: int in steps:
			var next := (step + 1) % steps
			_quad(kit, points[band][step], points[band][next], points[band + 1][next], points[band + 1][step], color)


## A puffy white chef's hat (Chefty-brand: a red band).
static func _chef(kit: RefCounted) -> void:
	kit.call("tube", PackedVector3Array([Vector3(0.0, -0.03, 0.0), Vector3(0.0, 0.06, 0.0)]), PackedFloat32Array([0.266, 0.264]), WHITE.darkened(0.04), 14, {"jitter": 0.0, "cap": false, "wobble": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0.0, 0.02, 0.0), Vector3(0.0, 0.045, 0.0)]), PackedFloat32Array([0.268, 0.268]), CHEFTY_RED, 14, {"jitter": 0.0, "cap": false, "wobble": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0.0, 0.05, 0.0), Vector3(0.0, 0.2, 0.0)]), PackedFloat32Array([0.258, 0.275]), WHITE, 14, {"jitter": 0.0, "cap": false, "wobble": 0.0})
	kit.call("blob", Vector3(0.0, 0.27, 0.0), Vector3(0.31, 0.14, 0.305), WHITE, {"detail": 1, "lumps": 0.18, "lump_scale": 3.2, "outward": true, "flat": false, "jitter": 0.0, "seed": 3})


## A traffic cone worn as a hat: orange, two white stripes, a black rubber base.
static func _cone(kit: RefCounted) -> void:
	var base_y := -0.03
	var height := 0.5
	var radius := 0.27
	var tip := 0.022
	kit.call("cone", Vector3(0.0, base_y, 0.0), radius, height, CONE_ORANGE, 14, {"top_radius": tip, "lumps": 0.0})
	for stripe: Vector2 in [Vector2(0.16, 0.24), Vector2(0.31, 0.37)]:
		var r0 := lerpf(radius, tip, stripe.x / height) + 0.004
		var r1 := lerpf(radius, tip, stripe.y / height) + 0.004
		kit.call("cone", Vector3(0.0, base_y + stripe.x, 0.0), r0, stripe.y - stripe.x, WHITE, 14, {"top_radius": r1, "lumps": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0.0, base_y - 0.035, 0.0), Vector3(0.0, base_y + 0.012, 0.0)]), PackedFloat32Array([0.29, 0.285]), RUBBER, 14, {"jitter": 0.0, "cap": false, "wobble": 0.0})


## A steel helmet with a bronze band and rivets, a ridge, and two curved horns.
static func _viking(kit: RefCounted) -> void:
	kit.call("blob", Vector3.ZERO, Vector3(0.266, 0.228, 0.262), STEEL, _ROUND)
	kit.call("blob", Vector3(0.0, 0.14, 0.0), Vector3(0.032, 0.095, 0.23), BRONZE, _SMOOTH)
	kit.call("tube", PackedVector3Array([Vector3(0.0, -0.035, 0.0), Vector3(0.0, 0.035, 0.0)]), PackedFloat32Array([0.276, 0.272]), BRONZE, 14, {"jitter": 0.0, "cap": false, "wobble": 0.0})
	for index: int in 10:
		var angle := TAU * float(index) / 10.0 + 0.3
		kit.call("blob", Vector3(cos(angle) * 0.279, 0.0, sin(angle) * 0.279), Vector3.ONE * 0.012, BRONZE.lightened(0.2), {"detail": 0, "lumps": 0.0, "flat": false, "jitter": 0.0})
	for side: float in [-1.0, 1.0]:
		var horn := PackedVector3Array([
			Vector3(side * 0.235, 0.04, 0.0), Vector3(side * 0.34, 0.09, -0.02),
			Vector3(side * 0.41, 0.2, -0.05), Vector3(side * 0.425, 0.31, -0.07)])
		kit.call("tube", horn, PackedFloat32Array([0.056, 0.046, 0.03, 0.007]), HORN, 8, {"jitter": 0.0})


## The Lawnfather's crown: a gold band with five points, jewels round it.
static func _crown(kit: RefCounted) -> void:
	var low := 0.205
	var high := 0.22
	kit.call("tube", PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.1, 0.0)]), PackedFloat32Array([low, high]), GOLD, 12, {"jitter": 0.0, "cap": false, "wobble": 0.0})
	# Its inside, so looking in over the rim shows gold, not the far wall's back.
	kit.call("tube", PackedVector3Array([Vector3(0.0, 0.1, 0.0), Vector3(0.0, 0.0, 0.0)]), PackedFloat32Array([high - 0.012, low - 0.012]), GOLD.darkened(0.3), 12, {"jitter": 0.0, "cap": false, "wobble": 0.0})
	var rim := PackedVector3Array()
	for step: int in 13:
		var angle := TAU * float(step) / 12.0
		rim.append(Vector3(cos(angle) * (high - 0.006), 0.1, sin(angle) * (high - 0.006)))
	kit.call("tube", rim, PackedFloat32Array([0.012]), GOLD.lightened(0.1), 5, {"jitter": 0.0, "cap": false, "wobble": 0.0})
	for point: int in 5:
		var angle := TAU * float(point) / 5.0 - PI * 0.5
		var at := Vector3(cos(angle) * (high - 0.004), 0.1, sin(angle) * (high - 0.004))
		kit.call("cone", at, 0.045, 0.1, GOLD, 6, {"lumps": 0.0})
		kit.call("blob", at + Vector3(0.0, 0.105, 0.0), Vector3.ONE * 0.02, GOLD.lightened(0.15), {"detail": 0, "lumps": 0.0, "flat": false, "jitter": 0.0})
		var jewel_angle := angle + TAU / 10.0
		kit.call("blob", Vector3(cos(jewel_angle) * (low + 0.012), 0.05, sin(jewel_angle) * (low + 0.012)), Vector3(0.022, 0.026, 0.022), RUBY if point % 2 == 0 else SAPPHIRE, {"detail": 0, "lumps": 0.0, "flat": true, "jitter": 0.0, "shade": false})


## The propeller's two blades round a hub, in the hub's space.
static func _propeller() -> ArrayMesh:
	var kit := _MeshKit.new()
	kit.blob(Vector3.ZERO, Vector3(0.022, 0.016, 0.022), Color(0.8, 0.8, 0.82), _SMOOTH)
	for side: float in [-1.0, 1.0]:
		kit.blob(Vector3(side * 0.1, 0.0, 0.0), Vector3(0.1, 0.008, 0.032), PROPELLER_COLORS[0 if side < 0.0 else 1], {"detail": 1, "lumps": 0.0, "flat": true, "jitter": 0.0})
	return kit.commit()


## Recolor a beanie's dome into four colored quarters round its middle (the
## propeller beanie), leaving everything above top_y (the stalk) as it is.
static func _quartered(mesh: ArrayMesh, colors: Array[Color], top_y: float) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tints: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	# By each corner's own angle, so the seams between quarters run soft along the
	# dome's edges instead of zigzagging triangle by triangle.
	for index: int in vertices.size():
		var at := vertices[index]
		if at.y > top_y + 0.1 or Vector2(at.x, at.z).length() < 0.02:
			continue
		var quarter := int(floor(fposmod(atan2(at.z, at.x) + PI * 0.25, TAU) / (PI * 0.5))) % 4
		var shade := tints[index].v / maxf(colors[0].v, 0.01)
		var tint := colors[quarter] * clampf(shade, 0.5, 1.2)
		tint.a = tints[index].a
		tints[index] = tint
	arrays[Mesh.ARRAY_COLOR] = tints
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## A two-sided quad a, b, c, d (in order round its edge).
static func _quad(kit: RefCounted, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var normal := (c - a).cross(b - a).normalized()
	if normal.y < 0.0:
		normal = -normal
		var swap := b
		b = d
		d = swap
	var under := color.darkened(0.25)
	kit.call("triangle", a, b, c, normal, color)
	kit.call("triangle", a, c, d, normal, color)
	kit.call("triangle", a, c, b, -normal, under)
	kit.call("triangle", a, d, c, -normal, under)
