class_name BeachContext
extends WorldContext

# Beach-specific world state: a sand slope into the sea (+X), a promenade
# deck on the land side (-X), sea level and the tide's reach up the sand.

const SAND_SLOPE := 0.06      # sand drops this much per metre into the sea (+X)
const LAND_SLOPE := 0.03      # and rises this much per metre up the beach (-X)
const BOARDWALK_X := -56.0

var tide_reach := 3.0         # world X the last wave reached (wet line)


func ground_height(x: float, z: float) -> float:
	var h := -SAND_SLOPE * x if x > 0.0 else -LAND_SLOPE * x
	h += 0.06 * sin(z * 0.21 + x * 0.1) + 0.04 * sin(z * 0.7 - x * 0.3)
	return h


func walk_height(x: float, z: float) -> float:
	if x < BOARDWALK_X + 1.2:
		return ground_height(BOARDWALK_X, 0.0) + 0.5   # boardwalk deck
	return ground_height(x, z)


func constrain(p: Vector3) -> Vector3:
	# from the deck edge (hedges start beyond) to ankle-deep water
	p.x = clampf(p.x, BOARDWALK_X - 6.2, 4.0)
	return p


func wetness_at(p: Vector3) -> float:
	if p.x > tide_reach + 0.5:
		return -1.0   # under water: no print
	return clampf((p.x - (tide_reach - 9.0)) / 8.0, 0.0, 1.0)


func sea_level() -> float:
	return 0.14 * sin(time * 0.55) + 0.05 * sin(time * 1.7)


func tick(delta: float) -> void:
	super.tick(delta)
	tide_reach = 3.2 + 1.6 * sin(time * 0.55) + 0.5 * sin(time * 1.7)
