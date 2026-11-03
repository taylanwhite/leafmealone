extends Node

## Authority: host. The hotbar, or "pockets" (docs/GAME.md, "2026-11-01, the
## hotbar"): five slots of things you carry, keys 1 to 5. What anyone carries
## lives on the props themselves (net/components/net_prop.gd held_by,
## pocketed_by, pocket_slot), so it replicates and late-joins for free; this node
## only keeps each peer's selected slot and decides, on the host, what comes out
## into whose hands. Clients ask (request_select); the host validates and settles;
## the result replicates through the props. Built on every peer like
## World/Brawl, so the RPCs have the same path everywhere.
##
## The host's one invariant lives in host_settle: at most one prop held per peer,
## and every other pocket item pocketed. With a big item (arms, shoulder, push) in
## hand, every pocket item stays pocketed. Settle always pockets before it draws.

const _PropLooks = preload("res://props/prop_looks.gd")
const REFUSE: int = -2
const BIG: int = -1

## peer id -> selected slot, -1 for bare hands. Host only.
var _selected: Dictionary = {}
## peer id -> where they last stood in the yard, sampled each physics tick on the
## host, so emptied pockets land on the yard, not wherever a teleport took them.
var _last_lot_spot: Dictionary = {}
## Host: the itemized rows still popping out ({peer, item, at, when, index}).
var _row_queue: Array[Dictionary] = []
## How many are still to pop (host), and the pops every peer played, for tests.
var row_log_size: int = 0
var itemized_log: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("hotbar")
	if not Net.player_zone_changed.is_connected(_on_zone_changed):
		Net.player_zone_changed.connect(_on_zone_changed)
	if not Net.player_left.is_connected(_on_player_left):
		Net.player_left.connect(_on_player_left)


# ---------------------------------------------------------------- every peer

## "pocket", "arms", "shoulder" or "push" (Constants.ITEM_CARRY). Unknown kinds
## are "arms": safe, never pocketable.
static func carry_class(kind: String) -> String:
	return str(Constants.ITEM_CARRY.get(kind, "arms"))


static func is_pocketable(kind: String) -> bool:
	return carry_class(kind) == "pocket"


## How many of this kind fit in one slot (Constants.HOTBAR_STACK), else 1.
static func stack_size(kind: String) -> int:
	return maxi(1, int(Constants.HOTBAR_STACK.get(kind, 1)))


## How many slots this peer has. One function, so a Tool Belt can change it.
static func capacity(_peer_id: int) -> int:
	return Constants.HOTBAR_SLOTS


## Everything this peer carries: in hand or in a pocket.
static func items_of(tree: SceneTree, peer_id: int) -> Array[Node]:
	var items: Array[Node] = []
	if peer_id == 0:
		return items
	for node: Node in tree.get_nodes_in_group("props"):
		if node.is_queued_for_deletion():
			continue
		if int(node.get("held_by")) == peer_id or int(node.get("pocketed_by")) == peer_id:
			items.append(node)
	return items


## capacity(peer) entries, each the props in that slot, sorted by node name (the
## same on every peer). The first of a stack is the one that comes out.
static func slots_of(tree: SceneTree, peer_id: int) -> Array:
	var count := capacity(peer_id)
	var slots: Array = []
	for _index: int in count:
		slots.append([])
	for item: Node in items_of(tree, peer_id):
		var slot := int(item.get("pocket_slot"))
		if slot >= 0 and slot < count and is_pocketable(str(item.get("kind"))):
			(slots[slot] as Array).append(item)
	for slot: Array in slots:
		slot.sort_custom(func(a: Node, b: Node) -> bool: return str(a.name) < str(b.name))
	return slots


## Whether one more of this pocket kind fits: an empty slot, or a stack of the
## same kind with room. What the pickup prompt checks before saying "Pockets full".
static func has_room(tree: SceneTree, peer_id: int, kind: String) -> bool:
	var stack := stack_size(kind)
	for slot: Array in slots_of(tree, peer_id):
		if slot.is_empty():
			return true
		if stack > 1 and str(slot[0].get("kind")) == kind and slot.size() < stack:
			return true
	return false


## The big item (not pocketable) this peer holds in both hands, or null.
static func arms_item(tree: SceneTree, peer_id: int) -> Node:
	for item: Node in items_of(tree, peer_id):
		if int(item.get("held_by")) == peer_id and not is_pocketable(str(item.get("kind"))):
			return item
	return null


