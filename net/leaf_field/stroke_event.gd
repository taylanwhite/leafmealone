class_name StrokeEvent
extends RefCounted

## One stroke on the leaf field, as the host tells every peer about it (raking:1,
## contract C1). Pure static: pack() a Dictionary into ~36 bytes for
## LeafField._rpc_stroke_event, unpack() it back with the derived keys filled in.
##
## Keys: kind (String, one of KINDS), actor (int: peer id, RAKE_ACTOR_HAND_BASE + N
## for hired hand "HandN", 0 for mower/scatter/plow), seq (int, u16: the raking
## client's request number), bite (int: 0 the plant bite, 1 mid-drive), at
## (Vector3, the request origin in world space), dir (Vector3, unit and flat),
## step (Vector2i, the field's 8-way step for dir), width (float, m), cells (int),
## moved (int, density units moved, removed or added), tempo (float, swing seconds,
## 0 unknown), t (float, Net.server_time() at the host's apply), ack_tick (int,
## the host batch tick that carries the change, -1 when nothing changes), local
## (bool, this peer's own stroke; always false from unpack).
## Consumers compare kind strings, never these constants, so they compile without it.

const KINDS: Array[String] = ["rake", "hand", "blower", "crew_rake", "bag", "crew_bag", "mulch", "scatter", "plow"]
## Wire layout, little-endian (PackedByteArray.encode_*): kind u8, cells u8, bite u8,
## flags u8 (bits 0-1 step.x + 1, bits 2-3 step.y + 1, bit 4 has step), seq u16,
## actor u32, at 3 x f32, yaw u16, width u8, moved u16, tempo u8, ack_tick s32, t f32.
const SIZE: int = 36
const WIDTH_STEP: float = 0.05


static func pack(ev: Dictionary) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SIZE)
	var kind := maxi(0, KINDS.find(str(ev.get("kind", "rake"))))
	bytes.encode_u8(0, kind)
	bytes.encode_u8(1, clampi(int(ev.get("cells", 0)), 0, 255))
	bytes.encode_u8(2, clampi(int(ev.get("bite", 0)), 0, 255))
	var dir: Vector3 = ev.get("dir", Vector3.ZERO)
	var step: Vector2i = ev.get("step", step_of(dir))
	var flags := (clampi(step.x, -1, 1) + 1) | ((clampi(step.y, -1, 1) + 1) << 2) | 16
	bytes.encode_u8(3, flags)
	bytes.encode_u16(4, int(ev.get("seq", 0)) & 0xFFFF)
	bytes.encode_u32(6, int(ev.get("actor", 0)) & 0xFFFFFFFF)
	var at: Vector3 = ev.get("at", Vector3.ZERO)
	bytes.encode_float(10, at.x)
	bytes.encode_float(14, at.y)
	bytes.encode_float(18, at.z)
	var yaw := atan2(dir.x, dir.z) if Vector2(dir.x, dir.z).length() > 0.0001 else 0.0
	bytes.encode_u16(22, int(round(fposmod(yaw, TAU) / TAU * 65536.0)) & 0xFFFF)
	bytes.encode_u8(24, clampi(int(round(float(ev.get("width", 0.0)) / WIDTH_STEP)), 0, 255))
	bytes.encode_u16(25, clampi(int(ev.get("moved", 0)), 0, 65535))
	bytes.encode_u8(27, clampi(int(round(float(ev.get("tempo", 0.0)) / Constants.LEAF_EVENT_TEMPO_STEP)), 0, 255))
	bytes.encode_s32(28, int(ev.get("ack_tick", -1)))
	bytes.encode_float(32, float(ev.get("t", 0.0)))
	return bytes


## The event back from its bytes, with dir, step and local = false filled in.
## {} when the bytes are too short to be one.
static func unpack(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < SIZE:
		return {}
	var kind := bytes.decode_u8(0)
	var flags := bytes.decode_u8(3)
	var yaw := float(bytes.decode_u16(22)) / 65536.0 * TAU
	var dir := Vector3(sin(yaw), 0.0, cos(yaw))
	var step := step_of(dir)
	if flags & 16:
		step = Vector2i((flags & 3) - 1, ((flags >> 2) & 3) - 1)
	return {
		"kind": KINDS[kind] if kind < KINDS.size() else "rake",
		"cells": bytes.decode_u8(1),
		"bite": bytes.decode_u8(2),
		"seq": bytes.decode_u16(4),
		"actor": bytes.decode_u32(6),
		"at": Vector3(bytes.decode_float(10), bytes.decode_float(14), bytes.decode_float(18)),
		"dir": dir,
		"step": step,
		"width": float(bytes.decode_u8(24)) * WIDTH_STEP,
		"moved": bytes.decode_u16(25),
		"tempo": float(bytes.decode_u8(27)) * Constants.LEAF_EVENT_TEMPO_STEP,
		"ack_tick": bytes.decode_s32(28),
		"t": bytes.decode_float(32),
		"local": false,
	}


## The leaf field's 8-way step for a direction: the same rounding _apply_rake uses.
static func step_of(direction: Vector3) -> Vector2i:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.001:
		return Vector2i(0, 1)
	flat = flat.normalized()
	var step := Vector2i(int(round(flat.x)), int(round(flat.z)))
	return Vector2i(0, 1) if step == Vector2i.ZERO else step
