extends Node

## Authority: host. Local JSON log for one session. Clients do not write it.
## BL-009. The file is user://logs, not the repo.

var _events: Array[Dictionary] = []
var _path: String = ""
var _job_started_msec: int = 0
var _border_started_msec: int = 0
var _logging: bool = false


func _ready() -> void:
	add_to_group("telemetry")
	if not Net.state_changed.is_connected(_on_state):
		Net.state_changed.connect(_on_state)
	# Hosting from the command line can already be in session before this node connects.
	_on_state(Net.current_state())


func _on_state(next_state: Net.State) -> void:
	if _logging or next_state != Net.State.IN_SESSION:
		return
	if not Net.is_host() or Net.is_automated():
		return
	_logging = true
	var directory := DirAccess.open("user://")
	if directory != null and not directory.dir_exists("logs"):
		directory.make_dir("logs")
	_path = "user://logs/session_%d.json" % int(Time.get_unix_time_from_system())
	event("session_start", {})


func _exit_tree() -> void:
	event("session_end", {})


func event(event_name: String, data: Dictionary) -> void:
	if not _logging:
		return
	_events.append({
		"t": Net.server_time(),
		"event": event_name,
		"data": data,
	})
	_flush()


func mark_job_start() -> void:
	_job_started_msec = Time.get_ticks_msec()
	event("job_start", {})


func mark_job_finish(cleanup: float, payouts: Array) -> void:
	var seconds := float(Time.get_ticks_msec() - _job_started_msec) / 1000.0
	event("job_finish", {
		"seconds": seconds,
		"cleanup": cleanup,
		"payouts": payouts,
	})


func mark_border_start() -> void:
	_border_started_msec = Time.get_ticks_msec()
	event("border_start", {})


func mark_border_finish(peer_id: int) -> void:
	var seconds := float(Time.get_ticks_msec() - _border_started_msec) / 1000.0
	event("border_finish", {"peer_id": peer_id, "seconds": seconds})


func _flush() -> void:
	if _path == "":
		return
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"events": _events}, "\t"))
