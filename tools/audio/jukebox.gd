extends Node3D

## Dev only, not part of the game (gap-specs/audio.json chunk 7). Every sound the
## game has, to listen to without playing a day:
##   Music   every track and stinger (audio/music_tracks.gd), looping the way the
##           director loops them (back to the end of the intro)
##   Moods   a fake game state and the mood MusicDirector.pick_mood() picks for it,
##           live, with its tracks; play the mood
##   Sounds  every id in audio/sound_bank.gd, one-shots and loops, with a filter
##   Engine  audio/vehicle_sound.gd on a stand-in truck: on, speed, throttle, skid,
##           the profile, the crank and the pull-up, and the legacy ride's 8 s run
##   Board   audio/board_sound.gd on a stand-in board: speed, air, grind, the
##           one-shots and an ollie
## Run: Godot_v4.7.2-stable_win64.exe --path . res://tools/audio/jukebox.tscn
## (-- --shot=<abs png> saves the window after a second and quits, for a look;
## --tab=<n> opens on that tab; --demo=ride runs the legacy ride's engine at once,
## for a Movie Maker capture: --write-movie <abs>.png --fixed-fps 30).
## The labels are a developer's, in plain English here; nothing reaches a player.

const _Buses = preload("res://audio/buses.gd")
const _SfxScript = preload("res://audio/sfx.gd")
const _Bank = preload("res://audio/sound_bank.gd")
const _Tracks = preload("res://audio/music_tracks.gd")
const _Director = preload("res://audio/music_director.gd")
const _Strings = preload("res://ui/strings.gd")
const _VehicleSound = preload("res://audio/vehicle_sound.gd")
const _BoardSound = preload("res://audio/board_sound.gd")

## The legacy ride's run for the demo: as long as Chefty's ride, peaking near its speed.
const RIDE_SECONDS: float = 8.0
const RIDE_PEAK: float = 187.0

var _sfx: Node
var _music: AudioStreamPlayer
var _now_playing: Label
var _loops: Dictionary = {}
var _sound_list: ItemList
var _filter: LineEdit
var _mood_label: Label
var _mood: StringName = &""
var _fake := {"net_state": int(Net.State.IN_SESSION), "zone": int(Net.Zone.LOT), "hour": 9.0, "heat": 0.0, "phase": 0, "sleeping": false, "summary_open": false, "annex_urgent": false}

var _truck: Node3D
var _engine: Node3D
var _engine_state := {"on": false, "throttle": 0.0, "speed": 0.0, "skidding": false}
var _engine_label: Label
var _speed_slider: HSlider
var _throttle_slider: HSlider
var _ride_t: float = -1.0
## After the ride demo pulls up: the idle runs this much longer (s).
var _linger: float = 0.0

var _board_stub: Node3D
var _board: Node3D
var _board_state := {"on_board": true, "speed": 0.0, "on_ground": true, "grinding": false}
var _board_label: Label
var _ollie_t: float = -1.0

var _shot_path: String = ""
var _shot_wait: float = 1.0
var _first_tab: int = 0


func _ready() -> void:
	_Buses.ensure()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg == "--demo=ride":
			_ride_t = 0.0
		elif arg.begins_with("--tab="):
			_first_tab = int(arg.trim_prefix("--tab="))
	_sfx = _SfxScript.new()
	_sfx.name = "Sfx"
	add_child(_sfx)
	_music = AudioStreamPlayer.new()
	_music.bus = _Buses.MUSIC
	add_child(_music)
	# A listener for the 3D stand-ins: the camera sits a few meters off them.
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.6, 6.0)
	add_child(camera)
	camera.make_current()
	_truck = Node3D.new()
	_truck.name = "Truck"
	add_child(_truck)
	_board_stub = Node3D.new()
	_board_stub.name = "BoardStub"
	_board_stub.position = Vector3(1.5, 0.0, 3.0)
	add_child(_board_stub)
	_make_engine(&"chefty", Constants.ENGINE_RIDE_TOP_SPEED if _ride_t >= 0.0 else Constants.CHEFTY_TOP_SPEED)
	_board = _BoardSound.new()
	_board.set("state_source", func() -> Dictionary: return _board_state)
	_board_stub.add_child(_board)
	_build_ui()


