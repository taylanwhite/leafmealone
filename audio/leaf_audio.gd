class_name LeafAudio
extends Node

## Local presentation. The rake and leaf sounds (gap R1, chunk raking:5;
## docs/ART.md "Rake and leaf sounds"; gap-specs/raking.json contract C6; the
## timing and the mix: docs/GAME.md "Raking: what you hear, and when", R1b
## rakefeel:sound). A child of Sfx (audio/sfx.gd makes it), in group "leaf_audio".
##
## Every stroke the leaf field applies reaches every peer once as a stroke_event
## (raking:1, contract C1): on the raker it is the predicted bite, on the host the
## applied one, on everyone else the one that arrived. That event IS the moment
## the tines bite, and the rake on that peer is at the bite's phase of its swing
## (equipment/rake_stroke.gd: the raker's swing fires the bite on that tick,
## everyone else's is re-phased to it on receipt). So everything that belongs to
## a later moment of the swing is placed from the swing's own phases
## (Constants.RAKE_SWING_PHASES, RakeStroke.bites) and the event's tempo, never
## from a fixed delay, and counted down in physics ticks, the clock the swing
## itself runs on:
##   rake / crew_rake  first bite: the plant where the head lands, at the swing's
##                     "plant"; the scrape from the plant to "drive_end" (pitched
##                     to fill it; rake_empty on bare ground); every bite that
##                     moves enough leaves: a leaf layer (light / med / heavy)
##                     louder the more it moved; the last bite: the flick at
##                     "drive_end", ahead where the drive ends
##   hand              hand_scoop
##   bag / crew_bag    bag_open now, bag_stuff (louder for a bigger pile) as the
##                     leaves fly in, then bag_tie as they're all in, on every peer,
##                     the host too: the host's field asks world._spawn_bag for the
##                     bag before it tells the stroke, so world leaves the tie to
##                     this (owns_bag_tie) or the host would hear tie, open, stuff
##   scatter / plow    leaf_kick
##   blower / mulch    nothing (the blower and mower loops cover them)
## The leaf motion layer (raking:3) reports landings and kicks through the C5
## hooks on_settled and on_kick (call_group "leaf_audio"); both are no-ops for
## anyone who never calls them.
## Sfx.play_at starts each one in the mix at once (audio/sfx.gd _start_now), so a
## sound asked for from a network message or _process isn't a frame late.
## --audio-test drives this with synthetic events (net/dev/audio_test.gd, leaf_audio).
## Never touches gameplay state.

## The leaf layers by tier (light, medium, heavy), Constants.LEAF_SFX_TIERS.
const TIER_IDS: Array[String] = ["rake_leaves_light", "rake_leaves_med", "rake_leaves_heavy"]

var _field: Node = null
## Plays waiting for their moment: {"left" (game seconds to go), "frame" (the
## physics frame it was asked in), "id", "at", "db", "source", "pitch"}.
var _pending: Array[Dictionary] = []
## When the last leaf_settle sounds played (msec), for the per-second cap.
var _settles: Array[int] = []
## Area key -> the msec before which that area doesn't whump again.
var _whump_next: Dictionary = {}


func _ready() -> void:
	add_to_group("leaf_audio")


func _process(_delta: float) -> void:
	_hook()


## The swing advances in physics ticks (rake.gd, crew_hand.gd), so the plays
## that wait for a moment of it are counted down on the same ticks.
func _physics_process(delta: float) -> void:
	_flush(delta)


## Each job loads a new lot and leaf field, so hook whichever one is current.
func _hook() -> void:
	if _field != null and is_instance_valid(_field) and _field.is_inside_tree():
		return
	_field = null
	var field := get_tree().get_first_node_in_group("leaf_field")
	if field == null or not field.has_signal("stroke_event"):
		return
	_field = field
	if not field.is_connected("stroke_event", _on_stroke_event):
		field.connect("stroke_event", _on_stroke_event)


func _on_stroke_event(ev: Dictionary) -> void:
	handle(ev)


## True when this plays the bag tie for field's bags, so world._spawn_bag must
## not: field tells its strokes and a LeafAudio is listening. Before raking:1
## gives the field stroke_event, world keeps tying its own bags.
static func owns_bag_tie(field: Node) -> bool:
	if field == null or not field.is_inside_tree() or not field.has_signal("stroke_event"):
		return false
	return field.get_tree().get_first_node_in_group("leaf_audio") != null


# ---- the swing's moments


## A named moment of a swing ("plant", "drive_end", "flick_end"), as a fraction
## of it: the same table equipment/rake_stroke.gd draws the swing from.
static func swing_phase(point: String) -> float:
	return float(Constants.RAKE_SWING_PHASES.get(point, 0.0))


