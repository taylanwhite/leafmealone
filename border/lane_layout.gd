extends RefCounted

## Authority: data. OQ-022: difficulty scales hazard speed. The pad is the gray-box border zone.
## Four lanes so a cohort of up to four can cross together. Extra players share a lane.

const LANE_COUNT: int = 4
const LANE_WIDTH: float = 4.0
const HALF_LENGTH: float = 14.0


static func lane_center_x(lane: int) -> float:
	var index := posmod(lane, LANE_COUNT)
	return -6.0 + float(index) * LANE_WIDTH


static func hazard_count() -> int:
	return 8


## 0 is a rake that sweeps sideways. 1 is a bale that rolls along the lane.
static func kind(index: int) -> int:
	return 0 if index < 4 else 1


static func label_for(index: int) -> String:
	return "Rake" if kind(index) == 0 else "Bale"


static func mesh_size(index: int) -> Vector3:
	if kind(index) == 0:
		return Vector3(2.4, 0.25, 0.35)
	return Vector3(0.85, 0.85, 0.85)


static func hit_radius(index: int) -> float:
	return 1.15 if kind(index) == 0 else 0.7
