extends RefCounted

## Authority: nobody. A pure function of seed, hazard index, elapsed time, and difficulty.
## Integer phase plus a triangle wave, so Apple Silicon and x86 stay on the same path.
## OQ-022: difficulty multiplies speed.

const _Layout: Script = preload("res://border/lane_layout.gd")


static func position(seed: int, hazard_index: int, elapsed: float, difficulty: float) -> Vector3:
	var index := posmod(hazard_index, int(_Layout.call("hazard_count")))
	var lane := index % int(_Layout.LANE_COUNT)
	var center_x := float(_Layout.call("lane_center_x", lane))
	var phase := float(_mix(seed, index) % 1000) / 1000.0
	var speed := (1.2 + float(index % 3) * 0.45) * maxf(difficulty, 0.1)
	if int(_Layout.call("kind", index)) == 0:
		var across := _wave(elapsed * speed * 0.18 + phase)
		var along := -12.0 + float(index) * 6.0
		return Vector3(center_x + across * 1.35, 0.75, along)
	var roll := _wave(elapsed * speed * 0.22 + phase)
	return Vector3(center_x, 0.5, roll * float(_Layout.HALF_LENGTH))


static func _wave(t: float) -> float:
	var wrapped := fposmod(t, 1.0)
	if wrapped < 0.5:
		return wrapped * 4.0 - 1.0
	return 3.0 - wrapped * 4.0


static func _mix(seed: int, index: int) -> int:
	var value := seed * 1103515245 + index * 12345 + 99991
	return value & 0x7fffffff
