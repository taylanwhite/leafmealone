extends RefCounted

## OQ-009: which trigger families are active is configuration.
## Time pressure, tool noise, random escalation, and player action stay off until the workbook picks them.
## The cleanup share that can roll a run event is Constants.RUN_PROGRESS_FRACTION.


static func progress_ready(fraction: float) -> bool:
	return fraction >= Constants.RUN_PROGRESS_FRACTION