## Whatever this peer has in hand, or null.
static func in_hand(tree: SceneTree, peer_id: int) -> Node:
	for item: Node in items_of(tree, peer_id):
		if int(item.get("held_by")) == peer_id:
			return item
	return null


## What every player carries, keyed by player name, for net/dev/probe.gd: slots
## as [kind, count] ("" and 0 when empty), the kind in hand, and grip_ok: whether
## the held item's grips resolve on this peer, from its own replicated view, within
## reach of the holder's shoulders (props/prop_looks.gd grips_ok; true when the
## hands are empty). A client agreeing with the host proves remote holds land.
static func snapshot(tree: SceneTree) -> Dictionary:
	var out: Dictionary = {}
	var names: Array[String] = []
	var ids: Dictionary = {}
	var bodies: Dictionary = {}
	for node: Node in tree.get_nodes_in_group("players"):
		var peer_id := node.name.to_int()
		if peer_id <= 0:
			continue
		var shown := Net.player_name(peer_id)
		if shown == "":
			shown = str(peer_id)
		names.append(shown)
		ids[shown] = peer_id
		bodies[shown] = node
	names.sort()
	for shown: String in names:
		var peer_id := int(ids[shown])
		var slots: Array = []
		for slot: Array in slots_of(tree, peer_id):
			slots.append([str(slot[0].get("kind")) if not slot.is_empty() else "", slot.size()])
		var hand := in_hand(tree, peer_id)
		var grip_ok := hand == null or _PropLooks.grips_ok(hand as Node3D, bodies[shown] as Node3D)
		out[shown] = {"slots": slots, "hand": str(hand.get("kind")) if hand != null else "", "grip_ok": grip_ok}
	return out


## Ask to have this slot in hand (-1 puts your hands away). The caller resolves
## "the same number again means bare hands" (player/pockets.gd select), so the
## host applies exactly what was asked.
func request_select(slot: int) -> void:
	if Net.is_host():
		_handle_select(Net.local_peer_id(), slot)
	else:
		_rpc_request_select.rpc_id(1, slot)


# ---------------------------------------------------------------- host

## The slot this peer has selected on the host, -1 for bare hands. New players
## start on slot 1, so the first pickup lands there.
func selected_of(peer_id: int) -> int:
	return int(_selected.get(peer_id, 0))


func _handle_select(peer_id: int, slot: int) -> void:
	var player := _player(peer_id)
	if player == null:
		return
	var count := capacity(peer_id)
	if slot < -1 or slot >= count:
		_send_selected(peer_id, selected_of(peer_id))
		return
	# Bare hands are always allowed: hiding, piles and cots put your hands away.
	if slot >= 0:
		if arms_item(get_tree(), peer_id) != null:
			host_refuse(peer_id, "arms_full")
			_send_selected(peer_id, selected_of(peer_id))
			return
		if _busy(player) or float(player.call("wind_up_seconds")) >= 0.0:
			_send_selected(peer_id, selected_of(peer_id))
			return
	_selected[peer_id] = slot
	host_settle(peer_id)


## Where a pickup goes: REFUSE (-2) when the arms are full or there's no room
## (refusal_reason says which), BIG (-1) for a thing that fills both hands, else
## the slot: a stack of the same kind with room, the selected slot if it's empty,
## or the first empty one.
func host_slot_for_pickup(peer_id: int, prop: Node) -> int:
	if arms_item(get_tree(), peer_id) != null:
		return REFUSE
	var kind := str(prop.get("kind"))
	if not is_pocketable(kind):
		return BIG
	var slots := slots_of(get_tree(), peer_id)
	var stack := stack_size(kind)
	if stack > 1:
		for index: int in slots.size():
			var slot: Array = slots[index]
			if not slot.is_empty() and str(slot[0].get("kind")) == kind and slot.size() < stack and not slot.has(prop):
				return index
	var selected := selected_of(peer_id)
	if selected >= 0 and selected < slots.size() and (slots[selected] as Array).is_empty():
		return selected
	for index: int in slots.size():
		if (slots[index] as Array).is_empty():
			return index
	return REFUSE


## Why host_slot_for_pickup refused: "arms_full" or "full".
func refusal_reason(peer_id: int) -> String:
	return "arms_full" if arms_item(get_tree(), peer_id) != null else "full"


## Select a slot without asking (a pickup moves the selection to where it went).
func host_select_silently(peer_id: int, slot: int) -> void:
	_selected[peer_id] = slot
	_send_selected(peer_id, slot)


