extends CanvasLayer

## Authority: local. Shows session facts for multiplayer debugging. Toggled with toggle_debug (F3).

var _label: Label
var _bandwidth_at: int = 0
var _bandwidth_last := Vector2i.ZERO
var _bandwidth_rate := Vector2.ZERO


func _ready() -> void:
	layer = 20
	visible = false
	add_to_group("debug_overlay")
	_label = Label.new()
	# Top right, so it does not cover the HUD hints in the top left.
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		visible = not visible
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F6:
		if not Net.is_host():
			return
		var director := get_tree().get_first_node_in_group("run_director")
		if director != null:
			director.call("force_event")
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	_label.text = _readout()


func _readout() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("transport %s" % Net.Transport.keys()[Net.current_transport()])
	lines.append("state %s" % Net.State.keys()[Net.current_state()])
	lines.append("peer %d  host %s" % [Net.local_peer_id(), Net.is_host()])
	lines.append("fps %d" % Engine.get_frames_per_second())
	lines.append("clock offset %.3f s  rtt %.3f s" % [Net.clock_offset_seconds(), Net.clock_rtt_seconds()])
	lines.append("synchronizers %d" % _synchronizer_count())
	lines.append(_bandwidth_text())
	lines.append("F6 host calls the NICE BOYS")
	for peer_id: int in Net.peer_ids():
		var ping := Net.peer_ping_ms(peer_id)
		var ping_text := "%d ms" % ping if ping >= 0 else "n/a"
		lines.append("%s  id %d  %s  %s  %s" % [
			Net.player_name(peer_id),
			peer_id,
			Net.Zone.keys()[Net.player_zone(peer_id)],
			ping_text,
			_loss_text(peer_id),
		])
	return "\n".join(lines)


func _loss_text(peer_id: int) -> String:
	if peer_id == Net.local_peer_id():
		return "loss n/a"
	var packet_peer := Net.enet_link(peer_id)
	if packet_peer == null or packet_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return "loss n/a"
	var raw := float(packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS))
	var loss := raw / float(ENetPacketPeer.PACKET_LOSS_SCALE)
	return "loss %.1f%%" % (loss * 100.0)


## Bytes per second over the last second. Needs the wrapper from --measure or --sim-lag.
func _bandwidth_text() -> String:
	var totals := Net.bandwidth_totals()
	if totals.x < 0:
		return "bandwidth n/a (run with --measure or --sim-lag)"
	var now := Time.get_ticks_msec()
	if now - _bandwidth_at >= 1000:
		var seconds := float(now - _bandwidth_at) / 1000.0
		_bandwidth_rate = Vector2(totals - _bandwidth_last) / seconds
		_bandwidth_last = totals
		_bandwidth_at = now
	var text := "bandwidth in %.1f KB/s  out %.1f KB/s" % [_bandwidth_rate.x / 1024.0, _bandwidth_rate.y / 1024.0]
	if Net.simulated_lag_ms() > 0:
		text += "  (simulated %d ms)" % Net.simulated_lag_ms()
	return text


func _synchronizer_count() -> int:
	var count := 0
	var pending: Array[Node] = [get_tree().root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.is_class("MultiplayerSynchronizer"):
			count += 1
		for child: Node in node.get_children():
			pending.append(child)
	return count
