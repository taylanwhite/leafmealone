extends RefCounted

## Authority: data. OQ-022: difficulty scales hazard speed. The pad is the gray-box border zone.
## Four lanes so a cohort of up to four can cross together. Extra players share a lane.
## The gray-box exit opens after Constants.BORDER_CROSSING_SECONDS.

const LANE_COUNT: int = 4
const LANE_WIDTH: float = 4.0
const HALF_LENGTH: float = 14.0


static func lane_center_x(lane: int) -> float:
	var index := posmod(lane, LANE_COUNT)
	return -6.0 + float(index) * LANE_WIDTH


static func hazard_count() -> int:
	return 12


## Every hazard is a gate that sweeps one side of its lane, then the other.
static func kind(_index: int) -> int:
	return 0


static func label_for(_index: int) -> String:
	return "Rake"


static func mesh_size(_index: int) -> Vector3:
	return Vector3(1.1, 0.35, 0.45)


static func hit_radius(_index: int) -> float:
	return 0.55