## The phase this bite of this kind of swing lands at (RakeStroke.bites).
static func bite_phase(bite: int, crew: bool) -> float:
	var list := RakeStroke.bites(crew)
	return list[clampi(bite, 0, list.size() - 1)]


## True for a swing's last bite (the one the flick follows).
static func is_last_bite(bite: int, crew: bool) -> bool:
	return bite >= RakeStroke.bites(crew).size() - 1


## Game seconds from this bite to the swing's phase point (0 when it's already
## past), for a swing tempo seconds long. actor: when this peer's swing for
## that actor is running near the bite's phase (the raker's own, which bites on
## the tick nearest its phase, so up to half a tick early), count from where it
## really is, so the play lands on the tick the swing reaches point.
static func after_bite(bite: int, crew: bool, tempo: float, point: float, actor: int = 0) -> float:
	var from := bite_phase(bite, crew)
	if actor != 0:
		var live := RakeStroke.phase_of(actor)
		if live >= 0.0 and absf(live - from) < Constants.LEAF_SFX_LIVE_PHASE_SLACK:
			from = live
	return maxf(0.0, (point - from) * tempo)


## How long the drive lasts in a swing this long (s): plant to drive_end.
static func drive_seconds(tempo: float) -> float:
	if tempo <= 0.0:
		tempo = Constants.LEAF_SFX_DEFAULT_TEMPO
	return maxf(0.05, (swing_phase("drive_end") - swing_phase("plant")) * tempo)


## The scrape's pitch for a swing this long (s): the scrape file stretched over
## the drive, within RAKE_SCRAPE_PITCH.
static func scrape_pitch(tempo: float) -> float:
	return clampf(Constants.RAKE_SCRAPE_SECONDS / drive_seconds(tempo), Constants.RAKE_SCRAPE_PITCH.x, Constants.RAKE_SCRAPE_PITCH.y)


## How loud count leaves landing or kicked sound (dB): base, louder by
## LEAF_SFX_DB_PER_DOUBLING each time the count doubles, never over 0.
static func count_db(base: float, count: int) -> float:
	return minf(0.0, base + Constants.LEAF_SFX_DB_PER_DOUBLING * log(float(maxi(count, 1))) / log(2.0))


## Plays one stroke event's sounds, the same on every peer.
func handle(ev: Dictionary) -> void:
	var kind := str(ev.get("kind", ""))
	var actor := int(ev.get("actor", 0))
	var at: Vector3 = ev.get("at", Vector3.ZERO)
	var moved := int(ev.get("moved", 0))
	match kind:
		"rake", "crew_rake":
			_rake(ev, kind == "crew_rake", actor, at, moved)
		"hand":
			if moved > 0:
				_play("hand_scoop", at, 0.0, actor)
		"bag", "crew_bag":
			_play("bag_open", at, 0.0, actor)
			_later(Constants.BAG_STUFF_DELAY, "bag_stuff", at, bag_stuff_db(moved), actor)
			_later(Constants.BAG_TIE_DELAY, "bag_tie", at, 0.0, actor)
		"scatter", "plow":
			_play("leaf_kick", at, 0.0, actor)
		_:
			pass


func _rake(ev: Dictionary, crew: bool, actor: int, at: Vector3, moved: int) -> void:
	var dir: Vector3 = ev.get("dir", Vector3.ZERO)
	var bite := int(ev.get("bite", 0))
	var tempo := float(ev.get("tempo", 0.0))
	if tempo <= 0.0:
		tempo = Constants.LEAF_SFX_DEFAULT_TEMPO
	var head := at
	if bite == 0:
		# The head lands short of the stroke's middle, then drives through it. The
		# first bite is at (or before) the plant (audio_test "sync" holds the swing
		# to that), so the plant is now, and the scrape runs from the plant.
		head = at - dir * Constants.LEAF_SFX_PLANT_BACK
		var to_plant := after_bite(bite, crew, tempo, swing_phase("plant"), actor)
		_later(to_plant, "rake_plant", head, 0.0, actor)
		_later(to_plant, "rake_scrape" if moved > 0 else "rake_empty", head, 0.0, actor, scrape_pitch(tempo))
	if moved >= Constants.LEAF_SFX_MIN_UNITS:
		_play(TIER_IDS[tier_of(moved)], head, leaf_gain_db(moved), actor)
	if is_last_bite(bite, crew) and moved > 0:
		_later(after_bite(bite, crew, tempo, swing_phase("drive_end"), actor), "leaf_flick", at + dir * Constants.LEAF_SFX_FLICK_AHEAD, 0.0, actor)


## Which leaf layer (0 light, 1 medium, 2 heavy) a stroke that moved this much gets.
static func tier_of(moved: int) -> int:
	var i := float(moved) / Constants.LEAF_SFX_REF_UNITS
	if i < Constants.LEAF_SFX_TIERS.x:
		return 0
	return 1 if i < Constants.LEAF_SFX_TIERS.y else 2