func _process(delta: float) -> void:
	if _ride_t >= 0.0:
		_ride_t += delta
		var u := clampf(_ride_t / RIDE_SECONDS, 0.0, 1.0)
		_engine_state["on"] = true
		# smoothstep's speed, 6u(1-u) x length / time, peaks mid-way at RIDE_PEAK.
		_engine_state["speed"] = RIDE_PEAK * 4.0 * u * (1.0 - u)
		_engine_state["throttle"] = 1.0 if u < 0.5 else 0.0
		_engine_state["skidding"] = u >= Constants.ENGINE_RIDE_SKID_FROM and u < 1.0
		_speed_slider.set_value_no_signal(float(_engine_state["speed"]))
		if u >= 1.0:
			_ride_t = -1.0
			_engine_state["speed"] = 0.0
			_engine.call("arrive")
			_linger = Constants.ENGINE_IDLE_LINGER_SECONDS
	if _linger > 0.0:
		_linger -= delta
		if _linger <= 0.0:
			_engine_state["on"] = false
	if _ollie_t >= 0.0:
		_ollie_t += delta
		_board_state["on_ground"] = _ollie_t >= 0.55
		if _ollie_t >= 0.55:
			_ollie_t = -1.0
	_mood = _Director.pick_mood(_fake, _mood)
	if _mood_label != null:
		_mood_label.text = "pick_mood -> %s   tracks %s" % [_mood, _Tracks.tracks_for(String(_mood))]
	if _engine_label != null:
		_engine_label.text = "running %s  speed %.1f  mix %s" % [_engine.call("is_running"), float(_engine_state["speed"]), _rounded(_engine.call("current_mix"))]
	if _board_label != null:
		_board_label.text = "mix %s" % _rounded(_board.call("current_mix"))
	if _shot_path != "":
		_shot_wait -= delta
		if _shot_wait <= 0.0:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			get_tree().quit()
			_shot_path = ""


func _rounded(values: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in values:
		parts.append("%s %.2f" % [key, float(values[key])])
	return ", ".join(parts)


func _make_engine(profile: StringName, top: float) -> void:
	if _engine != null:
		_engine.queue_free()
	_engine = _VehicleSound.new()
	_engine.name = "VehicleSound"
	_engine.set("profile", profile)
	_engine.set("top_speed", top)
	_engine.set("state_source", func() -> Dictionary: return _engine_state)
	_truck.add_child(_engine)


# ---------------------------------------------------------------- the window

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var column := VBoxContainer.new()
	root.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var title := Label.new()
	title.text = "Leaf Me Alone jukebox"
	top.add_child(title)
	_now_playing = Label.new()
	_now_playing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_now_playing.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_now_playing)
	top.add_child(_button("Stop all", _stop_all))
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	tabs.add_child(_music_tab())
	tabs.add_child(_moods_tab())
	tabs.add_child(_sounds_tab())
	tabs.add_child(_engine_tab())
	tabs.add_child(_board_tab())
	tabs.current_tab = clampi(_first_tab, 0, tabs.get_tab_count() - 1)


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(pressed)
	return button


func _scroll(tab_name: String) -> Array:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return [scroll, box]


func _slider(box: Container, label: String, low: float, high: float, value: float, step: float, changed: Callable) -> HSlider:
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size.x = 160.0
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(changed)
	row.add_child(slider)
	var shown := Label.new()
	shown.custom_minimum_size.x = 60.0
	shown.text = "%.2f" % value
	slider.value_changed.connect(func(now: float) -> void: shown.text = "%.2f" % now)
	row.add_child(shown)
	return slider


