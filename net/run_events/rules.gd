extends RefCounted

## OQ-009: which trigger families are active is configuration.
## Time pressure, tool noise, random escalation, and player action stay off until the workbook picks them.
## TODO(balance): the cleanup share that can roll a run event is not in the workbook yet.

const PROGRESS_FRACTION: float = 0.1


static func progress_ready(fraction: float) -> bool:
	return fraction >= PROGRESS_FRACTION
