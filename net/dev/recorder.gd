extends Node

## Authority: local, dev only. The playtest recorder (docs/PLAYTEST.md): it
## records what this window shows as frames evenly spaced in GAME time, plus a
## log of everything that happened on each frame, so an agent can judge a moment
## by its motion and timing instead of one screenshot. net/dev/remote_play.gd
## drives it with the record_start, record_stop and record steps.
##
## Output, in <remote-play dir>/rec_<label>/:
##   frame_NNN.png  every frame (the window as drawn; headless runs draw a stand-in)
##   sheet.png      a contact sheet: up to SHEET_PAGE_TILES frames picked evenly,
##                  each stamped with its frame number and game time, flagged
##                  frames marked; sheet_01.png, sheet_02.png ... hold every frame
##   filmstrip.png  thumbnails on the same time axis as audio.png
##   events.json    per frame: the player, the camera, the HUD's text, what fired;
##                  plus every event with its time, and the automatic flags
##                  (pop, cam_cut, cam_snap, cam_frozen)
##   audio.wav      the real mix (an AudioEffectCapture on the Master bus, 32-bit
##                  float), streamed to disk while recording and kept in step with
##                  the wall clock: a stretch the audio thread never mixed (a
##                  starved or stalled audio thread) is written as silence where it
##                  happened, so the wav lasts as long as the frames and a sound
##                  after a dropout still lines up with its frame
##   audio.png      tools/playtest_audio.py draws it (tools/play.ps1 runs it):
##                  waveform, octave bands and sound markers under the filmstrip
##
## Writing never stalls the game (R2b tools): each frame goes to disk on a worker
## thread as it's captured, and record_stop only closes the take; the picture
## change, the flags it implies, the sheets, the filmstrip and events.json are
## written on a thread of their own while the game (and the network) keeps
## running. is_writing() says when that's still going; remote play waits for it
## before it answers, so a 3-minute take doesn't drop an observer ("Host left").
## A new take can start while the last one is still being written.
##
## Even spacing: launch the game with the engine's --fixed-fps N and the game's
## --fixed-step=N (tools/play.ps1 does): every frame then advances exactly 1/N s
## of game time however loaded the machine is (net/dev/pacer.gd holds it to
## real time, and Net's clock counts game time), and a recording at N/k fps
## keeps every k-th frame. Without them it records the first frame at or after
## each 1/fps step and says so (fixed_step false); spacing then wanders.
## Every event carries the game time of the frame it happened in, the same `t`
## as that frame's entry, whether it fired in a physics tick, in the network
## poll or in _process, and however the recording was started.

const _Sfx = preload("res://audio/sfx.gd")
## Contact sheet: at most this wide, in tiles of this size, this many per page.
const SHEET_MAX_WIDTH: int = 2048
const SHEET_TILE_WIDTH: int = 256
const SHEET_PAGE_TILES: int = 48
## The filmstrip's (and audio.png's) layout: left margin and timeline width, in pixels.
const FILM_MARGIN: int = 36
const FILM_WIDTH: int = 2000
const FILM_THUMB := Vector2i(160, 90)
## Frames being written by worker threads before the game waits for them.
const MAX_PENDING_SAVES: int = 10
## A stand-in frame's size in a headless run (nothing is drawn there).
const HEADLESS_FRAME := Vector2i(320, 180)
## Automatic flags. A watched thing that moves farther than POP_METERS in one
## frame, faster than its kind's speed limit, popped; the camera jumping farther
## than CAM_SNAP_METERS or turning more than CAM_SNAP_DEGREES in one frame
## snapped; a camera that keeps exactly still for CAM_FROZEN_SECONDS while the
## player is turning or walking is frozen.
const POP_METERS: float = 0.6
const POP_SPEED := {"player": 14.0, "crew": 14.0, "vehicle": 45.0}
const CAM_SNAP_METERS: float = 1.2
const CAM_SNAP_DEGREES: float = 50.0
const CAM_FROZEN_SECONDS: float = 0.5
## After a scenario places people (note_placement) or the spectator cuts to a
## teleported target (note_cut), this many frames aren't judged for pops and snaps.
const SETTLE_FRAMES: int = 3
## Picture change between frames: measured on copies this small; a frame whose
## change is CHANGE_SPIKE_TIMES the clip's median (and at least CHANGE_SPIKE_MIN)
## gets a visual_jump event.
const CHANGE_GRID := Vector2i(64, 36)
const CHANGE_SPIKE_TIMES: float = 4.0
const CHANGE_SPIKE_MIN: float = 0.03
## Image.compute_image_metrics' "mean" is 0-255 averaged over four channels; the
## change is the mean over the three colour channels, 0-1.
const CHANGE_METRIC_SCALE: float = 4.0 / 3.0 / 255.0
## The frames on each side a change is compared with.
const CHANGE_WINDOW: int = 6
## view_frozen: the camera turned this far or moved this far in one frame while
## the picture changed less than this.
const FROZEN_TURN_DEGREES: float = 25.0
const FROZEN_MOVE_METERS: float = 1.0
const FROZEN_MAX_CHANGE: float = 0.1
## Most texts kept from the HUD per frame, and the longest.
const HUD_TEXTS: int = 30
const HUD_TEXT_CHARS: int = 160
## Audio: the capture's buffer (seconds the main thread may stall without losing
## any), how far the mix may fall behind the wall clock before the gap is written
## as silence, and how much of it is left as slack (the audio thread mixes in
## blocks a little ahead of time).
const AUDIO_BUFFER_SECONDS: float = 4.0
const AUDIO_GAP_SECONDS: float = 0.12
const AUDIO_SLACK_SECONDS: float = 0.04
## A gap is silence only once it has lasted this long (a late mix catches up sooner).
const AUDIO_GAP_HOLD_SECONDS: float = 0.4
## A 3x5 pixel font for the stamps (the same glyphs as tools/audio_check.py).
const FONT := {
	"A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
	"E": "111100110100111", "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
	"I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
	"M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
	"Q": "010101101110011", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
	"U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
	"Y": "101101010010010", "Z": "111001010100111", "0": "111101101101111", "1": "010110010010111",
	"2": "110001010100111", "3": "110001010001110", "4": "101101111001001", "5": "111100110001110",
	"6": "011100111101111", "7": "111001010010010", "8": "111101111101111", "9": "111101111001110",
	" ": "000000000000000", ".": "000000000000010", "-": "000000111000000", ":": "000010000010000",
	"_": "000000000000111", "/": "001001010100100", "%": "101001010100101", "+": "000010111010000",
	"=": "000111000111000", "(": "010100100100010", ")": "010001001001010", ",": "000000000010100",
	"!": "010010010000010", "#": "010111010111010", ">": "100010001010100", "<": "001010100010001",
}
## Event kinds that mark a tile red (something is wrong) or yellow (a sound).
const RED_FLAGS: Array[String] = ["pop", "cam_snap", "cam_frozen", "view_frozen"]

## Emitted on the main thread when a stopped take is fully written.
signal written(report: Dictionary)