## Make hands and pockets match the selection: every pocket item that shouldn't
## be in hand goes in its pocket first, then the first of the selected slot's
## stack comes out, unless a big item fills the hands. Also repairs pocket items
## without a slot (say one was handed over by older code): they get the first
## slot with room, or are set down if there is none.
func host_settle(peer_id: int) -> void:
	var tree := get_tree()
	var player := _player(peer_id)
	var count := capacity(peer_id)
	for item: Node in items_of(tree, peer_id):
		var kind := str(item.get("kind"))
		if not is_pocketable(kind):
			if int(item.get("pocket_slot")) != -1:
				item.set("pocket_slot", -1)
			continue
		var slot := int(item.get("pocket_slot"))
		if slot >= 0 and slot < count:
			continue
		var room := _room_for(peer_id, item)
		if room >= 0:
			item.set("pocket_slot", room)
		else:
			var at: Vector3 = (player as Node3D).global_position + Vector3.UP * Constants.CONFISCATE_DROP_HEIGHT if player != null else (item as Node3D).global_position
			item.call("host_unown", at, Vector3.ZERO)
	var want: Node = null
	var selected := selected_of(peer_id)
	if arms_item(tree, peer_id) == null and selected >= 0 and player != null and not _busy(player):
		var slots := slots_of(tree, peer_id)
		if selected < slots.size() and not (slots[selected] as Array).is_empty():
			want = (slots[selected] as Array)[0]
	for item: Node in items_of(tree, peer_id):
		if item != want and int(item.get("held_by")) == peer_id and is_pocketable(str(item.get("kind"))):
			item.call("host_pocket", peer_id)
	if want != null and int(want.get("held_by")) != peer_id:
		want.call("host_draw", peer_id)


## A big pickup is coming: the pocket item in hand goes in its pocket first.
## The selection stays, so setting the big thing down draws it again.
func host_clear_hands(peer_id: int) -> void:
	for item: Node in items_of(get_tree(), peer_id):
		if int(item.get("held_by")) == peer_id and is_pocketable(str(item.get("kind"))):
			item.call("host_pocket", peer_id)


## Hands away entirely (a Chefty seat, critic C23): bare hands, and a big item is set down.
func host_stow_hands(peer_id: int) -> void:
	_selected[peer_id] = -1
	_send_selected(peer_id, -1)
	var big := arms_item(get_tree(), peer_id)
	if big != null:
		big.call("force_release")
	host_settle(peer_id)


## Everything this peer carries pops out where they were on the yard, a little
## apart, and they hear why: "confiscated", "left" (walked off the job), "gone"
## (disconnected; nobody to tell). "itemized" is the NICE BOYS' catch (R2 chunk 2,
## net/run_events/encounter.gd): the thing in hand, then each pocket in order, pops
## out one every Constants.CATCH_ITEM_GAP s into a straight row CATCH_ROW_SPACING m
## apart, across row_dir from row_origin, each with a rising tick. No toast: the row
## on the lawn says it.
func host_empty_pockets(peer_id: int, reason: String, row_origin: Vector3 = Vector3.INF, row_dir: Vector3 = Vector3.ZERO) -> void:
	var items := items_of(get_tree(), peer_id)
	_selected[peer_id] = -1
	if items.is_empty():
		return
	if reason == "itemized":
		_queue_row(peer_id, items, row_origin, row_dir)
		_send_selected(peer_id, -1)
		return
	var player := _player(peer_id)
	var center: Vector3 = _last_lot_spot.get(peer_id, (player as Node3D).global_position if player != null else (items[0] as Node3D).global_position)
	center = _on_pad(center)
	var radius := 0.0 if items.size() == 1 else maxf(Constants.CONFISCATE_SPREAD, Constants.CONFISCATE_SPREAD * float(items.size()) / TAU)
	for index: int in items.size():
		var angle := TAU * float(index) / float(items.size())
		var at := center + Vector3(cos(angle), 0.0, sin(angle)) * radius + Vector3.UP * Constants.CONFISCATE_DROP_HEIGHT
		# Each one pops a little higher than the last, so they land one after another: itemized.
		var pop := Vector3.UP * Constants.CONFISCATE_POP * (1.0 + Constants.CONFISCATE_POP_STEP * float(index))
		items[index].call("host_unown", at, pop)
	if reason != "gone":
		_send_selected(peer_id, -1)
		_send_notice(peer_id, reason)


