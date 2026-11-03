extends RefCounted

## The beat clock (R2, docs/DECISIONS.md "Beats"). Every staged moment of the
## NICE BOYS encounter is a beat {kind, at, args}: the host sends it reliably with
## a server time `at`, and every peer plays it from that time with these helpers.
## A beat that arrives a little late fast-forwards; one that arrives later than
## Constants.BEAT_SKIP snaps to its end pose without its sound. Game logic never
## waits on an animation: the host times outcomes from constants.
## Preload it (no class_name): const _Beat = preload("res://net/run_events/beat.gd").


## When a beat with no anticipation of its own should play: now plus the lead,
## so a peer 150 ms away still sees it start on time.
static func lead_at() -> float:
	return Net.server_time() + Constants.BEAT_LEAD


## How late this peer is for a beat at `at`, in seconds (0 when it's still ahead).
static func late(at: float) -> float:
	return maxf(0.0, Net.server_time() - at)


## How far through a beat of `duration` seconds that started at `at`, 0 to 1.
static func progress(at: float, duration: float) -> float:
	if duration <= 0.0:
		return 1.0 if Net.server_time() >= at else 0.0
	return clampf((Net.server_time() - at) / duration, 0.0, 1.0)


## Whether the beat's sound should still play here (not later than BEAT_SKIP).
static func plays_sound(at: float) -> bool:
	return Net.server_time() - at <= Constants.BEAT_SKIP


## Whether this peer is so late it should jump to the beat's end pose, silently.
static func should_snap(at: float) -> bool:
	return late(at) > Constants.BEAT_SKIP
