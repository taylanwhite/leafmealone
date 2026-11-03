extends Node

## Authority: host. --cast-test checks the cast (docs/GAME.md, "2026-11-01, the
## cast"; docs/DECISIONS.md, 2026-11-01). Each step prints a [CastTest] line.
##
## Phase A, the string table audit (host, instant), walks every constant in
## ui/strings.gd:
##   1. no empty or blank text
##   2. nothing unfinished: no [SOME NAME] slots, todo, tbd, placeholder, stand-in
##   3. every pool has enough lines, no repeats, and the %s/%d slots FORMAT_ARGS says
##   4. a pool for every personality x mood, bill, text kind, keeper trigger, bark
##      kind, run cue, rank, day bucket, neighborhood, season, unlock, task and tool
##   5. the humor guardrail (Guardrail.check, net/dev/guardrail.gd), which also
##      wants "NICE BOYS" in capitals
##   6. no player-facing sentence written inline in game code, outside ui/strings.gd
##      (fails since cast:3, which moved the last ones)
##   7. Strings.homeowner_pool() resolves mood, bill and personality pools
##   8. Strings.summary_quip() picks the right bucket, the same line every time
## Phase A, the lines in the game (cast:2, host):
##  W1. Marty's line fits the moment (morning, greet or night, after_raid, open or
##      closed; a morning greet keeps the after-raid line for the next greet) and
##      every trigger's line is his own, shown in his caption
##  W2. the town's texts come from TEXT_LINES: Marty's welcome, and each request in
##      the client's own personality's voice with their address; the town save
##      has rival_announced
##  W3. run cues are a CUE_LINES line picked from the phase start, the same twice
##  W4. the day summary card shows the quip and the rank-up's blurb
##  W5. no hired hand is named for a nationality
##  W6. (in phase C) the forced raid is tallied for the summary (Campaign.note_day)
##  W7. the homeowner's reaction pool (homeowner.gd choose_pool, a seeded rng): their
##      personality's voice, bill_water and breakage bills as often as Constants says
## Phase A, the inline sweep's follow-ups (cast:3, host):
##  Q2. the border crossing answers is_thrown_back() (true only while running and
##      thrown back), and a quip player watching it plays border_fail once per throw
##  Q3. season names, and neighborhood and personality blurbs, read from Strings
##  Q1. (in phase C) the director's status is the Strings text, and the quip player
##      plays its run_warning and crew_arrival (Q-009) lines from the phase number
## Phase B, the look (host, a scratch node outside the world):
##   9. a plain cartoon body's triangles, reported against the character budget
##  10. the head NICE BOY and a NICE BOY, dressed by CrewMember.dress(): outfit,
##      visor, grin, every named outfit part, and the outfit's extra triangles
##      within Constants.CREW_OUTFIT_TRIANGLE_BUDGET; a chest seal under 200
##  11. the van (props/nice_van.gd): its lettering is the strings' and passes the
##      guardrail, it keeps its 5 collision boxes, it has wheels, see-through glass
##      and the dome; the pull-up ends exactly where the ride out starts
##  12. the beacon: seal, cones, notices and label; the seal spins; it folds away
##  14b. (in phase C) the van pulled up and is parked at the curb as the crew arrives
## Phase C, a raid with a client watching (a client named Target joins):
## Phase C runs at full heat (the test adds it) on a day other than 1 (--start-day),
## so the client must show plain NICE BOYS and tags from the day the host sends.
##  13. a client joins  14. the director calls a full crew  15. they freeze
##  16. each wears the right outfit and the name tag Strings.crew_tag() gives, and
##      the old capsule is hidden. CI compares probe.gd's crew_cast on both peers.
##  17. barks reach the client (cast:6, PHASE_C_BARKS)

const _Strings = preload("res://ui/strings.gd")
const _Hoods = preload("res://net/town/neighborhoods.gd")
const _Ranks = preload("res://core/ranks.gd")

