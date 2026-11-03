extends RefCounted

## Authority: local presentation. Whether this peer's screen is in the cinematic
## HUD mode (R2b, docs/GAME.md "What's on screen during the encounter"): staged,
## held, caught, escorted, riding the Courtesy Shuttle, or in Satellite Annex B.
## While it is, the yard HUD (the job panel, the hotbar and its hints, the goal
## line, the interact prompts, cash, cleanup, Chefty's count, heat, the clock and
## rank) eases out and stays out, and comes back once you're back in control.
##
##   HudMode.reason(tree, peer_id) -> &"" or why (&"locked", &"stage", &"staged",
##                                    &"caught", &"van", &"annex")
##   HudMode.cinematic(tree, peer_id) -> bool
##
## Read only: it asks the player, the director, the Shuttle and Net; it decides
## nothing about gameplay.

## Stage shots that are the player's own view (hiding in a hedge or a pile: you
## still steer the peek), so they don't take the HUD away.
const OWN_SHOTS: Array[StringName] = [&"hide_peek", &"hide_orbit"]


static func cinematic(tree: SceneTree, peer_id: int) -> bool:
	return reason(tree, peer_id) != &""


static func reason(tree: SceneTree, peer_id: int) -> StringName:
	if tree == null or peer_id <= 0 or Net.current_state() != Net.State.IN_SESSION:
		return &""
	var me := _player(tree, peer_id)
	if me != null:
		if me.has_method("is_control_locked") and bool(me.call("is_control_locked")):
			return &"locked"
		if me.has_method("stage_top"):
			var top := StringName(me.call("stage_top"))
			if top != &"" and not OWN_SHOTS.has(top):
				return &"stage"
		if me.has_method("is_staged") and bool(me.call("is_staged")):
			return &"staged"
	var shuttle := tree.get_first_node_in_group("nice_shuttle")
	if shuttle != null and shuttle.has_method("seat_info") and not (shuttle.call("seat_info", peer_id) as Dictionary).is_empty():
		return &"van"
	# In the Annex you walk its lobby yourself (caught or visiting): the Annex's own
	# prompts stay (ui/interaction_prompt.gd).
	if Net.player_zone(peer_id) == Net.Zone.BORDER:
		return &"annex"
	var director := tree.get_first_node_in_group("run_director")
	if director != null and director.has_method("is_captured") and bool(director.call("is_captured", peer_id)):
		return &"caught"
	return &""


static func _player(tree: SceneTree, peer_id: int) -> Node:
	for node: Node in tree.get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node
	return null