## The itemized row: what's in hand first, then the pockets by slot.
func _queue_row(peer_id: int, items: Array[Node], origin: Vector3, facing: Vector3) -> void:
	var player := _player(peer_id) as Node3D
	if not origin.is_finite():
		origin = player.global_position if player != null else (items[0] as Node3D).global_position
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length() < 0.01:
		flat = -player.global_basis.z if player != null else Vector3.FORWARD
	var across := flat.normalized().cross(Vector3.UP).normalized()
	items.sort_custom(func(a: Node, b: Node) -> bool:
		var a_held := int(a.get("held_by")) == peer_id
		var b_held := int(b.get("held_by")) == peer_id
		if a_held != b_held:
			return a_held
		if int(a.get("pocket_slot")) != int(b.get("pocket_slot")):
			return int(a.get("pocket_slot")) < int(b.get("pocket_slot"))
		return str(a.name) < str(b.name))
	var start := Net.server_time()
	for index: int in items.size():
		var at := _on_pad(origin + across * Constants.CATCH_ROW_SPACING * float(index))
		_row_queue.append({"peer": peer_id, "item": items[index], "at": at, "when": start + Constants.CATCH_ITEM_GAP * float(index), "index": index})


## Host: pop the row's items whose turn has come.
func _step_row() -> void:
	var now := Net.server_time()
	for entry: Dictionary in _row_queue.duplicate():
		if now < float(entry["when"]):
			continue
		_row_queue.erase(entry)
		var item := entry["item"] as Node
		var peer_id := int(entry["peer"])
		if not is_instance_valid(item) or (int(item.get("held_by")) != peer_id and int(item.get("pocketed_by")) != peer_id):
			continue
		var at: Vector3 = entry["at"]
		# Out of their hands and pockets, in a little arc onto its spot in the row
		# (never a teleport to it).
		var player := _player(peer_id) as Node3D
		var from := at + Vector3.UP * Constants.CONFISCATE_DROP_HEIGHT
		var throw := Vector3.UP * Constants.CONFISCATE_POP
		if player != null:
			var toward := at - player.global_position
			toward.y = 0.0
			from = player.global_position + Vector3.UP * 1.1 + toward.normalized() * minf(0.45, toward.length())
			var flight := Constants.CATCH_ITEM_FLIGHT
			var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
			var span := at + Vector3.UP * 0.15 - from
			throw = Vector3(span.x / flight, (span.y + 0.5 * gravity * flight * flight) / flight, span.z / flight)
		item.call("host_unown", from, throw)
		_rpc_itemized.rpc(from, int(entry["index"]))
	row_log_size = _row_queue.size()


## Every peer: one item out of the row, with a tick that rises item by item.
@rpc("authority", "call_local", "reliable")
func _rpc_itemized(at: Vector3, index: int) -> void:
	itemized_log.append({"at": at, "index": index})
	if itemized_log.size() > 32:
		itemized_log.pop_front()
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx == null:
		return
	var world := get_tree().get_first_node_in_group("world") as Node3D
	var marker := Node3D.new()
	if world == null:
		sfx.call("play", "itemize_pop")
		return
	world.add_child(marker)
	marker.global_position = at
	sfx.call("play_on", "itemize_pop", marker, 0.0, false)
	for child: Node in marker.get_children():
		if child is AudioStreamPlayer3D:
			(child as AudioStreamPlayer3D).pitch_scale = 1.0 + 0.09 * float(index)
	get_tree().create_timer(0.6).timeout.connect(marker.queue_free)


## Tell this peer no, and why ("full", "arms_full").
func host_refuse(peer_id: int, reason: String) -> void:
	if peer_id == Net.local_peer_id():
		_on_refused_local(reason)
	elif Net.peer_ids().has(peer_id):
		_rpc_refused.rpc_id(peer_id, reason)


func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not Net.is_host():
		return
	if not _row_queue.is_empty():
		_step_row()
	var tree := get_tree()
	for node: Node in tree.get_nodes_in_group("players"):
		var player := node as Node3D
		var peer_id := node.name.to_int()
		if player == null or peer_id <= 0:
			continue
		if Net.player_zone(peer_id) == Net.Zone.LOT:
			_last_lot_spot[peer_id] = player.global_position
		# Nothing in hand but something selected (a held bag went into Chefty, say):
		# the selected item comes back out.
		var selected := selected_of(peer_id)
		if selected >= 0 and in_hand(tree, peer_id) == null and not _busy(player):
			var slots := slots_of(tree, peer_id)
			if selected < slots.size() and not (slots[selected] as Array).is_empty():
				host_settle(peer_id)