const _CartoonBody = preload("res://player/cartoon_body.gd")
const _CrewMember = preload("res://npcs/crew_member.gd")
const _NiceSeal = preload("res://props/nice_seal.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _RunCues = preload("res://ui/run_cues.gd")
const _Homeowner = preload("res://npcs/homeowner.gd")
const _QuipPlayer = preload("res://ui/quip_player.gd")
const _Seasons = preload("res://core/seasons.gd")
## Step W7: how many seeded reactions to roll for each homeowner pool case.
const POOL_ROLLS: int = 400

## Steps 9-10: the outfit and its triangles (cast:4).
const PHASE_B_LOOK: bool = true
## Steps 11-12: the van and the beacon (cast:5).
const PHASE_B_VAN: bool = true
const _Vehicles = preload("res://props/vehicles.gd")
const _NiceVan = preload("res://props/nice_van.gd")
const _BeaconScript = preload("res://npcs/arrival_beacon.gd")
const _VanArrival = preload("res://net/run_events/van_arrival.gd")
## Steps 13-16: crew outfits and name tags on a networked crew (cast:4).
const PHASE_C_CREW: bool = true
## Step 17: barks reach the client (cast:6).
const PHASE_C_BARKS: bool = false
## Step 13 waits this long for a client to join.
const CLIENT_WAIT_SECONDS: float = 15.0
## After the crew arrives, this long for the spawn to reach the client.
const CREW_SETTLE_SECONDS: float = 1.5

## The humor guardrail is one list, net/dev/guardrail.gd (critic C31): every
## string is run through Guardrail.check(), which also holds "NICE BOYS" casing.
## Never weaken a pattern there to make a line pass without Taylan; reword the line.
const _Guardrail = preload("res://net/dev/guardrail.gd")

## Unfinished text. A [NAME] or [SOME NAME] slot starts with two capitals, so
## one-letter key labels like "[E]" are not caught.
const PLACEHOLDER_PATTERNS: Array[String] = [
	"\\[[A-Z]{2,}[A-Z _]*\\]",
	"(?i)\\b(todo|tbd|fixme|lorem|placeholder|stand-?ins?)\\b",
]
## A %s, %d or %.Nf slot ("%%" is removed first).
const SLOT_PATTERN := "%-?\\d*(?:\\.\\d+)?[sdf]"
## A pool with no FORMAT_ARGS entry: no slots, at least three lines.
const DEFAULT_FORMAT: Array = [0, 3]

## Text kinds the host composes phone texts from (net/town/town.gd, net/crew/hires.gd).
const TEXT_KINDS: Array[String] = [
	"request", "clerk_intro", "clerk_lead", "referral_named", "referral_anon", "referral_body",
	"poached", "won_back_named", "won_back_signs", "won_back_tail",
	"rival_arrival", "rival_taunt", "rival_sign", "rival_sore",
	"hire_hired", "hire_quit", "hire_fired",
]
const BILL_POOLS: Array[String] = ["bill_hose", "bill_gnome", "bill_medical", "bill_water", "paid"]
const CUE_KINDS: Array[String] = ["radio", "arrived", "clear"]
## Fallbacks for npcs/store_clerk.gd TRIGGERS and npcs/crew_member.gd BARK_KINDS
## (BARK_KINDS comes with cast:6): the lists every keeper and the crew must cover.
const DEFAULT_KEEPER_TRIGGERS: Array[String] = ["greet", "morning", "night", "open", "buy", "after_raid", "closed"]
const DEFAULT_BARK_KINDS: Array[String] = ["arrive", "spot", "chase", "lost", "search", "pile", "caught", "bonked"]

## The inline-text sweep: game code that puts a sentence of its own on screen.
const SWEEP_DIRS: Array[String] = [
	"res://net", "res://npcs", "res://ui", "res://levels", "res://props", "res://player", "res://core",
]
const SWEEP_SKIP: Array[String] = ["res://ui/strings.gd", "res://net/dev/"]
const SWEEP_SITES: Array[String] = [".text =", "text_sign(", "_status = ", "_show_ended(", "_text(", "_set_phase("]
const SWEEP_LITERAL := "\"[A-Za-z][^\"%\\n]*\\s[A-Za-z][^\"\\n]*\""
## Canon brand names that may stay where they are painted.
const SWEEP_ALLOW: Array[String] = ["HOMIE DEPOT", "Homie Depot", "Chefty"]
## The scene sweep (settings:4) reads .tscn files in SWEEP_DIRS and these, for
## these properties. The scenes' text belongs in ui/strings.gd, set by the script.
const SWEEP_SCENE_DIRS: Array[String] = ["res://border", "res://equipment"]
const SWEEP_SCENE_PROPERTIES: Array[String] = ["text", "placeholder_text", "tooltip_text"]

static var result: Dictionary = {}
## The crew as the host saw it in phase C, by node name: tag and outfit.
static var cast: Dictionary = {}
## Phase B's measurements: triangles of a plain body, each outfit, and the seal.
static var look: Dictionary = {}

var _started: bool = false
var _problems: Array[String] = []
var _placeholders: Array[RegEx] = []
var _slot: RegEx


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or get_tree().get_first_node_in_group("world") == null:
		return
	_started = true
	_run()


func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	_compile()
	var counts := _audit_table()
	_coverage()
	_api()
	_wiring()
	var inline := _sweep_inline()
	if PHASE_B_LOOK:
		await _phase_b()
	if PHASE_C_CREW:
		await _phase_c()
	var ok := _problems.is_empty()
	result = {
		"ok": ok, "done": true, "problems": _problems.duplicate(),
		"strings": counts.x, "pools": counts.y, "inline_text": inline,
		"look": look.duplicate(), "cast": cast.duplicate(true),
	}
	print("[CastTest] all ok: %s (%d problems, %d strings, %d pools)" % [ok, _problems.size(), counts.x, counts.y])


## Steps 9-12: the NICE BOYS' outfit and its triangles (cast:4), then the van and
## the beacon (cast:5, PHASE_B_VAN). Built in a scratch node outside the world.
func _phase_b() -> void:
	var scratch := Node3D.new()
	scratch.name = "CastScratch"
	add_child(scratch)
	var before := _problems.size()
	# Step 9: a plain body, the baseline every character starts from.
	var plain: Node3D = _CartoonBody.new()
	plain.call("dress_from_seed", 3)
	scratch.add_child(plain)
	plain.call("build")
	var plain_triangles := _triangles(plain)
	print("[CastTest] step 9: a plain cartoon body is %d triangles (the character budget is %d; over it before the outfit, see docs/ART.md)" % [plain_triangles, Constants.CHARACTER_TRIANGLE_BUDGET])
	look["plain_triangles"] = plain_triangles
	# Step 10: the head NICE BOY and a NICE BOY, dressed by the crew's own helper.
	for index: int in [1, 2]:
		var body: Node3D = _CartoonBody.new()
		_CrewMember.dress(body, index)
		scratch.add_child(body)
		body.position.x = float(index) * 2.0
		body.call("build")
		var outfit := str(body.get("outfit"))
		var want := "nice_boy_lead" if index == 1 else "nice_boy"
		_look(outfit == want, "10 NICE BOY %d wears %s, not '%s'" % [index, want, outfit])
		_look(str(body.get("hat_style")) == "visor", "10 NICE BOY %d wears a visor, not '%s'" % [index, body.get("hat_style")])
		_look(bool(body.get("grin")) and bool(body.get("shades")), "10 NICE BOY %d grins behind sunglasses" % index)
		for part: String in _CartoonBody.OUTFIT_PARTS.get(want, []):
			var node := body.find_child(part, true, false)
			_look(node is MeshInstance3D and (node as MeshInstance3D).mesh != null, "10 NICE BOY %d has a %s" % [index, part])
		var triangles := _triangles(body)
		var extra := triangles - plain_triangles
		_look(extra <= Constants.CREW_OUTFIT_TRIANGLE_BUDGET, "10 NICE BOY %d's outfit adds %d triangles, the budget is %d" % [index, extra, Constants.CREW_OUTFIT_TRIANGLE_BUDGET])
		print("[CastTest] step 10: NICE BOY %d (%s) is %d triangles, %+d over a plain body (outfit budget %d, character budget %d)" % [index, outfit, triangles, extra, Constants.CREW_OUTFIT_TRIANGLE_BUDGET, Constants.CHARACTER_TRIANGLE_BUDGET])
		look["%s_triangles" % want] = triangles
	# The gestures barks will use exist, and the seal stays small at chest size.
	for gesture: String in ["point", "scribble"]:
		_look(_CartoonBody.GESTURE_SECONDS.has(gesture), "10 the body has a '%s' gesture" % gesture)
	var seal := _MeshKit.new()
	_NiceSeal.add(seal, Vector3.ZERO, 0.045, Vector3.FORWARD)
	var seal_triangles := seal.vertex_count() / 3
	_look(seal_triangles > 0 and seal_triangles < 200, "10 a chest-size Daisy Seal is under 200 triangles (%d)" % seal_triangles)
	look["seal_triangles"] = seal_triangles
	if PHASE_B_VAN:
		_van_look(scratch)
		_van_roads()
		await _van_called_off(scratch)
		await _beacon(scratch)
	else:
		print("[CastTest] steps 11-12 (van, beacon) are off until cast:5")
	scratch.queue_free()
	await get_tree().process_frame
	print("[CastTest] steps 9-12, the NICE BOYS' look, van and beacon: %s" % (_problems.size() == before))


## Step 11 (cast:5): the Courtesy Shuttle's livery is the strings' text and passes
## the guardrail, it keeps the five collision boxes riders rely on, and it has
## wheels, see-through glass, the dome, and a Daisy Seal-sized mesh.
func _van_look(scratch: Node3D) -> void:
	var holder := Node3D.new()
	scratch.add_child(holder)
	holder.position = Vector3(20.0, 0.0, 0.0)
	var van: Node3D = _Vehicles.build_van(holder, _Vehicles.VAN_PAINT)
	_look(van != null and van.name == "VanLook", "11 build_van makes a VanLook")
	if van == null:
		return
	var livery := van.get_node_or_null("Livery")
	_look(livery != null, "11 the van has VanLook/Livery")
	var texts: Array[String] = []
	for node: Node in van.find_children("*", "Label3D", true, false):
		var text := (node as Label3D).text
		texts.append(text)
		_look(_Guardrail.is_clean(text), "11 the van's lettering '%s' passes the guardrail" % text)
	if livery != null:
		var painted := livery.find_children("*", "Label3D", true, false).size()
		_look(painted >= 3, "11 the livery has at least 3 lettering labels (%d)" % painted)
	for key: String in ["van_side", "van_motto", "van_rear"]:
		_look(texts.has(str(_Strings.UI[key])), "11 the van carries UI %s ('%s'); it has %s" % [key, _Strings.UI[key], texts])
	var solid := van.get_node_or_null("Solid")
	var boxes := solid.find_children("*", "CollisionShape3D", false, false).size() if solid != null else 0
	_look(boxes == 5, "11 VanLook/Solid keeps exactly 5 collision boxes (%d)" % boxes)
	var wheels := van.get_node_or_null("Wheels")
	_look(wheels != null and wheels.get_child_count() == 4, "11 the van has 4 wheels that can roll")
	for part: String in ["Shell/Body", "Shell/Glass", "Shell/Dome", "Motion"]:
		_look(van.get_node_or_null(part) != null, "11 the van has %s" % part)
	var glass := van.get_node_or_null("Shell/Glass") as MeshInstance3D
	if glass != null:
		var material := glass.material_override as BaseMaterial3D
		_look(material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, "11 the van's glass is see-through")
	var triangles := _triangles(van)
	look["van_triangles"] = triangles
	print("[CastTest] step 11: the van is %d triangles, lettering %s" % [triangles, texts])
	holder.queue_free()


## Step 11, the roads (cast:5): the van that pulls up (van_arrival.gd) ends where
## and facing how the ride leaving with riders starts, so the swap can't be seen;
## the pull-up stops at the curb, and both start from rest.
func _van_roads() -> void:
	var park := Vector3(994.0, 0.0, 28.6)
	var parked := _NiceVan.pose(_NiceVan.arrival_curve(park), 1.0)
	var leaving := _NiceVan.pose(_NiceVan.departure_curve(park, Vector3(0.0, 0.0, 1000.0)), 0.0)
	var gap := parked.origin.distance_to(leaving.origin)
	var turn := parked.basis.get_rotation_quaternion().angle_to(leaving.basis.get_rotation_quaternion())
	_look(gap < 0.01 and turn < deg_to_rad(1.0), "11 the parked van and the leaving ride line up (%.3f m, %.2f deg apart)" % [gap, rad_to_deg(turn)])
	_look(is_equal_approx(_NiceVan.arrive_progress(Constants.VAN_ARRIVE_SECONDS), 1.0) and _NiceVan.arrive_progress(0.0) == 0.0, "11 the pull-up runs 0 to 1")
	var dt := 0.05
	var last_step := _NiceVan.arrive_progress(Constants.VAN_ARRIVE_SECONDS) - _NiceVan.arrive_progress(Constants.VAN_ARRIVE_SECONDS - dt)
	_look(last_step * Constants.VAN_ARRIVE_DISTANCE / dt < 1.0, "11 the van creeps the last bit to the curb (%.2f m/s)" % (last_step * Constants.VAN_ARRIVE_DISTANCE / dt))
	# A ride the length of the lot-to-border road, and a short one.
	for road: Vector2 in [Vector2(8.0, 1414.0), Vector2(8.0, 30.0)]:
		var pulled := _NiceVan.depart_progress(Constants.VAN_PULL_SECONDS / road.x, road.x, road.y) * road.y
		_look(pulled <= 0.5 * Constants.VAN_PULL_ACCEL * Constants.VAN_PULL_SECONDS * Constants.VAN_PULL_SECONDS + 0.01, "11 the ride pulls out from the curb like a van (%.1f m in %.1f s on a %.0f m road)" % [pulled, Constants.VAN_PULL_SECONDS, road.y])
		_look(is_equal_approx(_NiceVan.depart_progress(1.0, road.x, road.y), 1.0), "11 the ride ends at the end of a %.0f m road" % road.y)
		var previous := 0.0
		for step: int in 201:
			var now := _NiceVan.depart_progress(float(step) / 200.0, road.x, road.y)
			_look(now >= previous - 0.000001, "11 the ride never backs up (step %d, %.0f m road)" % [step, road.y])
			previous = now


## A stand-in run director for step 11's call-off: the phase and times
## net/run_events/van_arrival.gd reads, set by the test.
class FakeDirector extends Node:
	var phase_now: int = 0
	var arrive_at: float = 0.0
	var started: float = 0.0
	var park := Vector3(-600.0, 0.0, 28.6)

	func phase() -> int:
		return phase_now

	func arrival_time() -> float:
		return arrive_at if phase_now == 1 else -1.0

	func phase_started_at() -> float:
		return started

	func van_park_point() -> Vector3:
		return park


## Step 11, called off (cast:5): a van that is still pulling up when the call is off
## (everyone left the lot, or the crew gave up) drives on down the street from
## where it is, without a jump back to the curb, and is gone after
## Constants.VAN_LEAVE_SECONDS. Run against a stand-in director, out of the world.
func _van_called_off(scratch: Node3D) -> void:
	var holder := Node.new()
	holder.name = "FakeWorld"
	scratch.add_child(holder)
	var director := FakeDirector.new()
	director.name = "FakeDirector"
	holder.add_child(director)
	var arrival: Node = _VanArrival.new()
	director.add_child(arrival)
	# A warning whose van is 3.5 s into its 5 s pull-up, braking.
	director.phase_now = 1
	director.arrive_at = Net.server_time() + Constants.VAN_ARRIVE_SECONDS - 3.5
	await _physics_ticks(12)
	var van: Node3D = arrival.call("van_look")
	var state := str(arrival.call("state_name"))
	_look(van != null and state == "arriving", "11 a van pulls up during the warning (%s)" % state)
	if van == null:
		holder.queue_free()
		return
	var before := van.global_position
	director.phase_now = 0
	await _physics_ticks(3)
	var after := van.global_position
	var step := (after - before).dot(_NiceVan.STREET_DIR)
	_look(str(arrival.call("state_name")) == "leaving", "11 a called-off van leaves")
	_look(step > 0.0 and before.distance_to(after) < 2.0, "11 it drives on from where it was (%.2f m on, %.2f m moved)" % [step, before.distance_to(after)])
	await get_tree().create_timer(0.6).timeout
	_look((van.global_position - after).dot(_NiceVan.STREET_DIR) > 0.5, "11 it keeps going down the street")
	var waited := 0.0
	while str(arrival.call("state_name")) != "" and waited < Constants.VAN_LEAVE_SECONDS + 1.5:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_look(str(arrival.call("state_name")) == "", "11 the called-off van is gone after %.1f s" % Constants.VAN_LEAVE_SECONDS)
	print("[CastTest] step 11: a called-off van drove on %.2f m in 3 ticks and was gone %.1f s later" % [step, waited + 0.6])
	holder.queue_free()


func _physics_ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


## Step 12 (cast:5): the Courtesy Flare has its seal, cones, notices and label, the
## seal spins, and dismiss() folds it away and frees it.
func _beacon(scratch: Node3D) -> void:
	var beacon: Node3D = _BeaconScript.new()
	scratch.add_child(beacon)
	beacon.position = Vector3(-20.0, 0.0, 0.0)
	beacon.call("set_urgency", 1.0)
	var seal := beacon.get_node_or_null("Seal") as Node3D
	var spin := seal.rotation.y if seal != null else 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	for part: String in ["Seal", "Cones", "Notices", "Label"]:
		_look(beacon.get_node_or_null(part) != null, "12 the beacon has %s" % part)
	_look(seal != null and not is_equal_approx(seal.rotation.y, spin), "12 the beacon's seal spins")
	var label := beacon.get_node_or_null("Label") as Label3D
	_look(label != null and label.text == str(_Strings.UI["beacon_label"]), "12 the beacon reads UI beacon_label")
	var notices := beacon.get_node_or_null("Notices")
	_look(notices != null and notices.get_child_count() == Constants.BEACON_NOTICES, "12 the beacon drops %d notices" % Constants.BEACON_NOTICES)
	beacon.call("dismiss")
	var waited := 0.0
	while is_instance_valid(beacon) and waited < Constants.BEACON_DISMISS_SECONDS + 1.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_look(not is_instance_valid(beacon), "12 a dismissed beacon folds away and is freed")
	print("[CastTest] step 12: the beacon spun, dropped notices and folded away in %.2f s" % waited)


## Steps 13-16 (cast:4): a raid on a real lot, with a client watching. Every NICE
## BOY wears the right outfit and name tag, the same on the client (CI compares
## probe.gd's crew_cast). Step 17, barks, comes with cast:6 (PHASE_C_BARKS).
func _phase_c() -> void:
	var before := _problems.size()
	# Step 13: a client.
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < CLIENT_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if Net.peer_ids().size() < 2:
		_fail("13 no client", "nobody joined in %d s" % int(CLIENT_WAIT_SECONDS))
		return
	print("[CastTest] step 13: a client joined")
	# Step 14: call the NICE BOYS and wait for them to arrive.
	var director := get_tree().get_first_node_in_group("run_director")
	if director == null:
		_fail("14 no director", "no run_director in the world")
		return
	# A full crew, so the networked check sees a plain NICE BOY's outfit and tags
	# past index 1, not only the head NICE BOY's.
	var heat := get_tree().get_first_node_in_group("heat")
	if heat != null:
		heat.call("add", 100.0, "test")
	# Q1 (cast:3): a quip player of the test's own (automated runs have no HUD, so
	# no UIRoot/Quips) watches the director from before the call.
	var quips: Node = _QuipPlayer.new()
	quips.name = "CastQuips"
	add_child(quips)
	await get_tree().process_frame
	await get_tree().process_frame
	director.call("force_event")
	var coming := str(director.call("status_line"))
	_look(coming == str(_Strings.UI["status_crew_coming"]), "Q1 the warning's status is UI status_crew_coming, not '%s'" % coming)
	waited = 0.0
	var limit := Constants.RUN_WARNING_SECONDS + 4.0
	while get_tree().get_nodes_in_group("crew").is_empty() and waited < limit:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var crew := get_tree().get_nodes_in_group("crew")
	if crew.is_empty():
		_fail("14 no crew", "nobody arrived %d s after the call" % int(limit))
		quips.queue_free()
		return
	var here := str(director.call("status_line"))
	_look(here == str(_Strings.UI["status_crew_here"]), "Q1 the arrival's status is UI status_crew_here, not '%s'" % here)
	# The quip player reads the director's phase, not its text: the warning plays
	# its run_warning line and the arrival its crew_arrival line (Q-009, which the
	# old "is here" match never played).
	var played: Dictionary = quips.get("_played")
	for trigger: String in ["run_warning", "crew_arrival"]:
		var id := _quip_id(trigger)
		_look(id != "" and int(played.get(id, 0)) >= 1, "Q1 the %s quip (%s) played; played: %s" % [trigger, id, JSON.stringify(played)])
	print("[CastTest] Q1: status '%s' then '%s'; quips played %s" % [coming, here, JSON.stringify(played)])
	quips.queue_free()
	# Step 15: frozen where they stand, so nobody is caught and they don't leave.
	for member: Node in crew:
		member.set("_stun_left", 60.0)
	print("[CastTest] step 14-15: %d NICE BOYS arrived, frozen" % crew.size())
	_look(crew.size() == Constants.HEAT_MAX_CREW, "14 a full-heat raid brings %d NICE BOYS, not %d" % [Constants.HEAT_MAX_CREW, crew.size()])
	# W6 (cast:2): the raid counts toward the day summary's "raided" quip.
	var raids := float((Campaign.get("_day_tally") as Dictionary).get("raids", 0.0))
	_wire(raids >= 1.0, "W6 the raid is tallied for the day summary (Campaign.note_day 'raids' is %.0f)" % raids)
	# Let the spawn reach the client before the reports are written.
	await get_tree().create_timer(CREW_SETTLE_SECONDS).timeout
	# Step 14b (cast:5): the van pulled up with them and is parked at the curb.
	if PHASE_B_VAN:
		var arrival := get_tree().get_first_node_in_group("van_arrival")
		var parked := str(arrival.call("state_name")) if arrival != null else "(no van_arrival)"
		var van_look: Node3D = arrival.call("van_look") if arrival != null else null
		var park: Vector3 = director.call("van_park_point")
		var off := van_look.global_position.distance_to(park) if van_look != null else -1.0
		_look(parked == "parked" and van_look != null and off < 0.05, "14b the NICE BOYS' van is parked at the curb (%s, %.2f m off)" % [parked, off])
		print("[CastTest] step 14b: the van is %s, %.3f m from its parking spot" % [parked, off])
	# Step 16: outfit, name tag, no capsule. The day must not be 1, the client's
	# default before the host's state arrives, or a client that ignored the
	# replicated day would still show the same tags (CI passes --start-day=7).
	var clock := get_tree().get_first_node_in_group("day_clock")
	var day := int(clock.get("day")) if clock != null else 1
	_look(day != 1, "16 the raid is on day %d; run with --start-day=N (N > 1) so the tags prove the client got the host's day" % day)
	for member: Node in get_tree().get_nodes_in_group("crew"):
		var index := int(member.call("crew_index"))
		var body := member.get_node_or_null("Visual/CartoonBody")
		var label := member.get_node_or_null("Visual/Label") as Label3D
		var capsule := member.get_node_or_null("Visual/Body") as Node3D
		var want := "nice_boy_lead" if index == 1 else "nice_boy"
		_look(body != null and str(body.get("outfit")) == want, "16 %s wears %s" % [member.name, want])
		var tag := _Strings.crew_tag(index, day)
		_look(label != null and label.text == tag, "16 %s's tag reads '%s', not '%s'" % [member.name, tag, label.text if label != null else "(no label)"])
		_look(capsule == null or not capsule.visible, "16 %s's placeholder capsule is hidden" % member.name)
		cast[str(member.name)] = {"tag": label.text if label != null else "", "outfit": str(body.get("outfit")) if body != null else ""}
	if PHASE_C_BARKS:
		pass # Step 17 (barks reach the client) comes with cast:6.
	print("[CastTest] steps 13-16, the crew on a client: %s %s" % [_problems.size() == before, JSON.stringify(cast)])


## The workbook quip (Strings.LINES) id for a trigger, or "".
func _quip_id(trigger: String) -> String:
	for row: Dictionary in _Strings.LINES:
		if str(row["trigger"]) == trigger:
			return str(row["id"])
	return ""


## Triangles drawn under root: every MeshInstance3D's faces.
func _triangles(root: Node) -> int:
	var total := 0
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			total += mesh.get_faces().size() / 3
	return total


func _look(condition: bool, what: String) -> void:
	if not condition:
		_fail("look", what)


func _fail(rule: String, detail: String) -> void:
	_problems.append("%s: %s" % [rule, detail])
	print("[CastTest] FAIL %s: %s" % [rule, detail])


func _compile() -> void:
	for pattern: String in PLACEHOLDER_PATTERNS:
		_placeholders.append(_regex(pattern))
	_slot = _regex(SLOT_PATTERN)
	# The guardrail's own samples (Guardrail.SHOULD_HIT and SHOULD_PASS), then the
	# cast's: each bad sample must trip it, no good sample may.
	for failure: Variant in _Guardrail.self_check():
		_fail("0 guardrail self-check", str(failure))
	for bad: String in ["Here comes ICE.", "the Nice Boys", "Papers, please!", "an ice cream van", "the police"]:
		if _Guardrail.is_clean(bad):
			_fail("0 guardrail misses", bad)
	for bad: String in ["Hi [CLERK NAME]", "Hi [NAME]", "a stand-in line", "TODO: joke"]:
		if not _trips(_placeholders, bad):
			_fail("0 unfinished misses", bad)
	for good: String in ["the NICE BOYS", "Nice work, nice boys.", "COURTESY NOTICE", "Another happy customer!", "[E]  %s"]:
		if not _Guardrail.is_clean(good) or _trips(_placeholders, good):
			_fail("0 pattern too eager", good)
	if _slots("%s at %d, %.1f%% and 25% more") != 3:
		_fail("0 slot count", "%s at %d, %.1f%% and 25% more")
	print("[CastTest] %d guardrail patterns (net/dev/guardrail.gd), checked against samples" % _Guardrail.PATTERNS.size())


func _trips(patterns: Array[RegEx], text: String) -> bool:
	for regex: RegEx in patterns:
		if regex.search(text) != null:
			return true
	return false


func _regex(pattern: String) -> RegEx:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		_fail("bad pattern", pattern)
	return regex


# ---------------------------------------------------------------- phase A, steps 1-5


## Steps 1-3 and 5 over every string and pool. Returns (strings, pools) checked.
func _audit_table() -> Vector2i:
	var leaves: Array = []
	var pools: Array = []
	var constants := (_Strings as Script).get_script_constant_map()
	for key: String in constants:
		_walk(constants[key], key, leaves, pools)
	for leaf: Array in leaves:
		var path := str(leaf[0])
		var text := str(leaf[1])
		if text.strip_edges() == "":
			_fail("1 empty", path)
			continue
		for regex: RegEx in _placeholders:
			if regex.search(text) != null:
				_fail("2 unfinished", "%s: %s" % [path, text])
		for hit: Variant in _Guardrail.check(text):
			_fail("5 guardrail %s" % str(hit), "%s: %s" % [path, text])
		var exact: Variant = _Strings.FORMAT_ARGS.get(path)
		if exact is Array and _slots(text) != int(exact[0]):
			_fail("3 slots", "%s wants %d, has %d: %s" % [path, int(exact[0]), _slots(text), text])
	for pool: Array in pools:
		var path := str(pool[0])
		var lines: Array = pool[1]
		var rule := _format_rule(path)
		if lines.size() < int(rule[1]):
			_fail("3 too few lines", "%s has %d, wants %d" % [path, lines.size(), int(rule[1])])
		var seen: Dictionary = {}
		for line: Variant in lines:
			var text := str(line)
			if seen.has(text):
				_fail("3 repeated line", "%s: %s" % [path, text])
			seen[text] = true
			if _slots(text) != int(rule[0]):
				_fail("3 slots", "%s wants %d, has %d: %s" % [path, int(rule[0]), _slots(text), text])
	print("[CastTest] steps 1-3, 5: %d strings and %d pools read" % [leaves.size(), pools.size()])
	return Vector2i(leaves.size(), pools.size())


## Collects every string (path, text) and every pool, an array of strings (path, lines).
func _walk(value: Variant, path: String, leaves: Array, pools: Array) -> void:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			leaves.append([path, str(value)])
		TYPE_DICTIONARY:
			var table: Dictionary = value
			for key: Variant in table:
				_walk(table[key], "%s/%s" % [path, str(key)], leaves, pools)
		TYPE_ARRAY:
			var list: Array = value
			var all_text := true
			for item: Variant in list:
				all_text = all_text and (item is String or item is StringName)
			if all_text:
				pools.append([path, list])
			for index: int in list.size():
				_walk(list[index], "%s/%d" % [path, index], leaves, pools)


## The FORMAT_ARGS entry for a pool: its own, else the nearest one above it.
func _format_rule(path: String) -> Array:
	var probe := path
	while probe != "":
		var rule: Variant = _Strings.FORMAT_ARGS.get(probe)
		if rule is Array:
			return rule
		var cut := probe.rfind("/")
		probe = probe.substr(0, cut) if cut >= 0 else ""
	return DEFAULT_FORMAT


func _slots(text: String) -> int:
	return _slot.search_all(text.replace("%%", "")).size()


# ---------------------------------------------------------------- phase A, step 4


func _coverage() -> void:
	var before := _problems.size()
	var personalities: Array = _Hoods.PERSONALITIES.keys()
	var moods: Array = (_constant("res://npcs/homeowner.gd", "STAGING", {}) as Dictionary).keys()
	_need(not moods.is_empty(), "npcs/homeowner.gd STAGING has moods")
	for personality: Variant in personalities:
		var by_mood: Dictionary = _Strings.PERSONALITY_LINES.get(personality, {})
		for mood: Variant in moods:
			_need(by_mood.has(mood), "PERSONALITY_LINES/%s/%s" % [personality, mood])
		_need(_Strings.PERSONALITY_BLURBS.has(personality), "PERSONALITY_BLURBS/%s" % personality)
		_need((_Strings.TEXT_LINES["request"] as Dictionary).has(personality), "TEXT_LINES/request/%s" % personality)
	for mood: Variant in moods:
		_need(_Strings.HOMEOWNER_LINES.has(mood), "HOMEOWNER_LINES/%s" % mood)
	for pool: String in BILL_POOLS:
		_need(_Strings.HOMEOWNER_LINES.has(pool), "HOMEOWNER_LINES/%s" % pool)
	_need((_Strings.TEXT_LINES["request"] as Dictionary).has("generic"), "TEXT_LINES/request/generic")
	for kind: String in TEXT_KINDS:
		_need(_Strings.TEXT_LINES.has(kind), "TEXT_LINES/%s" % kind)
	var triggers: Array = _constant("res://npcs/store_clerk.gd", "TRIGGERS", DEFAULT_KEEPER_TRIGGERS)
	_need(_Strings.KEEPER_LINES.has("marty"), "KEEPER_LINES/marty")
	for keeper: Variant in _Strings.KEEPER_LINES:
		for trigger: Variant in triggers:
			_need((_Strings.KEEPER_LINES[keeper] as Dictionary).has(trigger), "KEEPER_LINES/%s/%s" % [keeper, trigger])
	for kind: Variant in _constant("res://npcs/crew_member.gd", "BARK_KINDS", DEFAULT_BARK_KINDS):
		_need(_Strings.CREW_BARKS.has(kind), "CREW_BARKS/%s" % kind)
	for kind: String in CUE_KINDS:
		_need(_Strings.CUE_LINES.has(kind), "CUE_LINES/%s" % kind)
	for rank: String in _Ranks.NAMES:
		_need(_Strings.RANK_BLURBS.has(rank), "RANK_BLURBS/%s" % rank)
	_need(_Strings.RANK_BLURBS.has(_Ranks.ENDLESS_NAME), "RANK_BLURBS/%s" % _Ranks.ENDLESS_NAME)
	for bucket: String in _Strings.QUIP_BUCKETS:
		_need(_Strings.SUMMARY_QUIPS.has(bucket), "SUMMARY_QUIPS/%s" % bucket)
	for hood: Dictionary in _Hoods.HOODS:
		_need(_Strings.HOOD_BLURBS.has(str(hood["id"])), "HOOD_BLURBS/%s" % hood["id"])
	_need(_Strings.SEASON_NAMES.size() == 4, "SEASON_NAMES has 4 seasons")
	_need(_Strings.SEASON_ARRIVALS.size() == 4, "SEASON_ARRIVALS has 4 seasons")
	# The NICE BOYS' names: enough of them, and none a homeowner's.
	var unique: Dictionary = {}
	for crew_name: String in _Strings.CREW_NAMES:
		unique[crew_name.to_lower()] = true
	_need(unique.size() >= 8, "CREW_NAMES has 8 different names")
	for first: String in _Hoods.FIRST_NAMES:
		_need(not unique.has(first.to_lower()), "CREW_NAMES leaves out the homeowner name %s" % first)
	# Every unlock reads as words.
	var unlocks: Array = _Ranks.UNLOCKS.duplicate()
	var extra: Variant = (_Ranks as Script).get_script_constant_map().get("EXTRA_UNLOCKS")
	# shops:1's EXTRA_UNLOCKS is tier -> Array of unlock ids: check the ids, not the tiers.
	if extra is Dictionary:
		for ids: Variant in (extra as Dictionary).values():
			if ids is Array:
				unlocks.append_array(ids as Array)
			else:
				unlocks.append(ids)
	elif extra is Array:
		unlocks.append_array(extra)
	# "kind:id" left in the text means the name fell through; "hiring: crew hands" is prose.
	# An underscore means a raw id leaked in ("the leaf_blower_mk2 at Homie Depot").
	var id_like := _regex("[a-z_]+:[a-z_]+")
	for unlock: Variant in unlocks:
		var id := str(unlock)
		var named := _Strings.unlock_name(id)
		_need(named != id and id_like.search(named) == null and not named.contains("_"),
				"unlock_name(%s) reads as words, not \"%s\"" % [id, named])
	for task: Variant in Constants.TASK_TOOLS:
		_need(_Strings.UI.has("task_%s" % task), "UI/task_%s" % task)
	for tool: Variant in Constants.TOOL_PRICES:
		_need(_Strings.UI.has("tool_%s" % tool), "UI/tool_%s" % tool)
		_need(_Strings.UI.has("tool_blurb_%s" % tool), "UI/tool_blurb_%s" % tool)
	print("[CastTest] step 4, coverage: %s" % (_problems.size() == before))


func _need(condition: bool, what: String) -> void:
	if not condition:
		_fail("4 missing", what)


## A constant from another script, or the fallback when it has none (yet).
func _constant(path: String, key: String, fallback: Variant) -> Variant:
	if not ResourceLoader.exists(path):
		return fallback
	var value: Variant = (load(path) as Script).get_script_constant_map().get(key)
	return value if value != null else fallback


# ---------------------------------------------------------------- phase A, steps 7-8


func _api() -> void:
	var before := _problems.size()
	# Step 7: pool ids.
	_check(_Strings.homeowner_pool("grumpy/slow") == _Strings.PERSONALITY_LINES["grumpy"]["slow"], "7 homeowner_pool('grumpy/slow') is the grumpy slow pool")
	_check(_Strings.homeowner_pool("bill_hose") == _Strings.HOMEOWNER_LINES["bill_hose"], "7 homeowner_pool('bill_hose') is the hose bill pool")
	_check(_Strings.homeowner_pool("thrilled") == _Strings.HOMEOWNER_LINES["thrilled"], "7 homeowner_pool('thrilled') is the thrilled pool")
	_check(_Strings.homeowner_pool("nobody/nothing") == [""] and _Strings.homeowner_pool("bill_moon") == [""], "7 an unknown pool is ['']")
	# Step 8: the day summary's quip.
	var cases: Array = [
		[{"day": 3, "jobs": 0}, "zero"],
		[{"day": 3, "jobs": 2, "stars": 10.0, "raids": 1}, "raided"],
		[{"day": 3, "jobs": 2, "stars": 9.0}, "great"],
		[{"day": 3, "jobs": 1, "stars": 5.0}, "solid"],
		[{"day": 3, "jobs": 3, "stars": 6.0}, "rough"],
	]
	for row: Array in cases:
		var summary: Dictionary = row[0]
		var bucket := str(row[1])
		var line := _Strings.summary_quip(summary)
		_check(_Strings.quip_bucket(summary) == bucket, "8 %s reads as a %s day" % [JSON.stringify(summary), bucket])
		_check(line == _Strings.summary_quip(summary) and (_Strings.SUMMARY_QUIPS[bucket] as Array).has(line), "8 the %s quip is the same line twice: %s" % [bucket, line])
	# The rest of the API later chunks lean on.
	var tag := _Strings.crew_tag(1, 5)
	_check(tag == _Strings.crew_tag(1, 5) and tag.begins_with("HEAD NICE BOY "), "crew_tag(1, day) is the head NICE BOY: %s" % tag)
	_check(_Strings.crew_tag(2, 5).begins_with("NICE BOY "), "crew_tag(2, day) is a NICE BOY: %s" % _Strings.crew_tag(2, 5))
	# No two crew in one raid share a name, and the roster changes day to day.
	var repeats: Array[int] = []
	var firsts: Dictionary = {}
	for day: int in range(1, 101):
		var names: Dictionary = {}
		for index: int in range(1, 4):
			names[_Strings.crew_tag(index, day).get_slice(" ", _Strings.crew_tag(index, day).get_slice_count(" ") - 1)] = true
		if names.size() != 3:
			repeats.append(day)
		firsts[_Strings.crew_tag(1, day)] = true
	_check(repeats.is_empty(), "crew_tag(1..3, day) are three different names on days 1-100; repeats on %s" % str(repeats))
	_check(firsts.size() >= 4, "crew_tag(1, day) changes across days (%d different heads in 100 days)" % firsts.size())
	_check(_Strings.rank_blurb(0) == _Strings.RANK_BLURBS["Rake Rookie"] and _Strings.rank_blurb(_Ranks.TIERS_PER_RANK) == _Strings.RANK_BLURBS["Leaf Grunt"], "rank_blurb at a rank's tier I is the rank's")
	var endless := _Ranks.NAMES.size() * _Ranks.TIERS_PER_RANK
	_check(_Strings.rank_blurb(endless) == _Strings.RANK_BLURBS[_Ranks.ENDLESS_NAME], "rank_blurb at the first Lawnfather tier is The Lawnfather's")
	_check(_Strings.rank_blurb(1) == _Strings.TIER_BLURBS[0] and _Strings.rank_blurb(4) == _Strings.TIER_BLURBS[3] and _Strings.TIER_BLURBS.has(_Strings.rank_blurb(endless + 3)), "rank_blurb at tiers II to V, and Lawnfather stars, is a tier blurb")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var request: Dictionary = _Strings.TEXT_LINES["request"]
	_check((request["grumpy"] as Array).has(_Strings.client_line("request", "grumpy", rng)), "client_line('request', 'grumpy') is a grumpy request")
	_check((request["generic"] as Array).has(_Strings.client_line("request", "", rng)), "client_line('request', '') is a generic request")
	_check((_Strings.TEXT_LINES["hire_fired"] as Array).has(_Strings.client_line("hire_fired", "grumpy", rng)), "client_line of a kind with one pool uses it")
	_check(_Strings.pick_seeded(["a", "b", "c"], -7) == "c" and _Strings.pick_seeded([], 3) == "", "pick_seeded wraps any seed into the pool")
	print("[CastTest] steps 7-8, the strings API: %s" % (_problems.size() == before))


func _check(condition: bool, what: String) -> void:
	if not condition:
		_fail("api", what)


# ---------------------------------------------------------------- phase A, steps W1-W5


## Steps W1-W5 (cast:2): the lines are wired into the game, on the host.
func _wiring() -> void:
	var before := _problems.size()
	# W1: Marty picks his line by what's happening, and shows it over his head.
	var clerk := get_tree().get_first_node_in_group("store_clerk")
	_wire(clerk != null, "W1 Marty is in the world")
	if clerk != null:
		var marty: Dictionary = _Strings.KEEPER_LINES["marty"]
		var clock := get_tree().get_first_node_in_group("day_clock")
		var morning := clock != null and float(clock.call("hour")) < Constants.CLERK_MORNING_UNTIL_HOUR
		_wire(not morning or str(clerk.call("greet_trigger")) == "morning", "W1 the day's first greet before noon is 'morning', not '%s'" % clerk.call("greet_trigger"))
		clerk.call("_greet")
		var quiet := clock != null and bool(clock.call("is_quiet_hours"))
		_wire(str(clerk.call("greet_trigger")) == ("night" if quiet else "greet"), "W1 the next greet is '%s', not '%s'" % ["night" if quiet else "greet", clerk.call("greet_trigger")])
		clerk.call("_on_zone_changed", Net.local_peer_id(), Net.Zone.BORDER)
		_wire(str(clerk.call("greet_trigger")) == "after_raid", "W1 a greet after a trip over the border is 'after_raid', not '%s'" % clerk.call("greet_trigger"))
		clerk.call("_greet")
		_wire(str(clerk.call("greet_trigger")) != "after_raid", "W1 'after_raid' is said once")
		# A raid, then the next day's first greet before noon: "morning" wins, and the
		# after-raid line is kept for the greet after it, not lost.
		clerk.call("_on_zone_changed", Net.local_peer_id(), Net.Zone.BORDER)
		clerk.set("_greeted_day", -1)
		var first := str(clerk.call("greet_trigger"))
		_wire(first == ("morning" if morning else "after_raid"), "W1 a new day's first greet after a raid is '%s', not '%s'" % ["morning" if morning else "after_raid", first])
		clerk.call("_greet")
		if first == "morning":
			_wire(str(clerk.call("greet_trigger")) == "after_raid", "W1 a morning greet keeps the after-raid line for the next greet, not '%s'" % clerk.call("greet_trigger"))
			clerk.call("_greet")
		_wire(str(clerk.get("last_trigger")) == "after_raid" and str(clerk.call("greet_trigger")) != "after_raid", "W1 the after-raid line was said, once")
		var shops := get_tree().get_first_node_in_group("shops")
		var open := shops == null or bool(shops.call("is_open", "homie_depot"))
		_wire(str(clerk.call("open_trigger")) == ("open" if open else "closed"), "W1 opening the window says '%s'" % ("open" if open else "closed"))
		var caption := clerk.get_node_or_null("Caption") as Label3D
		for trigger: Variant in _constant("res://npcs/store_clerk.gd", "TRIGGERS", DEFAULT_KEEPER_TRIGGERS):
			clerk.call("say_line", trigger)
			var said := str(clerk.get("last_line"))
			_wire((marty.get(trigger, []) as Array).has(said), "W1 Marty's '%s' line is one of his: '%s'" % [trigger, said])
			_wire(caption != null and caption.text == said, "W1 Marty's caption shows his '%s' line" % trigger)
	# W2: the town's texts come from the pools: Marty's welcome, then requests in
	# each client's own voice, with their address.
	var town := get_tree().get_first_node_in_group("town")
	_wire(town != null, "W2 the town is in the world")
	if town != null:
		var texts: Array = town.get("texts")
		var intro := false
		var requests := 0
		for entry: Variant in texts:
			var text: Dictionary = entry
			var kind := str(text.get("kind", ""))
			if kind == "intro":
				intro = str(text.get("from", "")) == _Strings.UI["clerk_name"] and (_Strings.TEXT_LINES["clerk_intro"] as Array).has(str(text.get("text", "")))
			elif kind == "request":
				requests += 1
				var house_id := int(text.get("house", -1))
				var owner: Dictionary = (town.call("house", house_id) as Dictionary).get("owner", {})
				var by: Dictionary = _Strings.TEXT_LINES["request"]
				var pool: Array = by.get(str(owner.get("personality", "")), by["generic"])
				var address := str(town.call("address", house_id))
				var found := false
				for line: Variant in pool:
					found = found or str(line) % address == str(text.get("text", ""))
				_wire(found, "W2 %s's request is in their %s voice: %s" % [text.get("from", ""), owner.get("personality", "generic"), text.get("text", "")])
		_wire(intro, "W2 Marty's welcome text is from %s and in TEXT_LINES.clerk_intro" % _Strings.UI["clerk_name"])
		_wire(requests > 0, "W2 there are request texts to check")
		var section: Dictionary = (town.call("_save_section") as Dictionary).get("town", {})
		_wire(section.has("rival_announced"), "W2 the town save has rival_announced")
	# W3: run cues are picked from the phase's start, the same line every time.
	for kind: String in ["radio", "arrived", "clear"]:
		var line := _RunCues.cue_line(kind, 1234.567)
		_wire(line == _RunCues.cue_line(kind, 1234.567) and (_Strings.CUE_LINES[kind] as Array).has(line), "W3 the %s cue is a CUE_LINES line, the same twice: %s" % [kind, line])
	# W4: the day summary card shows the quip and each rank-up's blurb.
	var card := get_tree().get_first_node_in_group("day_summary")
	_wire(card != null, "W4 the day summary card exists")
	if card != null:
		var summary := {"day": 7, "jobs": 2, "stars": 10.0, "raids": 1.0, "title": "Leaf Grunt I",
			"rank_ups": [{"tier": _Ranks.TIERS_PER_RANK, "title": "Leaf Grunt I", "unlock": "", "extras": []}]}
		card.call("show_summary", summary)
		var shown: Array[String] = []
		for label: Node in card.find_children("*", "Label", true, false):
			if not label.is_queued_for_deletion():
				shown.append((label as Label).text)
		_wire(shown.has(_Strings.summary_quip(summary)), "W4 the summary shows the raided quip: %s" % _Strings.summary_quip(summary))
		_wire(shown.has(_Strings.rank_blurb(_Ranks.TIERS_PER_RANK)), "W4 the summary shows Leaf Grunt's blurb")
		card.call("close_window")
	# W5: hired hands are never named for a nationality.
	var hire_names: Array = _constant("res://net/crew/hires.gd", "NAMES", [])
	_wire(not hire_names.is_empty() and not hire_names.has("Dutch"), "W5 the hire nicknames have no 'Dutch'")
	# Q2 (cast:3): the quip player asks the crossing whether you were thrown back,
	# instead of matching its status text.
	var crossing := get_tree().get_first_node_in_group("border_return")
	_wire(crossing != null and crossing.has_method("is_thrown_back") and not bool(crossing.call("is_thrown_back")), "Q2 the border crossing says is_thrown_back() (false with nobody crossing)")
	if crossing != null and crossing.has_method("is_thrown_back"):
		_throwback(crossing)
	# Q3 (cast:3): text that moved out of game code reads the same through its new home.
	_wire(_Seasons.name_of(0) == _Strings.SEASON_NAMES[0] and _Seasons.name_of(5) == _Strings.SEASON_NAMES[1], "Q3 Seasons.name_of() reads Strings.SEASON_NAMES")
	for hood: Dictionary in _Hoods.HOODS:
		_wire(not hood.has("blurb"), "Q3 %s's blurb lives in Strings.HOOD_BLURBS, not neighborhoods.gd" % hood["id"])
	for personality: Variant in _Hoods.PERSONALITIES:
		_wire(not (_Hoods.PERSONALITIES[personality] as Dictionary).has("blurb"), "Q3 %s's blurb lives in Strings.PERSONALITY_BLURBS" % personality)
	_homeowner_pools()
	print("[CastTest] steps W1-W5 and W7, the lines in the game: %s" % (_problems.size() == before))


## Q2 (cast:3): is_thrown_back() is true only while the local player is running
## and was thrown back, and a quip player watching it plays the border_fail line
## once per throw. Done in one frame on the real crossing, whose state is put back
## before its _process can see it.
func _throwback(crossing: Node) -> void:
	var saved := {}
	for field: String in ["_running", "_local_done", "_threw_back"]:
		saved[field] = crossing.get(field)
	crossing.set("_running", true)
	crossing.set("_local_done", false)
	crossing.set("_threw_back", true)
	_wire(bool(crossing.call("is_thrown_back")), "Q2 is_thrown_back() is true while running and thrown back")
	var quips: Node = _QuipPlayer.new()
	quips.name = "CastThrowQuips"
	add_child(quips)
	quips.call("_watch_throwback")
	quips.call("_watch_throwback")
	var id := _quip_id("border_fail")
	var played: Dictionary = quips.get("_played")
	_wire(id != "" and int(played.get(id, 0)) == 1, "Q2 a throw-back plays the border_fail quip (%s) once; played: %s" % [id, JSON.stringify(played)])
	crossing.set("_local_done", true)
	_wire(not bool(crossing.call("is_thrown_back")), "Q2 is_thrown_back() is false once the local player is done")
	crossing.set("_local_done", false)
	crossing.set("_threw_back", false)
	_wire(not bool(crossing.call("is_thrown_back")), "Q2 is_thrown_back() is false while running without a throw-back")
	for field: String in saved:
		crossing.set(field, saved[field])
	remove_child(quips)
	quips.queue_free()


## Step W7: the homeowner's reaction pool (npcs/homeowner.gd choose_pool), rolled
## with a seeded rng: a homeowner with a personality talks like themselves about as
## often as Constants says, a water-only bill comes up, breakage comes first, and
## every pool picked resolves to real lines.
func _homeowner_pools() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	var mood := "happy"
	var personality := str(_Strings.PERSONALITY_LINES.keys()[0])
	var own: Array = _Strings.PERSONALITY_LINES[personality][mood]
	# A homeowner with a personality and nothing owed.
	var spoke_own := 0
	var stray: Array[String] = []
	for roll: int in POOL_ROLLS:
		var pool := _Homeowner.choose_pool(mood, {}, 0, personality, rng)
		if pool == "%s/%s" % [personality, mood] and _Strings.homeowner_pool(pool) == own:
			spoke_own += 1
		elif pool != mood:
			stray.append(pool)
	var share := float(spoke_own) / float(POOL_ROLLS)
	_wire(stray.is_empty(), "W7 a %s homeowner owed nothing says a %s or %s/%s line, not %s" % [personality, mood, personality, mood, str(stray.slice(0, 3))])
	_wire(absf(share - Constants.HOMEOWNER_PERSONALITY_LINE_CHANCE) < 0.1, "W7 a %s homeowner talks like themselves %.2f of the time (Constants: %.2f)" % [personality, share, Constants.HOMEOWNER_PERSONALITY_LINE_CHANCE])
	# No personality (a test yard): always the mood's pool.
	var plain := true
	for roll: int in POOL_ROLLS:
		plain = plain and _Homeowner.choose_pool(mood, {}, 0, "", rng) == mood
	_wire(plain, "W7 a homeowner with no personality says a %s line" % mood)
	# Owed only for water: bill_water about as often as Constants says; never with no fee.
	var water := 0
	var water_free := true
	for roll: int in POOL_ROLLS:
		var pool := _Homeowner.choose_pool(mood, {}, 25, personality, rng)
		if pool == "bill_water":
			water += 1
		water_free = water_free and _Homeowner.choose_pool(mood, {}, 0, personality, rng) != "bill_water"
	var water_share := float(water) / float(POOL_ROLLS)
	_wire(not _Strings.homeowner_pool("bill_water").is_empty() and str(_Strings.homeowner_pool("bill_water")[0]) != "", "W7 there are bill_water lines")
	_wire(absf(water_share - Constants.HOMEOWNER_WATER_LINE_CHANCE) < 0.1, "W7 a water-only bill comes up %.2f of the time (Constants: %.2f)" % [water_share, Constants.HOMEOWNER_WATER_LINE_CHANCE])
	_wire(water_free, "W7 no water fee, no bill_water line")
	# Breakage owed: that bill first, about as often as Constants says; never water.
	var hose := 0
	var hose_water := false
	for roll: int in POOL_ROLLS:
		var pool := _Homeowner.choose_pool(mood, {"hose": 40}, 25, personality, rng)
		hose += 1 if pool == "bill_hose" else 0
		hose_water = hose_water or pool == "bill_water"
	var hose_share := float(hose) / float(POOL_ROLLS)
	_wire(absf(hose_share - Constants.HOMEOWNER_BILL_LINE_CHANCE) < 0.1 and not hose_water, "W7 a broken hose comes up %.2f of the time (Constants: %.2f), never the water" % [hose_share, Constants.HOMEOWNER_BILL_LINE_CHANCE])
	# Nothing delivered: never a bill, whatever is owed.
	var nothing := true
	for roll: int in POOL_ROLLS:
		var pool := _Homeowner.choose_pool("nothing", {"hose": 40}, 25, personality, rng)
		nothing = nothing and not pool.begins_with("bill_")
	_wire(nothing, "W7 a homeowner who got nothing never brings up a bill")
	# Every personality x mood the host can pick names a real pool.
	var missing: Array[String] = []
	for each: Variant in _Strings.PERSONALITY_LINES.keys():
		for staged: Variant in (_constant("res://npcs/homeowner.gd", "STAGING", {}) as Dictionary).keys():
			var lines: Array = _Strings.homeowner_pool("%s/%s" % [each, staged])
			if lines.is_empty() or str(lines[0]) == "":
				missing.append("%s/%s" % [each, staged])
	_wire(missing.is_empty(), "W7 every personality/mood pool the host can pick has lines; missing %s" % str(missing))


func _wire(condition: bool, what: String) -> void:
	if not condition:
		_fail("wiring", what)


# ---------------------------------------------------------------- phase A, step 6


## Step 6: every sentence game code puts on screen itself fails the test (cast:3
## made it fail; before that it only reported). Move the text into ui/strings.gd
## and read it from there; canon brand names (SWEEP_ALLOW) may stay where painted.
## Since settings:4 it reads scenes too: a .tscn's text, placeholder_text or
## tooltip_text sentence fails the same way (the script sets it from Strings).
func _sweep_inline() -> Array[String]:
	var found: Array[String] = []
	var literal := _regex(SWEEP_LITERAL)
	var files: Array[String] = []
	for dir: String in SWEEP_DIRS:
		_list_scripts(dir, files)
	for path: String in files:
		var skip := false
		for prefix: String in SWEEP_SKIP:
			skip = skip or path.begins_with(prefix)
		if skip:
			continue
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for number: int in lines.size():
			var line := lines[number]
			if line.strip_edges().begins_with("#") or not _is_text_site(line):
				continue
			for hit: RegExMatch in literal.search_all(line):
				var text := hit.get_string().trim_prefix("\"").trim_suffix("\"")
				if SWEEP_ALLOW.has(text):
					continue
				found.append("%s:%d %s" % [path.trim_prefix("res://"), number + 1, hit.get_string()])
	# Scenes too (settings:4): a Label's or Button's words written into a .tscn.
	var scenes: Array[String] = []
	for dir: String in SWEEP_DIRS + SWEEP_SCENE_DIRS:
		_list_scripts(dir, scenes, ".tscn")
	for path: String in scenes:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for number: int in lines.size():
			var line := lines[number]
			if not _is_scene_text(line):
				continue
			for hit: RegExMatch in literal.search_all(line):
				var text := hit.get_string().trim_prefix("\"").trim_suffix("\"")
				if SWEEP_ALLOW.has(text):
					continue
				found.append("%s:%d %s" % [path.trim_prefix("res://"), number + 1, hit.get_string()])
	for entry: String in found:
		_fail("6 inline text", "%s (move it into ui/strings.gd)" % entry)
	print("[CastTest] step 6: %d inline sentences outside ui/strings.gd (%d scripts and %d scenes read)" % [found.size(), files.size(), scenes.size()])
	_need_sweep(scenes.size() > 5, "6 the sweep read the game's scenes (%d files)" % scenes.size())
	_need_sweep(files.size() > 50, "6 the sweep read the game's scripts (%d files)" % files.size())
	return found


func _need_sweep(condition: bool, what: String) -> void:
	if not condition:
		_fail("6 sweep", what)


func _is_text_site(line: String) -> bool:
	for site: String in SWEEP_SITES:
		if line.contains(site):
			return true
	return false


## A scene property that puts words on screen: text, placeholder_text, tooltip_text.
func _is_scene_text(line: String) -> bool:
	for property: String in SWEEP_SCENE_PROPERTIES:
		if line.begins_with(property + " = \""):
			return true
	return false


func _list_scripts(dir_path: String, out: Array[String], extension := ".gd") -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file: String in dir.get_files():
		if file.ends_with(extension):
			out.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		_list_scripts(dir_path.path_join(sub), out, extension)