## One recording: what's captured while it runs, and what its writer thread
## turns into files after record_stop. Nothing here is touched by the main
## thread once the writer starts, except `report` after the writer is done.
class Take extends RefCounted:
	var dir: String = ""
	var label: String = ""
	var fps: float = 30.0
	var fixed_fps: int = 0
	var tile := Vector2i(SHEET_TILE_WIDTH, 144)
	var frames: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	var flags: Array[Dictionary] = []
	## Per frame, filled by the frame writers: a sheet tile, and a CHANGE_GRID copy
	## with its lower third.
	var thumbs: Array = []
	var smalls: Array = []
	var small_lows: Array = []
	var lock := Mutex.new()
	var tasks: Array[int] = []
	var audio_path: String = ""
	var audio_lead: float = 0.0
	var audio_padded: float = 0.0
	var report: Dictionary = {}
	var thread: Thread
	var stop_usec: int = 0


## True between start() and stop().
var recording: bool = false
## Called once per captured frame for what a person reads off the screen
## (remote_play.gd's _state()); returns a Dictionary.
var state_source: Callable

var _take: Take
## Stopped takes whose writer thread is still running.
var _writing: Array[Take] = []
var _t: float = 0.0
## The engine frame (Engine.get_process_frames()) whose time _t is: set in
## this node's _process, which runs first in every frame's process step.
var _clock_frame: int = -1
## Events that fired in a frame before its time was known (a physics tick or
## the network poll come before _process): stamped when it is.
var _unstamped: Array[Dictionary] = []
var _post_draw: bool = false
var _process_frames: int = 0
var _next_due: float = 0.0
var _wall0_usec: int = 0
var _capture_pending: bool = false
var _headless: bool = false
var _every: int = 1
var _frame_events: Array[Dictionary] = []
var _hooked: Dictionary = {}
var _chunks: Array[int] = []
var _last_pos: Dictionary = {}
var _last_cam: Camera3D
var _last_cam_xf := Transform3D()
var _cam_still_since: float = -1.0
var _cam_frozen_flagged: bool = false
var _last_look_at: float = -100.0
var _look_sum := Vector2.ZERO
var _poll: Dictionary = {}
var _hud_nodes: Array[Control] = []
var _hud_scan_wait: int = 0
var _recent_deltas: Array[float] = []
var _sustained: Dictionary = {}
var _frame_wall_usec: int = 0
var _wall_frame: int = -1
var _last_delta: float = 1.0 / 30.0
var _settle: int = 0
var _capture_fx: AudioEffectCapture
var _wav: FileAccess
var _wav_frames: int = 0
var _wav_padded: int = 0
var _wav_discarded: int = 0
## Silence written for a gap that may yet turn out to be a late mix (dropped then).
var _wav_pad_debt: int = 0
var _wav_behind_since: float = -1.0
var _mix_rate: float = 44100.0


func _ready() -> void:
	# First in every frame, so whatever fires later in the frame gets this frame's time.
	process_priority = -1000
	process_physics_priority = -1000
	_headless = DisplayServer.get_name() == "headless"
	RenderingServer.frame_post_draw.connect(_on_post_draw)


func _exit_tree() -> void:
	if recording:
		stop()
	for take: Take in _writing:
		take.thread.wait_to_finish()
	_writing.clear()


## The session's fixed step (--fixed-step=N, given with the engine's --fixed-fps
## N), or 0 without one (then frames aren't evenly spaced). Checked against the
## frame times actually seen: a --fixed-step without --fixed-fps doesn't count.
func session_fixed_fps() -> int:
	var fixed := int(Net.dev_options().get("fixed_step"))
	if fixed <= 0:
		return 0
	if _recent_deltas.size() >= 3:
		for seen: float in _recent_deltas:
			if absf(seen - Engine.time_scale / float(fixed)) > 0.00001:
				push_warning("[Recorder] --fixed-step=%d but frames take %.4f s: launch with --fixed-fps %d too" % [fixed, seen, fixed])
				return 0
	return fixed


## A recording's folder name: lower case, letters, digits, _ and - only, kept as
## typed otherwise ("pile2_1p" stays pile2_1p; to_snake_case made it pile_2_1p).
static func clean_label(label: String) -> String:
	var out := ""
	for character: String in label.strip_edges().to_lower():
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character == "_" or character == "-":
			out += character
		elif character == " " or character == ".":
			out += "_"
	return out if out != "" else "clip"


## Start recording into <base>/rec_<label>/ at fps frames a second. Returns
## {dir, fps, fixed_step} or {error}.
func start(base_dir: String, fps: float, label: String) -> Dictionary:
	if recording:
		return {"error": "already recording %s (record_stop first)" % _take.label}
	var take := Take.new()
	take.label = clean_label(label)
	take.dir = base_dir.path_join("rec_" + take.label)
	# The same label still being written by its last take: let that finish first.
	for older: Take in _writing.duplicate():
		if older.dir == take.dir:
			older.thread.wait_to_finish()
			_finish_writing(older)
	if DirAccess.dir_exists_absolute(take.dir):
		for file: String in DirAccess.get_files_at(take.dir):
			DirAccess.remove_absolute(take.dir.path_join(file))
	DirAccess.make_dir_recursive_absolute(take.dir)
	take.fixed_fps = session_fixed_fps()
	fps = clampf(fps, 1.0, 120.0)
	if take.fixed_fps > 0:
		# Every k-th fixed frame: the nearest rate the session's step allows.
		_every = maxi(1, int(round(float(take.fixed_fps) / fps)))
		take.fps = float(take.fixed_fps) / float(_every)
	else:
		_every = 1
		take.fps = fps
	_take = take
	_t = 0.0
	# Frame 0 is the next frame whose _process this node runs while recording:
	# this one's, if start() comes before it (a physics tick, the network poll),
	# otherwise the next one's. Events until then get frame 0's time.
	_clock_frame = -1
	_unstamped.clear()
	_process_frames = 0
	_next_due = 0.0
	_frame_events.clear()
	_chunks.clear()
	_last_pos.clear()
	_poll.clear()
	_sustained.clear()
	_last_cam = null
	_cam_still_since = -1.0
	_cam_frozen_flagged = false
	_last_look_at = -100.0
	_look_sum = Vector2.ZERO
	_hud_scan_wait = 0
	_settle = 0
	_Sfx.on_play = _on_sfx
	var size := HEADLESS_FRAME if _headless else Vector2i(get_viewport().get_visible_rect().size)
	var columns := mini(SHEET_MAX_WIDTH / SHEET_TILE_WIDTH, 8)
	take.tile = Vector2i(SHEET_MAX_WIDTH / columns, int(round(float(SHEET_MAX_WIDTH / columns) * float(size.y) / maxf(1.0, float(size.x)))))
	_wall0_usec = Time.get_ticks_usec()
	_start_audio()
	recording = true
	_event("record_start", {"fps": take.fps, "fixed_fps": take.fixed_fps})
	print("[Recorder] recording %s at %.1f fps (%s)" % [take.dir, take.fps, "fixed step %d" % take.fixed_fps if take.fixed_fps > 0 else "no fixed step: spacing follows the frame rate"])
	return {"dir": take.dir, "fps": take.fps, "fixed_step": take.fixed_fps > 0}