## The leaf layer's gain (dB): quieter the less it moved, a touch over at a big shove.
static func leaf_gain_db(moved: int) -> float:
	var i := float(moved) / Constants.LEAF_SFX_REF_UNITS
	return minf(lerpf(Constants.LEAF_SFX_GAIN_FLOOR_DB, 0.0, sqrt(minf(i, 1.2))), Constants.LEAF_SFX_GAIN_CAP_DB)


## The stuffing's gain (dB): a thin pile goes in softer, never as soft as the floor.
static func bag_stuff_db(moved: int) -> float:
	var full := clampf(float(moved) / Constants.BAG_STUFF_REF_UNITS, 0.0, 1.0)
	return lerpf(Constants.BAG_STUFF_FLOOR_DB, 0.0, sqrt(full))


## Footsteps by how deep the leaves are where the foot lands (for audio:6's foley).
static func step_id(density: int) -> String:
	if density < Constants.LEAF_STEP_DEEP_DENSITY:
		return "step_leaves"
	if density < Constants.LEAF_STEP_PILE_DENSITY:
		return "step_leaves_deep"
	return "step_leaves_pile"


## C5: count leaves just landed around at (onto a pile when onto_pile).
func on_settled(at: Vector3, count: int, onto_pile: bool) -> void:
	if count < Constants.LEAF_SETTLE_MIN:
		return
	var now := Time.get_ticks_msec()
	var key := Vector2i(floori(at.x / Constants.PILE_WHUMP_AREA), floori(at.z / Constants.PILE_WHUMP_AREA))
	while not _settles.is_empty() and now - _settles[0] >= 1000:
		_settles.pop_front()
	if _settles.size() < Constants.LEAF_SETTLE_PER_SECOND:
		_settles.append(now)
		_play("leaf_settle", at, count_db(Constants.LEAF_SETTLE_BASE_DB, count), _area_source(key))
	if not onto_pile or count < Constants.PILE_WHUMP_MIN:
		return
	if now < int(_whump_next.get(key, 0)):
		return
	_whump_next[key] = now + int(Constants.PILE_WHUMP_GAP * 1000.0)
	_play("pile_whump", at, 0.0, _area_source(key))


## C5: a player kicked or dove through count leaves at at.
func on_kick(at: Vector3, count: int) -> void:
	var key := Vector2i(floori(at.x / Constants.PILE_WHUMP_AREA), floori(at.z / Constants.PILE_WHUMP_AREA))
	_play("leaf_kick", at, count_db(Constants.LEAF_SFX_GAIN_FLOOR_DB, count), _area_source(key))


## A throttle key for a 2 m area of the yard (never 0, so areas don't share one).
static func _area_source(key: Vector2i) -> int:
	return 1 + posmod(key.x, 1000) * 1000 + posmod(key.y, 1000)


## How many plays are waiting for their time (tests).
func pending_count() -> int:
	return _pending.size()


## When the plays waiting now will start (tests): [{"id", "left"}], soonest first.
func pending() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _pending:
		out.append({"id": entry["id"], "left": entry["left"]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["left"]) < float(b["left"]))
	return out


func _play(id: String, at: Vector3, db: float, source: int, pitch := 1.0) -> void:
	var sfx := _sfx()
	if sfx != null:
		sfx.call("play_at", id, at, db, true, source, pitch)


## Plays id delay game seconds from now: at once when that is under half a
## physics tick, else on the physics tick nearest it.
func _later(delay: float, id: String, at: Vector3, db: float, source: int, pitch := 1.0) -> void:
	if delay < 0.5 / float(Engine.physics_ticks_per_second):
		_play(id, at, db, source, pitch)
		return
	_pending.append({"left": delay, "frame": Engine.get_physics_frames(), "id": id, "at": at, "db": db, "source": source, "pitch": pitch})


## One physics tick: everything whose moment is nearest this tick plays. A play
## asked for on this very tick (the raker's bite) only starts counting on the
## next, like the swing that asked for it.
func _flush(delta: float) -> void:
	if _pending.is_empty():
		return
	var frame := Engine.get_physics_frames()
	var keep: Array[Dictionary] = []
	var due: Array[Dictionary] = []
	for entry: Dictionary in _pending:
		if int(entry["frame"]) != frame:
			entry["left"] = float(entry["left"]) - delta
		if float(entry["left"]) <= 0.5 * delta:
			due.append(entry)
		else:
			keep.append(entry)
	_pending = keep
	for entry: Dictionary in due:
		_play(str(entry["id"]), entry["at"], float(entry["db"]), int(entry["source"]), float(entry["pitch"]))


func _sfx() -> Node:
	var parent := get_parent()
	if parent != null and parent.has_method("play_at"):
		return parent
	return get_tree().get_first_node_in_group("sfx")