func _check(box: Container, label: String, value: bool, toggled: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = label
	check.button_pressed = value
	check.toggled.connect(toggled)
	box.add_child(check)
	return check


func _option(box: Container, label: String, items: Array, selected: int, picked: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size.x = 160.0
	row.add_child(name_label)
	var option := OptionButton.new()
	for item: Variant in items:
		option.add_item(str(item))
	option.select(selected)
	option.item_selected.connect(picked)
	row.add_child(option)
	return option


# ---------------------------------------------------------------- music

func _music_tab() -> Control:
	var parts := _scroll("Music")
	var box: VBoxContainer = parts[1]
	for id: String in _Tracks.TRACKS:
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		var kind := "stinger" if _Tracks.is_stinger(id) else "loop %.0f s" % _Tracks.seconds(id)
		label.text = "%s  (%s, %s)" % [_Strings.track_title(_Tracks.title_key(id)), id, kind]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(_button("Play", _play_track.bind(id)))
		if not _Tracks.is_stinger(id):
			row.add_child(_button("End of loop", _play_track.bind(id, true)))
	return parts[0]


## Plays id the way the director does; near_end starts 6 s before the loop's end,
## to hear the seam.
func _play_track(id: String, near_end: bool = false) -> void:
	var path := str(_Tracks.track(id)["file"])
	if not ResourceLoader.exists(path):
		_now_playing.text = "%s is missing" % path
		return
	var stream := (load(path) as AudioStream).duplicate()
	if not _Tracks.is_stinger(id) and stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
		(stream as AudioStreamOggVorbis).loop_offset = _Tracks.loop_offset(id)
	_music.stream = stream
	_music.volume_db = (Constants.MUSIC_STINGER_DB if _Tracks.is_stinger(id) else Constants.MUSIC_TRACK_DB) + float(_Tracks.track(id).get("db", 0.0))
	_music.play(maxf(0.0, stream.get_length() - 6.0) if near_end else 0.0)
	_now_playing.text = "Now playing: %s" % _Strings.track_title(_Tracks.title_key(id))


# ---------------------------------------------------------------- moods

func _moods_tab() -> Control:
	var parts := _scroll("Moods")
	var box: VBoxContainer = parts[1]
	_mood_label = Label.new()
	box.add_child(_mood_label)
	_option(box, "net state", Net.State.keys(), int(_fake["net_state"]), func(index: int) -> void: _fake["net_state"] = index)
	_option(box, "zone", Net.Zone.keys(), int(_fake["zone"]), func(index: int) -> void: _fake["zone"] = index)
	_slider(box, "hour", 6.0, 26.0, float(_fake["hour"]), 0.25, func(value: float) -> void: _fake["hour"] = value)
	_slider(box, "heat", 0.0, 100.0, float(_fake["heat"]), 1.0, func(value: float) -> void: _fake["heat"] = value)
	_option(box, "raid phase", ["none", "warning", "chase"], 0, func(index: int) -> void: _fake["phase"] = [0, _Director.PHASE_WARNING, _Director.PHASE_CHASE][index])
	_check(box, "sleeping", false, func(on: bool) -> void: _fake["sleeping"] = on)
	_check(box, "summary card open", false, func(on: bool) -> void: _fake["summary_open"] = on)
	_check(box, "Annex urgent", false, func(on: bool) -> void: _fake["annex_urgent"] = on)
	box.add_child(_button("Play this mood", func() -> void:
		var tracks := _Tracks.tracks_for(String(_mood))
		if not tracks.is_empty():
			_play_track(tracks[0])
		else:
			_music.stop()
			_now_playing.text = "%s plays nothing" % _mood
	))
	return parts[0]


# ---------------------------------------------------------------- sounds

func _sounds_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Sounds"
	var row := HBoxContainer.new()
	tab.add_child(row)
	_filter = LineEdit.new()
	_filter.placeholder_text = "filter ids"
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.text_changed.connect(func(_text: String) -> void: _fill_sounds())
	row.add_child(_filter)
	row.add_child(_button("Play", _play_selected))
	_sound_list = ItemList.new()
	_sound_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sound_list.item_activated.connect(func(_index: int) -> void: _play_selected())
	tab.add_child(_sound_list)
	_fill_sounds()
	return tab


func _fill_sounds() -> void:
	_sound_list.clear()
	var ids: Array = _Bank.SOUNDS.keys()
	ids.sort()
	for id: String in ids:
		if _filter.text == "" or id.contains(_filter.text):
			var entry := _Bank.entry(id)
			_sound_list.add_item("%s%s  [%s]" % [id, "  (loop)" if bool(entry["loop"]) else "", entry["bus"]])
			_sound_list.set_item_metadata(_sound_list.item_count - 1, id)


## A one-shot plays 2D; a loop starts, and stops on the second press.
func _play_selected() -> void:
	var picked := _sound_list.get_selected_items()
	if picked.is_empty():
		return
	var id := str(_sound_list.get_item_metadata(picked[0]))
	if not bool(_Bank.entry(id)["loop"]):
		_sfx.call("play", id)
		_now_playing.text = "Sound: %s" % id
		return
	if _loops.has(id):
		(_loops[id] as AudioStreamPlayer).queue_free()
		_loops.erase(id)
		return
	var player := AudioStreamPlayer.new()
	player.stream = _SfxScript.looped(id)
	player.bus = _Bank.bus(id)
	player.volume_db = _Bank.db(id)
	add_child(player)
	player.play()
	_loops[id] = player
	_now_playing.text = "Loop: %s (press again to stop)" % id


func _stop_all() -> void:
	_music.stop()
	for id: String in _loops:
		(_loops[id] as AudioStreamPlayer).queue_free()
	_loops.clear()
	_engine_state["on"] = false
	_ride_t = -1.0
	_board_state["on_board"] = false
	_now_playing.text = ""


# ---------------------------------------------------------------- engine

func _engine_tab() -> Control:
	var parts := _scroll("Engine")
	var box: VBoxContainer = parts[1]
	_engine_label = Label.new()
	_engine_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_engine_label)
	_option(box, "profile", ["chefty (drivable, 19 m/s)", "chefty (legacy ride, 160 m/s)", "van"], 0, func(index: int) -> void:
		_make_engine([&"chefty", &"chefty", &"van"][index], [Constants.CHEFTY_TOP_SPEED, Constants.ENGINE_RIDE_TOP_SPEED, Constants.CHEFTY_TOP_SPEED][index])
		_speed_slider.max_value = [Constants.CHEFTY_TOP_SPEED, RIDE_PEAK, Constants.CHEFTY_TOP_SPEED][index]
	)
	_check(box, "engine on", false, func(on: bool) -> void: _engine_state["on"] = on)
	_speed_slider = _slider(box, "speed (m/s)", 0.0, Constants.CHEFTY_TOP_SPEED, 0.0, 0.1, func(value: float) -> void: _engine_state["speed"] = value)
	_throttle_slider = _slider(box, "throttle", -1.0, 1.0, 0.0, 0.05, func(value: float) -> void: _engine_state["throttle"] = value)
	_check(box, "skidding", false, func(on: bool) -> void: _engine_state["skidding"] = on)
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(_button("start()", func() -> void: _engine.call("start")))
	row.add_child(_button("arrive()", func() -> void: _engine.call("arrive")))
	row.add_child(_button("Legacy ride (8 s)", func() -> void: _ride_t = 0.0))
	return parts[0]


# ---------------------------------------------------------------- board

func _board_tab() -> Control:
	var parts := _scroll("Board")
	var box: VBoxContainer = parts[1]
	_board_label = Label.new()
	box.add_child(_board_label)
	_check(box, "on the board", true, func(on: bool) -> void: _board_state["on_board"] = on)
	_slider(box, "speed (m/s)", 0.0, Constants.SKATE_MAX_PUSH_SPEED * 1.3, 0.0, 0.1, func(value: float) -> void: _board_state["speed"] = value)
	_check(box, "on the ground", true, func(on: bool) -> void: _board_state["on_ground"] = on)
	_check(box, "grinding", false, func(on: bool) -> void: _board_state["grinding"] = on)
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(_button("Ollie", func() -> void: _ollie_t = 0.0))
	row.add_child(_button("pop()", func() -> void: _board.call("pop")))
	row.add_child(_button("land(1)", func() -> void: _board.call("land", 1.0)))
	row.add_child(_button("bail()", func() -> void: _board.call("bail")))
	return parts[0]