## Stop. Returns what will be written, for the remote-play result, at once: the
## files are finished on a writer thread ("writing": true until is_writing() is
## false and `written` fires; the same dictionary is filled in then).
func stop() -> Dictionary:
	if not recording:
		return {"error": "not recording"}
	var take := _take
	_event("record_stop", {})
	# Stopped before this frame's _process: these keep the time this frame will
	# have (exact on a fixed step) and are filed under the last frame captured.
	_unstamped.clear()
	_flush_frame_events_into_last()
	recording = false
	if _Sfx.on_play == Callable(self, "_on_sfx"):
		_Sfx.on_play = Callable()
	_capture_pending = false
	_stop_audio()
	var count := take.frames.size()
	var pages: Array = []
	if count > SHEET_PAGE_TILES:
		for page: int in range(1, int(ceil(float(count) / float(SHEET_PAGE_TILES))) + 1):
			pages.append(take.dir.path_join("sheet_%02d.png" % page))
	take.report = {
		"label": take.label,
		"dir": take.dir,
		"fps": take.fps,
		"fixed_step": take.fixed_fps > 0,
		"session_fixed_fps": take.fixed_fps,
		"frames": count,
		"seconds": take.frames.back()["t"] if count > 0 else 0.0,
		"spacing": _spacing(take),
		"realtime_ratio": _realtime_ratio(take),
		"flags": take.flags.size(),
		"events_json": take.dir.path_join("events.json"),
		"sheet": take.dir.path_join("sheet.png"),
		"sheet_pages": pages,
		"filmstrip": take.dir.path_join("filmstrip.png"),
		"audio_wav": take.audio_path,
		"audio_padded_seconds": snappedf(take.audio_padded, 0.001),
		"headless_stand_in": _headless,
		"writing": true,
	}
	take.stop_usec = Time.get_ticks_usec()
	take.thread = Thread.new()
	take.thread.start(_write_take.bind(take), Thread.PRIORITY_LOW)
	_writing.append(take)
	return take.report


## A stopped take is still being written.
func is_writing() -> bool:
	return not _writing.is_empty()


## Waits (letting frames run) until every stopped take is written.
func wait_written() -> void:
	while is_writing():
		await get_tree().process_frame


## The spectator camera jumped on purpose (its target was teleported): a cut,
## not a snap. Logged as cam_cut with the reason.
func note_cut(reason: String) -> void:
	if not recording:
		return
	_last_cam = null
	_settle = maxi(_settle, SETTLE_FRAMES)
	_event("cam_cut", {"to": "spectator", "reason": reason})


## A scenario is placing people (net/dev/scenarios.gd): the jumps it makes over
## the next few frames are setup, logged as one "placed" event, not as pops.
func note_placement(reason: String) -> void:
	if not recording:
		return
	_settle = maxi(_settle, SETTLE_FRAMES)
	_event("placed", {"reason": reason})


## A line the agent asked for (remote play's "mark" step), on this frame.
func note(text: String) -> void:
	if recording:
		_event("mark", {"text": text})


func _process(delta: float) -> void:
	_reap_writers()
	_recent_deltas.append(delta)
	if _recent_deltas.size() > 5:
		_recent_deltas.pop_front()
	if not recording:
		return
	if _process_frames > 0:
		_t += delta
	_last_delta = delta
	_clock_frame = Engine.get_process_frames()
	for entry: Dictionary in _unstamped:
		_stamp(entry, _t)
	_unstamped.clear()
	# The frame's wall-clock time is when it started (its first physics tick,
	# just after net/dev/pacer.gd's wait), not when the picture was read back
	# after drawing, so a sound asked for on one of its ticks lines up.
	if _wall_frame != Engine.get_process_frames():
		_wall_frame = Engine.get_process_frames()
		_frame_wall_usec = Time.get_ticks_usec()
	_process_frames += 1
	_poll_audio()
	_hook_signals()
	_poll_changes()
	_watch_motion(delta)
	var due := false
	if _take.fixed_fps > 0:
		due = (_process_frames - 1) % _every == 0
	elif _t + 0.0005 >= _next_due:
		due = true
		while _next_due <= _t + 0.0005:
			_next_due += 1.0 / _take.fps
	if not due:
		return
	if _headless:
		_capture(_stand_in(_take.frames.size()))
	elif not DisplayServer.window_can_draw():
		# A minimized or covered window doesn't draw; force it, like remote play's shots.
		RenderingServer.force_draw(false)
		_capture(get_viewport().get_texture().get_image())
	else:
		_capture_pending = true


## Writers that finished: joined on the main thread, their reports completed.
func _reap_writers() -> void:
	for take: Take in _writing.duplicate():
		if not take.thread.is_alive():
			take.thread.wait_to_finish()
			_finish_writing(take)


func _finish_writing(take: Take) -> void:
	_writing.erase(take)
	take.report.erase("writing")
	take.report["write_seconds"] = snappedf(float(Time.get_ticks_usec() - take.stop_usec) / 1000000.0, 0.01)
	print("[Recorder] wrote %d frames to %s in %.2f s after the stop (spacing %s)" % [take.frames.size(), take.dir, float(take.report["write_seconds"]), take.report["spacing"]])
	# What the writer kept for the sheets can go now.
	take.thumbs.clear()
	take.smalls.clear()
	take.small_lows.clear()
	written.emit(take.report)


func _physics_process(_delta: float) -> void:
	if recording:
		if _wall_frame != Engine.get_process_frames():
			_wall_frame = Engine.get_process_frames()
			_frame_wall_usec = Time.get_ticks_usec()


func _input(event: InputEvent) -> void:
	if not recording:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.relative.length() > 0.0:
			_look_sum += motion.relative
			_last_look_at = _now()
	elif event is InputEventAction:
		var action := event as InputEventAction
		_event("input", {"action": String(action.action), "pressed": action.pressed})
		if action.pressed and String(action.action).begins_with("move_"):
			_last_look_at = _now()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_event("input", {"click": [(event as InputEventMouseButton).position.x, (event as InputEventMouseButton).position.y]})


func _on_post_draw() -> void:
	if not recording:
		return
	# Still the frame whose time _t is: this node's _process ran earlier in it.
	_post_draw = true
	_poll_changes()
	_post_draw = false
	if not _capture_pending:
		return
	_capture_pending = false
	_capture(get_viewport().get_texture().get_image())


## The game time of the frame running now. Before this node's _process in a
## frame (physics ticks and the network poll run first) that frame's time isn't
## known yet: this guesses it from the last frame's step (exact on a fixed step)
## and _now_known() says false, so _event() stamps the real one later.
func _now() -> float:
	if _now_known():
		return _t
	return 0.0 if _process_frames == 0 else _t + _last_delta


func _now_known() -> bool:
	return _post_draw or _clock_frame == Engine.get_process_frames()


func _stamp(entry: Dictionary, t: float) -> void:
	var was := float(entry["t"])
	entry["t"] = snappedf(t, 0.0001)
	if entry.has("until") and is_equal_approx(float(entry["until"]), was):
		entry["until"] = entry["t"]


func _event(kind: String, data: Dictionary) -> void:
	if _take == null:
		return
	# A pop or a snap that goes on frame after frame (a van flying along at 170 m/s)
	# is one flag that lasts, not one a frame.
	if kind == "pop" or kind == "cam_snap":
		var key := kind + ":" + str(data.get("who", data.get("camera", "")))
		var last: Dictionary = _sustained.get(key, {})
		if not last.is_empty() and _now() - float(last["until"]) <= _last_delta * 1.5 + 0.0001:
			last["until"] = snappedf(_now(), 0.0001)
			last["frames"] = int(last["frames"]) + 1
			last["meters"] = maxf(float(last["meters"]), float(data.get("meters", 0.0)))
			if data.has("to"):
				last["to"] = data["to"]
			return
		data["until"] = snappedf(_now(), 0.0001)
		data["frames"] = 1
	var entry := {"t": snappedf(_now(), 0.0001), "kind": kind}
	entry.merge(data)
	if kind == "pop" or kind == "cam_snap":
		_sustained[kind + ":" + str(data.get("who", data.get("camera", "")))] = entry
	_take.events.append(entry)
	_frame_events.append(entry)
	if not _now_known():
		_unstamped.append(entry)
	if RED_FLAGS.has(kind):
		_take.flags.append(entry)


