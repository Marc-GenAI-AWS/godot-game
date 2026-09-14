class_name BeachContext
extends WorldContext

# Beach-specific world state: a sand slope into the sea (+X), a promenade
# deck on the land side (-X), sea level and the tide's reach up the sand.

const SAND_SLOPE := 0.06      # sand drops this much per metre into the sea (+X)
const LAND_SLOPE := 0.03      # and rises this much per metre up the beach (-X) beyond the shore strip
const SHORE_W := 8.0          # metres of sea slope kept landward of x = 0
const BOARDWALK_X := -56.0

var tide_reach := 0.7         # world X the last wave reached (wet line), 2.5 m up the beach from the water's edge


func _init() -> void:
	world_title = "Beach Walk"


func ground_height(x: float, z: float) -> float:
	# The sea slope continues SHORE_W metres up the beach so the tide's whole
	# excursion (+-3.2 m) stays on the steeper sand, then the beach eases to
	# LAND_SLOPE. Undulation fades out near the shore so the sea meets a clean
	# slope (a flat water plane would poke through low spots as hard-edged
	# pools at high tide).
	var h := -SAND_SLOPE * x if x > -SHORE_W else SAND_SLOPE * SHORE_W - LAND_SLOPE * (x + SHORE_W)
	var inland := clampf((-SHORE_W - x) / 9.0, 0.0, 1.0)
	h += inland * (0.06 * sin(z * 0.21 + x * 0.1) + 0.04 * sin(z * 0.7 - x * 0.3))
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
	tide_reach = water_edge_x() - 2.5


# World X where the sea surface meets the sand right now (no swell).
func water_edge_x() -> float:
	return -sea_level() / SAND_SLOPE
