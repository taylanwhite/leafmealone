extends RefCounted

## Authority: none (pure). The curling till slip a player holds after the
## turnstile: 4 to 6 itemized lines written from their own raid and visit
## (Strings.RECEIPT_LINES, each "$0.00"), the time line, and the total. A pure
## function of (seed, stats, seconds, best), so the same visit prints the same
## slip on every peer and in every test.
##
## stats keys the Annex and the raid fill in (each > 0 when it happened): hid,
## piled, peeked, bonked, wriggled, loud, carbon, window_d, big_stamp, cosigned,
## closing, bell, wrong_window, redirect; heat (0-100, for the fee).
##
## Preload it (no class_name).

const _Strings = preload("res://ui/strings.gd")
const MIN_LINES: int = 4
const MAX_LINES: int = 6
## The order a slip lists what happened in, most memorable first.
const ORDER: Array[String] = ["window_d", "big_stamp", "closing", "cosigned", "bonked", "wriggled", "hid", "piled", "peeked", "loud", "carbon", "redirect", "bell", "wrong_window"]


## The itemized lines, then the time line. [] is never returned.
static func lines(seed_value: int, stats: Dictionary, annex_seconds: float, best_seconds: float) -> PackedStringArray:
	var out := PackedStringArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "receipt"])
	var pool: Dictionary = _Strings.RECEIPT_LINES
	for key: String in ORDER:
		if out.size() >= MAX_LINES:
			break
		if float(stats.get(key, 0.0)) <= 0.0 or not pool.has(key):
			continue
		out.append(_line(_pick(pool[key], rng)))
	# Topped up from the general pool, never the same line twice.
	var general: Array = (pool["general"] as Array).duplicate()
	while out.size() < MIN_LINES and not general.is_empty():
		var index := rng.randi_range(0, general.size() - 1)
		out.append(_line(str(general[index])))
		general.remove_at(index)
	var format: Dictionary = _Strings.RECEIPT_FORMAT
	if best_seconds > 0.0 and best_seconds < annex_seconds:
		out.append(str(format["time_best"]) % [clock(annex_seconds), clock(best_seconds)])
	else:
		out.append(str(format["time"]) % clock(annex_seconds))
	return out


## "TOTAL DUE $0.00" (BAL-28: the fee constants are 0, so it always is for now).
static func total_line(stats: Dictionary) -> String:
	return str(_Strings.RECEIPT_FORMAT["total"]) % money(fee(stats))


static func fee(stats: Dictionary) -> float:
	return float(Constants.ANNEX_FEE_BASE) + Constants.ANNEX_FEE_PER_HEAT * float(stats.get("heat", 0.0))


static func money(amount: float) -> String:
	return "%.2f" % maxf(amount, 0.0)


## 72.4 -> "1:12".
static func clock(seconds: float) -> String:
	var whole := maxi(int(round(seconds)), 0)
	return "%d:%02d" % [floori(whole / 60.0), whole % 60]


static func _line(label: String) -> String:
	return str(_Strings.RECEIPT_FORMAT["line"]) % [label, money(0.0)]


static func _pick(lines_in: Variant, rng: RandomNumberGenerator) -> String:
	var list: Array = lines_in
	return str(list[rng.randi_range(0, list.size() - 1)]) if not list.is_empty() else ""