## Leaving the yard mid-job (to the store, say) leaves your stuff where you last
## stood on it. In the connected town walking to the curb changes zones all the
## time, so there the rule is distance from the site instead (critic C23, the
## driving spec's chunk D), not zone changes.
func _on_zone_changed(peer_id: int, zone: Net.Zone) -> void:
	if not Net.is_host() or zone == Net.Zone.LOT or not Campaign.is_job_open():
		return
	var world := get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("is_town_map") and bool(world.call("is_town_map")):
		return
	host_empty_pockets(peer_id, "left")


func _on_player_left(peer_id: int) -> void:
	if not Net.is_host():
		return
	host_empty_pockets(peer_id, "gone")
	_selected.erase(peer_id)
	_last_lot_spot.erase(peer_id)


# ---------------------------------------------------------------- helpers

## A slot with room for this item, ignoring its own (invalid) slot, or -1.
func _room_for(peer_id: int, item: Node) -> int:
	var kind := str(item.get("kind"))
	var slots := slots_of(get_tree(), peer_id)
	if stack_size(kind) > 1:
		for index: int in slots.size():
			var slot: Array = slots[index]
			if not slot.is_empty() and str(slot[0].get("kind")) == kind and slot.size() < stack_size(kind):
				return index
	for index: int in slots.size():
		if (slots[index] as Array).is_empty():
			return index
	return -1


## Hidden, in a pile, asleep, carried, carrying a teammate (both arms are full
## of them), or in a Chefty seat (hands on the wheel or the rail): nothing comes
## out of a pocket.
func _busy(player: Node) -> bool:
	if player.has_method("in_vehicle") and bool(player.call("in_vehicle")):
		return true
	return bool(player.call("is_hidden")) or bool(player.call("is_sleeping")) or int(player.get("carried_by")) != 0 or int(player.get("carrying")) != 0


## A point pulled inside the yard's pad (Constants.PAD_RECTS), so emptied
## pockets never land in the street or over a fence.
func _on_pad(at: Vector3) -> Vector3:
	var world := get_tree().get_first_node_in_group("world")
	var zone := world.get_node_or_null("LotZone") as Node3D if world != null else null
	if zone == null:
		return at
	var rect: Rect2 = Constants.PAD_RECTS.get("LotZone", Rect2(-20.0, -20.0, 40.0, 40.0))
	var inner := rect.grow(-Constants.CONFISCATE_PAD_INSET)
	var local := at - zone.global_position
	if Vector2(local.x, local.z).length() > Constants.CONFISCATE_NEAR_YARD_METERS:
		# Nowhere near the yard (it moved, or this is the store): leave it be.
		return at
	return zone.global_position + Vector3(clampf(local.x, inner.position.x, inner.end.x), local.y, clampf(local.z, inner.position.y, inner.end.y))


func _player(peer_id: int) -> Node:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node
	return null


func _send_selected(peer_id: int, slot: int) -> void:
	if peer_id == Net.local_peer_id():
		var pockets := _local_pockets()
		if pockets != null:
			pockets.call("on_selected", slot)
	elif Net.peer_ids().has(peer_id):
		_rpc_selected.rpc_id(peer_id, slot)


func _send_notice(peer_id: int, kind: String) -> void:
	if peer_id == Net.local_peer_id():
		_on_notice_local(kind)
	elif Net.peer_ids().has(peer_id):
		_rpc_notice.rpc_id(peer_id, kind)


func _local_pockets() -> Node:
	var player := _player(Net.local_peer_id())
	return player.get_node_or_null("Pockets") if player != null else null


func _on_refused_local(reason: String) -> void:
	var pockets := _local_pockets()
	if pockets != null:
		pockets.call("on_refused", reason)


func _on_notice_local(kind: String) -> void:
	var pockets := _local_pockets()
	if pockets != null:
		pockets.call("on_notice", kind)


# ---------------------------------------------------------------- RPCs

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_select(slot: int) -> void:
	if Net.is_host():
		_handle_select(multiplayer.get_remote_sender_id(), slot)


## Host to the owner: your selection is this (after a refusal or a pickup).
@rpc("authority", "call_remote", "reliable")
func _rpc_selected(slot: int) -> void:
	var pockets := _local_pockets()
	if pockets != null:
		pockets.call("on_selected", slot)


@rpc("authority", "call_remote", "reliable")
func _rpc_refused(reason: String) -> void:
	_on_refused_local(reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_notice(kind: String) -> void:
	_on_notice_local(kind)
