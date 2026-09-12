class_name StreetContext
extends WorldContext

# A straight two-lane street along Z with parking strips, kerbs, sidewalks,
# grass verges and house lots either side. Flat ground; sidewalks raised.

const ROAD_HALF := 6.0        # asphalt edge (kerb) at |x| = 6
const LANE_X := 1.9           # driving lane centres at |x| = 1.9
const PARK_X := 4.9           # parking strip centres
const KERB_H := 0.15
const WALK_OUT := 9.0         # sidewalk from 6 to 9
const VERGE_OUT := 12.5       # grass verge 9 to 12.5
const LOT_X := 13.5           # walls / houses start


func _init() -> void:
	world_title = "Street Drive"
	sky_zenith = Color(0.12, 0.36, 0.84)
	sky_horizon = Color(0.66, 0.8, 0.94)


func ground_height(_x: float, _z: float) -> float:
	return 0.0


func walk_height(x: float, z: float) -> float:
	return KERB_H if absf(x) > ROAD_HALF else 0.0


func constrain(p: Vector3) -> Vector3:
	p.x = clampf(p.x, -VERGE_OUT + 0.4, VERGE_OUT - 0.4)
	return p


func constrain_vehicle(p: Vector3) -> Vector3:
	p.x = clampf(p.x, -ROAD_HALF + 1.0, ROAD_HALF - 1.0)
	return p