func _capture(image: Image) -> void:
	if image == null or image.is_empty():
		return
	var take := _take
	var n := take.frames.size()
	if _look_sum != Vector2.ZERO:
		_event("look", {"dx": snappedf(_look_sum.x, 0.1), "dy": snappedf(_look_sum.y, 0.1)})
		_look_sum = Vector2.ZERO
	if not _chunks.is_empty():
		_event("chunk_changed", {"chunks": _chunks.slice(0, 16), "count": _chunks.size()})
		_chunks.clear()
	var entry := {
		"n": n,
		"t": snappedf(_t, 0.0001),
		"wall": snappedf(float(_frame_wall_usec - _wall0_usec) / 1000000.0, 0.0001),
		"file": "frame_%03d.png" % n,
		"camera": _camera_state(),
		"hud": _hud_texts(),
		"words": _words(),
		"events": _frame_events.duplicate(),
	}
	if state_source.is_valid():
		entry["state"] = state_source.call()
	take.frames.append(entry)
	_frame_events.clear()
	take.lock.lock()
	take.thumbs.append(null)
	take.smalls.append(null)
	take.small_lows.append(null)
	take.lock.unlock()
	while take.tasks.size() >= MAX_PENDING_SAVES:
		WorkerThreadPool.wait_for_task_completion(take.tasks.pop_front())
	take.tasks.append(WorkerThreadPool.add_task(_save_frame.bind(take, image, take.dir.path_join(entry["file"]), n)))


## On a worker thread: the full frame to disk, a tile for the sheet, and the
## small copies the picture change is measured on.
static func _save_frame(take: Take, image: Image, path: String, index: int) -> void:
	if image.get_format() != Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGB8)
	image.save_png(path)
	var thumb := image.duplicate() as Image
	thumb.resize(take.tile.x, take.tile.y, Image.INTERPOLATE_BILINEAR)
	var small := thumb.duplicate() as Image
	small.resize(CHANGE_GRID.x, CHANGE_GRID.y, Image.INTERPOLATE_BILINEAR)
	var low_rows := CHANGE_GRID.y / 3
	var low := small.get_region(Rect2i(0, CHANGE_GRID.y - low_rows, CHANGE_GRID.x, low_rows))
	take.lock.lock()
	if index < take.thumbs.size():
		take.thumbs[index] = thumb
		take.smalls[index] = small
		take.small_lows[index] = low
	take.lock.unlock()


## Headless runs draw nothing, so each frame is a plain card with its number:
## the sheet, the stamps and the spacing still get exercised (the CI test).
func _stand_in(index: int) -> Image:
	var image := Image.create(HEADLESS_FRAME.x, HEADLESS_FRAME.y, false, Image.FORMAT_RGB8)
	var shade := 0.15 + 0.6 * float(index % 30) / 30.0
	image.fill(Color(shade * 0.4, shade * 0.6, shade))
	draw_text(image, Vector2i(20, 70), "FRAME %d" % index, Color.WHITE, 4)
	return image


func _flush_frame_events_into_last() -> void:
	if _take.frames.is_empty() or _frame_events.is_empty():
		return
	(_take.frames.back()["events"] as Array).append_array(_frame_events)
	_frame_events.clear()


# ---------------------------------------------------------------- what happened


## Connect to whatever appeared since the last frame: leaf fields (a new one each
## job), the run director, hiding spots, and Net's zone changes. The handlers are
## this node's own methods with the emitter bound, so nothing a freed node left
## behind is ever called (a lambda's captures can be freed under it).
func _hook_signals() -> void:
	if not _hooked.has("net"):
		_hooked["net"] = true
		Net.player_zone_changed.connect(_on_zone_changed)
	for field: Node in get_tree().get_nodes_in_group("leaf_field"):
		if _hooked.has(field.get_instance_id()):
			continue
		_hooked[field.get_instance_id()] = true
		if field.has_signal("stroke_event"):
			# Every stroke, once per peer, in the frame its leaves change (contract C1).
			field.connect("stroke_event", _on_stroke)
		if field.has_signal("chunk_changed"):
			field.connect("chunk_changed", _on_chunk_changed)
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null and not _hooked.has(director.get_instance_id()):
		_hooked[director.get_instance_id()] = true
		director.connect("phase_changed", _on_phase_changed.bind(director.get_instance_id()))
	for spot: Node in get_tree().get_nodes_in_group("hide_spots"):
		if _hooked.has(spot.get_instance_id()):
			continue
		_hooked[spot.get_instance_id()] = true
		spot.connect("occupant_changed", _on_occupant_changed.bind(spot.get_instance_id()))


func _on_zone_changed(peer_id: int, zone: Net.Zone) -> void:
	if recording:
		_event("zone", {"peer": peer_id, "who": Net.player_name(peer_id), "zone": Net.Zone.keys()[zone]})


func _on_stroke(ev: Dictionary) -> void:
	if recording:
		_event("stroke", {"kind": str(ev.get("kind", "")), "actor": int(ev.get("actor", 0)), "bite": int(ev.get("bite", 0)), "moved": int(ev.get("moved", 0)), "local": bool(ev.get("local", false)), "at": _v(ev.get("at", Vector3.ZERO))})


func _on_chunk_changed(chunk_index: int) -> void:
	if recording and not _chunks.has(chunk_index):
		_chunks.append(chunk_index)


func _on_phase_changed(status: String, director_id: int) -> void:
	var director := instance_from_id(director_id) as Node
	if recording and director != null:
		_event("raid_phase", {"phase": ["QUIET", "WARNING", "CHASE", "DEPARTING"][clampi(int(director.call("phase")), 0, 3)], "status": status})


func _on_occupant_changed(peer_id: int, spot_id: int) -> void:
	var spot := instance_from_id(spot_id) as Node3D
	if recording and spot != null:
		_event("hide_spot", {"spot": str(spot.get("label")) if spot.get("label") != null else spot.name, "occupant": peer_id, "at": _v(spot.global_position)})


## audio/sfx.gd's hook: a sound the game asked for, the moment it asked.
func _on_sfx(id: String, how: String, at: Vector3) -> void:
	if not recording:
		return
	if how == "":
		_event("sfx", {"id": id})
	else:
		_event("sfx_at", {"id": id, "how": how, "at": _v(at)})


