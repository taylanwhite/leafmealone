class_name Boarding
extends RefCounted

## OQ-002: who gets a seat. Replace this function when the boarding rule changes.
## OQ-003: anyone left out stays where they are.

# TODO(balance): the workbook does not give a boarding radius yet.
const BOARD_RADIUS_METERS: float = 8.0


static func choose_party(candidates: Array[int]) -> Array[int]:
	var party: Array[int] = []
	for peer_id: int in candidates:
		if party.size() >= Balance.EXPECTED_TRAVELING_PARTY_SIZE:
			break
		party.append(peer_id)
	return party
