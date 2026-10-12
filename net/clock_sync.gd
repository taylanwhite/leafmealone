extends RefCounted

## Estimates the host clock on a client from ping samples.
## Authority: host clock, estimated on clients.

const SAMPLE_WINDOW_SECONDS: float = 10.0

var _origin_usec: int = 0
var _offset_seconds: float = 0.0
var _last_rtt_seconds: float = 0.0
var _has_sample: bool = false
var _samples: Array[Dictionary] = []


func start() -> void:
	_origin_usec = Time.get_ticks_usec()
	_offset_seconds = 0.0
	_samples.clear()


## Seconds since the session started on the host. On a client this is the estimate.
func server_seconds(is_host: bool) -> float:
	if is_host:
		return _local_seconds()
	return _local_seconds() + _offset_seconds


func local_seconds() -> float:
	return _local_seconds()


func offset_seconds() -> float:
	return _offset_seconds


func last_rtt_seconds() -> float:
	return _last_rtt_seconds


func has_sample() -> bool:
	return _has_sample


## offset = host_time + rtt / 2 - local_receive_time. Keep the lowest-rtt sample from the last 10 seconds.
func note_sample(sent_local_seconds: float, host_seconds: float, received_local_seconds: float) -> void:
	var rtt := received_local_seconds - sent_local_seconds
	if rtt < 0.0:
		return
	_last_rtt_seconds = rtt
	_has_sample = true
	_samples.append({"rtt": rtt, "offset": host_seconds + rtt * 0.5 - received_local_seconds, "at": received_local_seconds})
	var cutoff := received_local_seconds - SAMPLE_WINDOW_SECONDS
	var kept: Array[Dictionary] = []
	for sample: Dictionary in _samples:
		if float(sample["at"]) >= cutoff:
			kept.append(sample)
	_samples = kept
	var best_rtt := INF
	for sample: Dictionary in _samples:
		var sample_rtt := float(sample["rtt"])
		if sample_rtt < best_rtt:
			best_rtt = sample_rtt
			_offset_seconds = float(sample["offset"])


func _local_seconds() -> float:
	return float(Time.get_ticks_usec() - _origin_usec) / 1000000.0
