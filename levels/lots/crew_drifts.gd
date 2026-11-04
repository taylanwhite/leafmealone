extends RefCounted

## Every peer, from the seed. balance:E: a smaller crew gets a smaller yard in
## area, not a thinner one (Constants.CREW_WORK_SCALE). LeafField.cleaned_fraction()
## counts cells, so thinning every cell left a solo player raking the whole lawn
## for 60% of the bags (the review's rake_pace run: 60% of the leaves took 90% of
## the time). Instead the leaves lie in a few wind-blown drifts covering that share
## of the leafy lawn, and the rest of the grass starts clean: the field counts it
## clean at start, so it isn't part of the job. levels/lots/lot_generator.gd and
## tools/rake_pace.gd shape their yards through here.

const _Field := preload("res://net/leaf_field/leaf_field.gd")


## The drift pattern for a yard: low, smooth noise from the job's seed.
static func noise_for(seed_value: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = Constants.CREW_DRIFT_FREQUENCY
	noise.fractal_octaves = Constants.CREW_DRIFT_OCTAVES
	return noise


## 0..1 at a point (metres, the yard's frame): 1 inside a drift, fading to 0 over
## Constants.CREW_DRIFT_FADE noise units across its edge.
static func weight(noise: FastNoiseLite, cut: float, point: Vector2) -> float:
	var half := Constants.CREW_DRIFT_FADE * 0.5
	return smoothstep(cut - half, cut + half, noise.get_noise_2dv(point))


## The noise level a drift starts at, so that keep of the cells that would have
## leaves still have them (counted the way LeafField.shape_initial rounds them).
## points are the field's cell centres in the yard's frame; amounts the leaf
## multiplier at each before the drifts. Below the lowest level for keep >= 1.
static func cut_for(noise: FastNoiseLite, points: PackedVector2Array, amounts: PackedFloat32Array, keep: float) -> float:
	var values := PackedFloat32Array()
	values.resize(points.size())
	var leafy := 0
	for index: int in points.size():
		values[index] = noise.get_noise_2dv(points[index])
		if _leafy(amounts[index], 1.0):
			leafy += 1
	if keep >= 0.999 or leafy == 0:
		return -2.0
	var want := float(leafy) * clampf(keep, 0.0, 1.0)
	var half := Constants.CREW_DRIFT_FADE * 0.5
	var lo := -1.0 - half
	var hi := 1.0 + half
	for _step: int in 24:
		var cut := (lo + hi) * 0.5
		var count := 0
		for index: int in points.size():
			if _leafy(amounts[index], smoothstep(cut - half, cut + half, values[index])):
				count += 1
		if float(count) > want:
			lo = cut
		else:
			hi = cut
	return (lo + hi) * 0.5


static func _leafy(amount: float, drift: float) -> bool:
	return clampi(int(round(float(_Field.INITIAL_DENSITY) * amount * drift)), 0, 255) > _Field.CLEAN_DENSITY