## Things with no signal: captures, the Annex, rides, the crew, the current
## camera, and the local player's state. Checked in _process and again after
## the frame is drawn, so a change made later in the frame than this node's
## _process is still filed under the frame that shows it.
func _poll_changes() -> void:
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null:
		_changed("cohort", str(director.call("cohort_roster")), func(value: String) -> void: _event("capture", {"cohort": value}))
	var annex := get_tree().get_first_node_in_group("annex")
	if annex != null:
		var status: Dictionary = annex.call("status")
		_changed("annex", "%s %s %s" % [status.get("active", false), status.get("form", ""), status.get("stage", "")], func(_value: String) -> void: _event("annex", status.duplicate()))
	for ride: Node in get_tree().get_nodes_in_group("rides"):
		if ride.is_in_group("nice_shuttle"):
			continue
		var ride_name := str(ride.name)
		_changed("ride:" + ride_name, str(ride.call("is_riding")), func(value: String) -> void: _event("ride", {"ride": ride_name, "riding": value == "true"}))
	# The Courtesy Shuttle (nice_boys:4): each trip's leg, and who sits in a van.
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	if shuttle != null:
		for trip_id: Variant in shuttle.call("trip_ids"):
			var trip := int(trip_id)
			_changed("van_leg:%d" % trip, str(shuttle.call("leg_name", trip)), func(value: String) -> void: _event("van_leg", {"trip": trip, "leg": value}))
		_changed("van_seated", str(shuttle.call("seated_riders")), func(value: String) -> void: _event("van_seated", {"riders": value}))
	# How many NICE BOYS, and each one's mode (R2 chunk 2: seated, hopping out,
	# spotting, winding up...), so a recording shows the catch beat by beat.
	var crew_now := get_tree().get_nodes_in_group("crew")
	var modes := PackedStringArray()
	for member: Node in crew_now:
		modes.append("%s=%d" % [member.name, int(member.get("mode")) if "mode" in member else -1])
	_changed("crew", "%d|%s" % [crew_now.size(), ",".join(modes)], func(value: String) -> void: _event("crew", {"count": value.get_slice("|", 0).to_int(), "modes": value.get_slice("|", 1)}))
	var me := _player(Net.local_peer_id())
	if me != null:
		_changed("hidden", str(me.call("is_hidden")), func(value: String) -> void: _event("hidden", {"hidden": value == "true"}))
		_changed("anim", str(me.get("anim_state")), func(value: String) -> void: _event("anim", {"state": int(value)}))
		_changed("held", _held_kind(me), func(value: String) -> void: _event("held", {"kind": value}))
	var camera := get_viewport().get_camera_3d()
	var name_now := _node_label(camera)
	_changed("camera", name_now, func(value: String) -> void: _event("cam_cut", {"to": value}))


func _changed(key: String, value: String, on_change: Callable) -> void:
	if not _poll.has(key):
		_poll[key] = value
		return
	if str(_poll[key]) != value:
		_poll[key] = value
		on_change.call(value)


## Pops (something jumping across the screen) and the camera snapping or freezing.
func _watch_motion(delta: float) -> void:
	var settling := _settle > 0
	if settling:
		_settle -= 1
	var watched: Array = []
	var observer := bool(Net.dev_options().get("observer"))
	for node: Node in get_tree().get_nodes_in_group("players"):
		var peer_id := int(str(node.name)) if str(node.name).is_valid_int() else 0
		# A watcher's body (the observer's) is a ghost nobody sees: its zone moves aren't pops.
		if Net.is_watcher(peer_id) or (observer and peer_id == Net.local_peer_id()):
			continue
		var visual := node.get_node_or_null("Visual") as Node3D
		# A staged body (a van seat) is drawn later this frame from its anchor
		# (player/stage_body.gd, priority 110): watch the anchor, not a Visual its
		# synced parent has moved since last frame.
		var stage := node.get_node_or_null("StageBody")
		var anchor: Node3D = stage.call("staged_anchor") if stage != null and stage.has_method("staged_anchor") else null
		watched.append(["player", "player %s" % _who(node), anchor if anchor != null else (visual if visual != null else node as Node3D)])
	for node: Node in get_tree().get_nodes_in_group("crew"):
		var visual := node.get_node_or_null("Visual") as Node3D
		watched.append(["crew", str(node.name), visual if visual != null else node as Node3D])
	for ride: Node in get_tree().get_nodes_in_group("rides"):
		var body := ride.get_node_or_null("Body") as Node3D
		if body != null:
			watched.append(["vehicle", str(ride.name), body])
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	if shuttle != null:
		for trip_id: Variant in shuttle.call("trip_ids"):
			var holder := shuttle.get_node_or_null("Trip%d" % int(trip_id)) as Node3D
			if holder != null and holder.visible:
				watched.append(["vehicle", "van %d" % int(trip_id), holder])
	var seen: Dictionary = {}
	for item: Array in watched:
		var node := item[2] as Node3D
		if node == null or not node.is_inside_tree():
			continue
		var key := node.get_instance_id()
		seen[key] = true
		var at := node.get_global_transform_interpolated().origin if node.is_physics_interpolated() else node.global_position
		if _last_pos.has(key) and not settling:
			var jump := at.distance_to(_last_pos[key])
			if jump > POP_METERS and jump / maxf(delta, 0.001) > float(POP_SPEED[item[0]]):
				_event("pop", {"who": item[1], "meters": snappedf(jump, 0.01), "from": _v(_last_pos[key]), "to": _v(at)})
		_last_pos[key] = at
	for key: Variant in _last_pos.keys():
		if not seen.has(key):
			_last_pos.erase(key)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var xf := camera.get_global_transform_interpolated() if camera.is_physics_interpolated() else camera.global_transform
	if camera == _last_cam and not settling:
		var moved := xf.origin.distance_to(_last_cam_xf.origin)
		var turned := rad_to_deg((-xf.basis.z).normalized().angle_to((-_last_cam_xf.basis.z).normalized()))
		if moved > CAM_SNAP_METERS or turned > CAM_SNAP_DEGREES:
			_event("cam_snap", {"camera": _node_label(camera), "meters": snappedf(moved, 0.01), "degrees": snappedf(turned, 0.1)})
		if xf.is_equal_approx(_last_cam_xf):
			if _cam_still_since < 0.0:
				_cam_still_since = _now()
			var still := _now() - _cam_still_since
			if still >= CAM_FROZEN_SECONDS and _last_look_at >= _cam_still_since and not _cam_frozen_flagged:
				_cam_frozen_flagged = true
				_event("cam_frozen", {"camera": _node_label(camera), "still_for": snappedf(still, 0.01), "note": "the camera kept exactly still while looking or walking"})
		else:
			_cam_still_since = -1.0
			_cam_frozen_flagged = false
	else:
		_cam_still_since = -1.0
		_cam_frozen_flagged = false
	_last_cam = camera
	_last_cam_xf = xf


func _camera_state() -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var xf := camera.get_global_transform_interpolated() if camera.is_physics_interpolated() else camera.global_transform
	return {"name": _node_label(camera), "pos": _v(xf.origin), "fwd": _v(-xf.basis.z), "fov": snappedf(camera.fov, 0.1)}


