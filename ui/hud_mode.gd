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
## still steer the peek), so they don't take the HUD away. R2c: and the eye's
## move back out of a hedge (hide_move): the dive keeps the HUD, so the climb
## out does too (it used to blink the whole HUD out for 1.3 s). Being pulled out
## by a NICE BOY rides the same shot but is his moment (reason() checks it first).
const OWN_SHOTS: Array[StringName] = [&"hide_peek", &"hide_orbit", &"hide_move"]

## R2c: per peer, the last stage shot seen on top, and when (msec) the moment
## last had this peer or a stage shot last swung its camera (overlays_held).
static var _last_top: Dictionary = {}
static var _busy_at: Dictionary = {}


static func cinematic(tree: SceneTree, peer_id: int) -> bool:
	return reason(tree, peer_id) != &""


static func reason(tree: SceneTree, peer_id: int) -> StringName:
	if tree == null or peer_id <= 0 or Net.current_state() != Net.State.IN_SESSION:
		return &""
	var me := _player(tree, peer_id)
	if me != null:
		if me.has_method("is_control_locked") and bool(me.call("is_control_locked")):
			return &"locked"
		# R2c: hauled out by a NICE BOY is his moment, not your climb-out: the eye's
		# move home (hide_move) is your own shot only when you climbed out yourself.
		var hide_view := me.get_node_or_null("HideView")
		if hide_view != null and hide_view.has_method("is_pulled") and bool(hide_view.call("is_pulled")):
			return &"stage"
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


## R2c: whether the words that float in the world for you (the interact prompt,
## everyone's name tags) wait: while the moment has you (the Annex aside, where
## your crew's names and the Annex's prompts are wanted), while a stage camera
## that isn't your own view is still swinging back to your eyes, and for
## R2C_HUD_OVERLAY_DELAY after both, so nothing pops on mid-swing (the freed
## friend's "[E] Pick up Gnome" and Lance's tag during the hand-back).
static func overlays_held(tree: SceneTree, peer_id: int) -> bool:
	var now := Time.get_ticks_msec()
	var why := reason(tree, peer_id)
	if why == &"annex":
		return false
	var busy := why != &""
	var me := _player(tree, peer_id)
	if not busy and me != null and me.has_method("stage_cam"):
		var cam := me.call("stage_cam") as Node
		if cam != null and cam.has_method("is_live") and bool(cam.call("is_live")):
			var top := StringName(cam.call("top"))
			if top != &"":
				_last_top[peer_id] = top
			# Blending back from a shot: busy unless that shot was your own view.
			busy = not OWN_SHOTS.has(StringName(_last_top.get(peer_id, &"")))
	if busy:
		_busy_at[peer_id] = now
		return true
	return now - int(_busy_at.get(peer_id, -100000)) < int(Constants.R2C_HUD_OVERLAY_DELAY * 1000.0)


static func _player(tree: SceneTree, peer_id: int) -> Node:
	for node: Node in tree.get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node
	return null
