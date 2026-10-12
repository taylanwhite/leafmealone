extends Node

## Authority: host
## Persistent campaign state. M1 exposes the final API and does not grant credits,
## unlocks, or saves. Later milestones fill these in without changing the signatures.

signal campaign_loaded
signal credits_changed(peer_id: int, credits: int)
signal unlocks_changed
signal job_stats_changed(peer_id: int)
signal payout_ready(results: Array[Dictionary])


func _ready() -> void:
	campaign_loaded.emit()


## Credits currently held by one player. Always 0 until payout exists.
func credits(_peer_id: int) -> int:
	return 0


## Whether an unlock from the workbook (UN-xx) is owned. None are owned in M1.
func is_unlocked(_unlock_id: StringName) -> bool:
	return false


## How many lots the host has finished.
func lots_completed() -> int:
	return 0


## Lot number to load for the next job. Lot 1 until the campaign loop exists.
func current_lot_index() -> int:
	return 1


## leaves_cleared, rescues, and objectives for the current job.
func job_stats(_peer_id: int) -> Dictionary:
	return {
		"leaves_cleared": 0.0,
		"rescues": 0.0,
		"objectives": 0.0,
	}


## Ask the host to buy an item. Ignored until the store exists.
func request_purchase(_item_id: StringName) -> void:
	pass


## Host only. Add to a player's job stats. Ignored until the leaf field exists.
func record_stat(_peer_id: int, _stat: StringName, _amount: float) -> void:
	pass


## Host only. Compute payout and save. Ignored until jobs exist.
func finish_job() -> void:
	pass


## Host only. Write the campaign save. Ignored until saves exist.
func save_now() -> void:
	pass