## R2c: the words on screen this exact frame, with how much of each shows
## (`hud` rescans its labels every 15 frames, so a caption could look half a
## second late there): the caption stack's lines [text, alpha, rect], the
## bubbles and tags (ui/overheads.gd last_rects: [kind, text, alpha, rect]) and
## the interact prompt [text, alpha]. Rects are x, y, w, h in screen px.
func _words() -> Dictionary:
	var out := {}
	var stack := get_tree().get_first_node_in_group("caption_stack")
	if stack != null and "_lines" in stack:
		var lines: Array = []
		for line: Dictionary in stack.get("_lines"):
			var box := line.get("box") as Control
			if box == null or not is_instance_valid(box) or not box.visible or float(line.get("alpha", 0.0)) <= 0.0:
				continue
			var r := Rect2(box.position, box.size)
			lines.append([str(line.get("text", "")).left(HUD_TEXT_CHARS), snappedf(float(line["alpha"]), 0.01), [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]])
		out["captions"] = lines
	var ui := get_tree().get_first_node_in_group("game_ui")
	var heads := ui.get_node_or_null("Overheads") if ui != null else null
	if heads != null and "last_rects" in heads:
		var over: Array = []
		for item: Dictionary in heads.get("last_rects"):
			var r: Rect2 = item.get("rect", Rect2())
			over.append([str(item.get("kind", "")), str(item.get("text", "")).left(HUD_TEXT_CHARS), snappedf(float(item.get("alpha", 0.0)), 0.01), [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]])
		out["overheads"] = over
	var world := get_tree().get_first_node_in_group("world")
	var prompt := world.get_node_or_null("InteractionPrompt") as Label3D if world != null else null
	if prompt != null and prompt.visible:
		out["prompt"] = [prompt.text, snappedf(1.0 - prompt.transparency, 0.01)]
	return out


## Every visible line of 2D text (HUD, prompts, captions, windows).
func _hud_texts() -> Array:
	_hud_scan_wait -= 1
	if _hud_scan_wait <= 0:
		_hud_scan_wait = 15
		_hud_nodes.clear()
		_collect_labels(get_tree().root)
	var out: Array = []
	for node: Control in _hud_nodes:
		if not is_instance_valid(node) or not node.is_visible_in_tree():
			continue
		var text := ""
		if node is Label:
			text = (node as Label).text
		elif node is RichTextLabel:
			text = (node as RichTextLabel).get_parsed_text()
		text = text.strip_edges().replace("\n", " / ")
		if text == "":
			continue
		out.append(text.left(HUD_TEXT_CHARS))
		if out.size() >= HUD_TEXTS:
			break
	return out


func _collect_labels(node: Node) -> void:
	if node is Label or node is RichTextLabel:
		_hud_nodes.append(node as Control)
	for child: Node in node.get_children():
		# The 3D world holds no screen text (its labels are Label3D) and is most of the tree.
		if child.is_in_group("world"):
			continue
		_collect_labels(child)


# ---------------------------------------------------------------- audio


## The mix, streamed to <take>/audio.wav as 32-bit float stereo: an
## AudioEffectCapture on the Master bus, drained every frame.
func _start_audio() -> void:
	_capture_fx = null
	_wav = null
	_wav_frames = 0
	_wav_padded = 0
	_wav_pad_debt = 0
	_wav_behind_since = -1.0
	_wav_discarded = 0
	_take.audio_lead = 0.0
	_take.audio_path = ""
	if _headless or AudioServer.get_bus_count() == 0:
		return
	_mix_rate = AudioServer.get_mix_rate()
	var path := _take.dir.path_join("audio.wav")
	_wav = FileAccess.open(path, FileAccess.WRITE)
	if _wav == null:
		return
	_write_wav_header(_wav, int(_mix_rate), 0)
	_capture_fx = AudioEffectCapture.new()
	_capture_fx.buffer_length = AUDIO_BUFFER_SECONDS
	AudioServer.add_bus_effect(0, _capture_fx)
	# The wav's first sample is mixed at the audio thread's next mix, not now.
	_take.audio_lead = maxf(0.0, AudioServer.get_time_to_next_mix())
	_take.audio_path = path


## Drain what the audio thread mixed since the last frame, and write as silence
## whatever it never mixed: frames the capture had to drop, and a mix that has
## fallen behind the wall clock (an underrun: a starved audio thread mixes
## nothing for that stretch, so without this every later sound would sit early).
func _poll_audio() -> void:
	if _capture_fx == null or _wav == null:
		return
	var elapsed := float(Time.get_ticks_usec() - _wall0_usec) / 1000000.0 - _take.audio_lead
	var expected := int(elapsed * _mix_rate)
	var available := _capture_fx.get_frames_available()
	if available > 0:
		var chunk := _capture_fx.get_buffer(available)
		# Mix that turns up after its gap was already written as silence (it was
		# only late, not lost): as much of it is dropped, so the wav stays on the
		# wall clock both ways.
		var ahead := _wav_frames + available - expected - int(AUDIO_SLACK_SECONDS * _mix_rate)
		var drop := clampi(mini(ahead, _wav_pad_debt), 0, available) if ahead > int(AUDIO_GAP_SECONDS * _mix_rate) else 0
		if drop > 0:
			chunk = chunk.slice(drop)
			_wav_pad_debt -= drop
			_wav_padded -= drop
		_wav.store_buffer(chunk.to_byte_array())
		_wav_frames += available - drop
	var discarded := _capture_fx.get_discarded_frames()
	if discarded > _wav_discarded:
		_pad_audio(discarded - _wav_discarded)
		_wav_discarded = discarded
	# Behind the wall clock for longer than a late mix block ever is: the audio
	# thread never mixed that stretch (an underrun), so it's silence here.
	var behind := expected - _wav_frames
	if behind > int(AUDIO_GAP_SECONDS * _mix_rate):
		if _wav_behind_since < 0.0:
			_wav_behind_since = elapsed
		elif elapsed - _wav_behind_since >= AUDIO_GAP_HOLD_SECONDS:
			_pad_audio(behind - int(AUDIO_SLACK_SECONDS * _mix_rate))
			_wav_behind_since = -1.0
	else:
		_wav_behind_since = -1.0


func _pad_audio(frames: int) -> void:
	if frames <= 0:
		return
	var silence := PackedByteArray()
	silence.resize(frames * 8)
	_wav.store_buffer(silence)
	_wav_frames += frames
	_wav_padded += frames
	_wav_pad_debt += frames


func _stop_audio() -> void:
	if _capture_fx == null or _wav == null:
		return
	_poll_audio()
	for slot: int in range(AudioServer.get_bus_effect_count(0) - 1, -1, -1):
		if AudioServer.get_bus_effect(0, slot) == _capture_fx:
			AudioServer.remove_bus_effect(0, slot)
	_capture_fx = null
	_wav.seek(0)
	_write_wav_header(_wav, int(_mix_rate), _wav_frames)
	_wav.close()
	_wav = null
	_take.audio_padded = float(_wav_padded) / _mix_rate
	if _wav_padded > 0:
		print("[Recorder] %s: %.2f s the audio thread never mixed, written as silence where it went missing" % [_take.label, _take.audio_padded])


## A RIFF/WAVE header for IEEE float stereo (format 3, 32 bits), frames long.
static func _write_wav_header(file: FileAccess, rate: int, frames: int) -> void:
	var data_bytes := frames * 8
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data_bytes)
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(3)
	file.store_16(2)
	file.store_32(rate)
	file.store_32(rate * 8)
	file.store_16(8)
	file.store_16(32)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data_bytes)


# ---------------------------------------------------------------- writing (the take's own thread)


