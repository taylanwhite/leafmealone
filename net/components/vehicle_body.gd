extends Node3D

## Authority: none (presentation). A drivable vehicle's rendered pose (Chefty's
## "Body", net/components/chefty_drive.gd). Things that ride along with the drawn
## truck hang under it, and some ask their parent about the vehicle: audio's
## audio/vehicle_sound.gd reads parent.engine_state() (gap-specs/critic.md C13),
## so the body hands that through to the vehicle.

var vehicle: Node


## {on, throttle (-1..1), speed (m/s), skidding}, the vehicle's engine_state().
func engine_state() -> Dictionary:
	if vehicle == null or not is_instance_valid(vehicle) or not vehicle.has_method("engine_state"):
		return {"on": false, "throttle": 0.0, "speed": 0.0, "skidding": false}
	return vehicle.call("engine_state")
