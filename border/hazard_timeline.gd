extends RefCounted

## Authority: nobody. A pure function of seed, hazard index, elapsed time, and difficulty.
## Integer phase plus a triangle wave, so Apple Silicon and x86 stay on the same path.
## OQ-022: difficulty multiplies speed.

const _Layout: Script = preload("res://border/lane_layout.gd")


static func position(seed: int, hazard_index: int, elapsed: float, difficulty: float) -> Vector3:
	var count := int(_Layout.call("hazard_count"))
	var index := posmod(hazard_index, count)
	var lane := index % int(_Layout.LANE_COUNT)
	var gate := int(index / int(_Layout.LANE_COUNT))
	var center_x := float(_Layout.call("lane_center_x", lane))
	var along := -8.0 + float(gate) * 8.0
	var phase := float(_mix(seed, index) % 1000) / 1000.0
	# One side, then the other, about every three seconds. The far side of the lane stays open.
	var cycle := 0.34 * maxf(difficulty, 0.1)
	var across := _wave(elapsed * cycle + phase)
	return Vector3(center_x + across * 1.0, 0.7, along)


static func _wave(t: float) -> float:
	var wrapped := fposmod(t, 1.0)
	if wrapped < 0.5:
		return wrapped * 4.0 - 1.0
	return 3.0 - wrapped * 4.0


static func _mix(seed: int, index: int) -> int:
	var value := seed * 1103515245 + index * 12345 + 99991
	return value & 0x7fffffff