## The writer thread: wait for the frames, then the picture change and the
## flags it implies, the sheets, the filmstrip and events.json.
static func _write_take(take: Take) -> void:
	for task: int in take.tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	take.tasks.clear()
	_measure_change(take)
	take.report["flags"] = take.flags.size()
	_write_sheets(take)
	_write_filmstrip(take)
	var log := {
		"label": take.label,
		"fps": take.fps,
		"fixed_step": take.fixed_fps > 0,
		"session_fixed_fps": take.fixed_fps,
		"spacing": take.report["spacing"],
		"realtime_ratio": take.report["realtime_ratio"],
		"film": {"margin": FILM_MARGIN, "width": FILM_WIDTH, "seconds": take.report["seconds"]},
		"audio": {"wav": take.audio_path, "wall_start": snappedf(take.audio_lead, 0.0001), "padded_seconds": snappedf(take.audio_padded, 0.001), "format": "float32"},
		"flags": take.flags,
		"events": take.events,
		"frames": take.frames,
	}
	var file := FileAccess.open(take.dir.path_join("events.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(log, " "))
		file.close()


static func _spacing(take: Take) -> Dictionary:
	var frames := take.frames
	if frames.size() < 2:
		return {"frames": frames.size()}
	var low := INF
	var high := 0.0
	for index: int in range(1, frames.size()):
		var gap := float(frames[index]["t"]) - float(frames[index - 1]["t"])
		low = minf(low, gap)
		high = maxf(high, gap)
	var mean := (float(frames.back()["t"]) - float(frames[0]["t"])) / float(frames.size() - 1)
	return {"expected": snappedf(1.0 / take.fps, 0.0001), "min": snappedf(low, 0.0001), "max": snappedf(high, 0.0001), "mean": snappedf(mean, 0.0001), "even": high - low < 0.002}


## How much of the picture changed since the frame before, 0 to 1 (the mean
## colour difference of tiny copies), with the lower third on its own: the work
## in front of you. A spike well over the clip's usual change, with no camera
## cut or turn behind it, is something popping. Stored per frame as "change"
## and "change_low"; spikes become "visual_jump" events.
static func _measure_change(take: Take) -> void:
	var frames := take.frames
	var frozen_run := {}
	var values: Array[float] = []
	var previous: Image = null
	var previous_low: Image = null
	for index: int in frames.size():
		var small: Image = take.smalls[index] if index < take.smalls.size() else null
		var low: Image = take.small_lows[index] if index < take.small_lows.size() else null
		if small == null:
			continue
		if previous != null:
			var change := float(small.compute_image_metrics(previous, false)["mean"]) * CHANGE_METRIC_SCALE
			var change_low := float(low.compute_image_metrics(previous_low, false)["mean"]) * CHANGE_METRIC_SCALE
			frames[index]["change"] = snappedf(change, 0.0001)
			frames[index]["change_low"] = snappedf(change_low, 0.0001)
			values.append(change)
			frozen_run = _check_view_frozen(take, index, change, frozen_run)
		previous = small
		previous_low = low
	if values.size() < 4:
		return
	# A jump is a frame that changes far more than the frames around it: a steady
	# pulse (the raid vignette) or a long camera pan changes a lot every frame and
	# isn't one.
	for index: int in frames.size():
		var change := float(frames[index].get("change", 0.0))
		var around: Array[float] = []
		for other: int in range(maxi(1, index - CHANGE_WINDOW), mini(frames.size(), index + CHANGE_WINDOW + 1)):
			if other != index:
				around.append(float(frames[other].get("change", 0.0)))
		if around.is_empty():
			continue
		around.sort()
		var median: float = around[around.size() / 2]
		if change > maxf(median * CHANGE_SPIKE_TIMES, CHANGE_SPIKE_MIN):
			var entry := {"t": frames[index]["t"], "kind": "visual_jump", "frame": index, "change": snappedf(change, 0.001), "median": snappedf(median, 0.001)}
			take.events.append(entry)
			(frames[index]["events"] as Array).append(entry)


## The camera turned or moved a lot since the frame before, yet the picture
## barely changed: the view isn't following the camera (the renderer is drawing
## a stale view). A red flag, "view_frozen". Returns the run it's part of.
static func _check_view_frozen(take: Take, index: int, change: float, run: Dictionary) -> Dictionary:
	var frames := take.frames
	var now: Dictionary = frames[index].get("camera", {})
	var before: Dictionary = frames[index - 1].get("camera", {})
	if now.is_empty() or before.is_empty() or str(now["name"]) != str(before["name"]):
		return run
	var fwd_now := Vector3(now["fwd"][0], now["fwd"][1], now["fwd"][2])
	var fwd_before := Vector3(before["fwd"][0], before["fwd"][1], before["fwd"][2])
	var turned := rad_to_deg(fwd_now.angle_to(fwd_before))
	var moved := Vector3(now["pos"][0], now["pos"][1], now["pos"][2]).distance_to(Vector3(before["pos"][0], before["pos"][1], before["pos"][2]))
	if (turned >= FROZEN_TURN_DEGREES or moved >= FROZEN_MOVE_METERS) and change < FROZEN_MAX_CHANGE:
		# Frame after frame of it (riding inside a windowless van) is one flag that lasts.
		if not run.is_empty() and int(run["last_frame"]) == index - 1:
			run["last_frame"] = index
			run["frames"] = int(run["frames"]) + 1
			run["until"] = frames[index]["t"]
			return run
		var entry := {"t": frames[index]["t"], "kind": "view_frozen", "frame": index, "camera": now["name"], "degrees": snappedf(turned, 0.1), "meters": snappedf(moved, 0.01), "change": snappedf(change, 0.001), "note": "the camera turned or moved but the picture didn't", "frames": 1, "until": frames[index]["t"], "last_frame": index}
		take.events.append(entry)
		take.flags.append(entry)
		(frames[index]["events"] as Array).append(entry)
		return entry
	return run


## Game seconds per wall second over the recording: 1 is real time, under 1 is a
## loaded machine running the fixed step slower than real time.
static func _realtime_ratio(take: Take) -> float:
	var frames := take.frames
	if frames.size() < 2:
		return 1.0
	var wall := float(frames.back()["wall"]) - float(frames[0]["wall"])
	var game := float(frames.back()["t"]) - float(frames[0]["t"])
	return snappedf(game / wall, 0.001) if wall > 0.0 else 1.0


## sheet.png (an overview of at most SHEET_PAGE_TILES frames picked evenly) and,
## when there are more frames than that, sheet_01.png ... with every frame, the
## pages drawn side by side on the worker pool.
static func _write_sheets(take: Take) -> void:
	var count := take.frames.size()
	if count == 0:
		return
	var overview: Array[int] = []
	if count <= SHEET_PAGE_TILES:
		for index: int in count:
			overview.append(index)
	else:
		for k: int in SHEET_PAGE_TILES:
			overview.append(int(round(float(k) * float(count - 1) / float(SHEET_PAGE_TILES - 1))))
	_sheet(take, overview, take.dir.path_join("sheet.png"))
	if count > SHEET_PAGE_TILES:
		var pages := int(ceil(float(count) / float(SHEET_PAGE_TILES)))
		var group := WorkerThreadPool.add_group_task(_sheet_page.bind(take), pages, -1, false, "recorder sheets")
		WorkerThreadPool.wait_for_group_task_completion(group)


static func _sheet_page(page: int, take: Take) -> void:
	var indices: Array[int] = []
	for index: int in range(page * SHEET_PAGE_TILES, mini(take.frames.size(), (page + 1) * SHEET_PAGE_TILES)):
		indices.append(index)
	_sheet(take, indices, take.dir.path_join("sheet_%02d.png" % (page + 1)))


static func _sheet(take: Take, indices: Array[int], path: String) -> void:
	var tile := take.tile
	var columns := SHEET_MAX_WIDTH / tile.x
	var rows := int(ceil(float(indices.size()) / float(columns)))
	var sheet := Image.create(columns * tile.x, maxi(1, rows) * tile.y, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.07, 0.08, 0.1))
	for k: int in indices.size():
		var index := indices[k]
		var at := Vector2i((k % columns) * tile.x, (k / columns) * tile.y)
		var thumb: Image = take.thumbs[index] if index < take.thumbs.size() else null
		if thumb != null:
			sheet.blit_rect(thumb, Rect2i(Vector2i.ZERO, thumb.get_size()), at)
		var frame: Dictionary = take.frames[index]
		var mark := _tile_mark(frame)
		# The stamp: frame number and game time, top left.
		sheet.fill_rect(Rect2i(at, Vector2i(116, 14)), Color(0, 0, 0))
		draw_text(sheet, at + Vector2i(3, 2), "#%03d %.3fS" % [index, float(frame["t"])], Color(1, 1, 1), 2)
		if mark != Color.TRANSPARENT:
			sheet.fill_rect(Rect2i(at + Vector2i(tile.x - 12, 0), Vector2i(12, 12)), mark)
			sheet.fill_rect(Rect2i(at, Vector2i(tile.x, 2)), mark)
		# What fired on this frame, along the bottom.
		var tags := _tile_tags(frame)
		if tags != "":
			sheet.fill_rect(Rect2i(at + Vector2i(0, tile.y - 9), Vector2i(tile.x, 9)), Color(0, 0, 0))
			draw_text(sheet, at + Vector2i(2, tile.y - 7), tags.left((tile.x - 4) / 4), mark if mark != Color.TRANSPARENT else Color(0.75, 0.9, 1.0), 1)
		# A thin border between tiles.
		sheet.fill_rect(Rect2i(at + Vector2i(tile.x - 1, 0), Vector2i(1, tile.y)), Color(0.07, 0.08, 0.1))
		sheet.fill_rect(Rect2i(at + Vector2i(0, tile.y - 1), Vector2i(tile.x, 1)), Color(0.07, 0.08, 0.1))
	sheet.save_png(path)


## Red for a flag (pop, snap, freeze), yellow for a sound, cyan for any other event.
static func _tile_mark(frame: Dictionary) -> Color:
	var mark := Color.TRANSPARENT
	for entry: Dictionary in frame["events"]:
		var kind := str(entry["kind"])
		if RED_FLAGS.has(kind):
			return Color(1.0, 0.2, 0.15)
		if kind == "sfx" or kind == "sfx_at":
			mark = Color(1.0, 0.85, 0.2)
		elif mark == Color.TRANSPARENT and kind != "input" and kind != "look":
			mark = Color(0.3, 0.9, 1.0)
	return mark


static func _tile_tags(frame: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for entry: Dictionary in frame["events"]:
		var kind := str(entry["kind"])
		match kind:
			"sfx", "sfx_at":
				if not parts.has(str(entry["id"])):
					parts.append(str(entry["id"]))
			"look", "chunk_changed", "record_start", "record_stop":
				pass
			"input":
				if bool(entry.get("pressed", false)) and entry.has("action"):
					parts.append(">" + str(entry["action"]))
			"zone":
				parts.append("ZONE " + str(entry["zone"]))
			"raid_phase":
				parts.append("RAID " + str(entry["phase"]))
			"pop":
				parts.append("POP " + str(entry["who"]))
			"visual_jump":
				parts.append("JUMP")
			"mark":
				parts.append("MARK " + str(entry["text"]))
			_:
				parts.append(kind)
	return " ".join(parts)


## Thumbnails on the time axis tools/playtest_audio.py uses: x = FILM_MARGIN +
## t / seconds * FILM_WIDTH, so a thumbnail sits above the sound it made.
static func _write_filmstrip(take: Take) -> void:
	var frames := take.frames
	if frames.is_empty():
		return
	var seconds := maxf(float(frames.back()["t"]), 0.001)
	var film := Image.create(FILM_MARGIN + FILM_WIDTH + 8, FILM_THUMB.y + 14, false, Image.FORMAT_RGB8)
	film.fill(Color(0.07, 0.08, 0.1))
	var slots := FILM_WIDTH / FILM_THUMB.x
	var last := -1
	for k: int in slots:
		var t := seconds * (float(k) + 0.5) / float(slots)
		var index := _frame_at(frames, t)
		if index == last:
			continue
		last = index
		var thumb: Image = take.thumbs[index] if index < take.thumbs.size() else null
		if thumb == null:
			continue
		var small := thumb.duplicate() as Image
		small.resize(FILM_THUMB.x - 4, FILM_THUMB.y, Image.INTERPOLATE_BILINEAR)
		var center := FILM_MARGIN + int(float(frames[index]["t"]) / seconds * float(FILM_WIDTH))
		var x := clampi(center - small.get_width() / 2, 0, film.get_width() - small.get_width())
		film.blit_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i(x, 0))
		film.fill_rect(Rect2i(Vector2i(center, FILM_THUMB.y), Vector2i(1, 4)), Color(1, 1, 1))
		draw_text(film, Vector2i(x + 2, FILM_THUMB.y + 6), "#%03d" % index, Color(1, 1, 1), 1)
	film.save_png(take.dir.path_join("filmstrip.png"))


## The frame nearest game time t (frames are in time order).
static func _frame_at(frames: Array[Dictionary], t: float) -> int:
	var low := 0
	var high := frames.size() - 1
	while low < high:
		var mid := (low + high) / 2
		if float(frames[mid]["t"]) < t:
			low = mid + 1
		else:
			high = mid
	if low > 0 and absf(float(frames[low - 1]["t"]) - t) <= absf(float(frames[low]["t"]) - t):
		return low - 1
	return low


## Stamp text into an image with the 3x5 font, scale pixels per font pixel.
static func draw_text(image: Image, at: Vector2i, text: String, color: Color, scale: int) -> void:
	var x := at.x
	for character: String in text.to_upper():
		var glyph: String = FONT.get(character, FONT[" "])
		for row: int in 5:
			for column: int in 3:
				if glyph[row * 3 + column] == "1":
					var px := Rect2i(Vector2i(x + column * scale, at.y + row * scale), Vector2i(scale, scale))
					if px.position.x >= 0 and px.position.y >= 0 and px.end.x <= image.get_width() and px.end.y <= image.get_height():
						image.fill_rect(px, color)
		x += 4 * scale


# ---------------------------------------------------------------- helpers


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _held_kind(player: Node) -> String:
	var held: Node = player.call("_held_prop") if player.has_method("_held_prop") else null
	return str(held.get("kind")) if held != null else ""


func _who(node: Node) -> String:
	var shown := Net.player_name(int(str(node.name)))
	return shown if shown != "" else str(node.name)


func _node_label(node: Node) -> String:
	if node == null:
		return ""
	var parent := node.get_parent()
	return "%s/%s" % [parent.name, node.name] if parent != null else str(node.name)


static func _v(at: Vector3) -> Array:
	return [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]
