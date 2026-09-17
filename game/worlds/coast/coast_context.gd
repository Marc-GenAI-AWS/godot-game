class_name CoastContext
extends BeachContext

# The beach and the street in one continuous space.
#
# It extends BeachContext because the beach layers cast to it (`ctx as BeachContext`) and read
# SHORE_W, tide_reach and water_edge_x(). The street lives in its own district with its own
# StreetContext (see DistrictLayer), so nothing here has to satisfy both.
#
# Looking inland from the sea, at these world X:
#
#     +4  ankle-deep water        the player's seaward limit, unchanged
#      0  waterline
#    -52  steps up to the promenade, on the connector only
#    -56  promenade and boardwalk deck (y = 2.42)
#    -65  hedges, then the seafront hotel row to about -101
#    -73  the bluff: the 3 % beach rise eases off here
#    -88  the town terrace, flat and level with the deck
#    -88 .. -228  town blocks, crossed by the connector street at z = CROSS_Z
#   -240  Alta Vista Avenue - the street world, hosted as a district
#
# The beach keeps rising at LAND_SLOPE for ever in BeachContext, which would put the avenue
# 7.4 m above the hotels. The plateau is what makes a flat street district possible without a
# cliff: the land rises off the sand, then levels out, the way a seafront town actually sits.

# -72.7 is not arbitrary: it is the X at which the beach's own 3 % rise reaches the height of
# the promenade deck (2.42 m), so the town terrace comes out flush with the boardwalk and you
# walk off the deck onto the street instead of stepping up or down.
const BLUFF_X := -72.7             # where the beach rise starts easing
const PLATEAU_X := -88.0           # and where it is flat
const AVENUE_X := -240.0           # the street district's centre line
const TOWN_EDGE_X := -66.0         # seaward edge of the town's paving, just behind the deck

# The connector street, running inland (along X) across the town, joining the promenade to the
# avenue. It sits at one Z inside the 200 m loop, so the player always has a way across.
const CROSS_Z := -100.0
const CROSS_HALF := 7.0            # asphalt half width
const CROSS_WALK := 10.5           # sidewalk half width - the corridor the player may use

# The boardwalk deck stands half a metre above the sand, and the beach world has always had that
# as a bare step you teleport up. Inland is now somewhere you have to walk, so the connector gets
# steps: a ramp in walk_height here, matching treads built by CoastTown.
const STEP_X0 := -51.0             # bottom of the steps, on the sand
const STEP_X1 := -55.0             # top, flush with the deck's seaward edge

# Flat height of the town and the avenue. Read off the beach's own slope at the bluff so the
# two meet without a step.
static func plateau_y() -> float:
	return BeachContext.SAND_SLOPE * BeachContext.SHORE_W - BeachContext.LAND_SLOPE * (BLUFF_X + BeachContext.SHORE_W)


func _init() -> void:
	super._init()
	world_title = "Coast"


func ground_height(x: float, z: float) -> float:
	if x >= BLUFF_X:
		return super.ground_height(x, z)
	if x <= PLATEAU_X:
		return plateau_y()
	# smoothstep across the bluff so there is no crease where the sand meets the town
	var t := smoothstep(0.0, 1.0, (BLUFF_X - x) / (BLUFF_X - PLATEAU_X))
	return lerpf(super.ground_height(x, z), plateau_y(), t)


func walk_height(x: float, z: float) -> float:
	# Ordered seaward to inland, because the rules overlap at every join:
	#   sand -> steps -> boardwalk deck -> connector road -> town terrace
	var deck: float = super.ground_height(BOARDWALK_X, 0.0) + 0.5      # 2.42, the deck surface
	var on_cross := absf(z - CROSS_Z) <= CROSS_WALK
	if on_cross and x <= STEP_X0 and x >= STEP_X1:
		var t := clampf((STEP_X0 - x) / (STEP_X0 - STEP_X1), 0.0, 1.0)
		return lerpf(ground_height(STEP_X0, z), deck, t)                # the steps
	if x < BOARDWALK_X + 1.2 and x > BOARDWALK_X - 9.0:
		return deck                                                     # the deck itself
	if x <= BOARDWALK_X - 9.0 and on_cross:
		# The connector runs level with the deck. Behind the deck the sand has not finished
		# rising, so the road sits up to 26 cm proud of it for 9 m - which is what a road behind
		# a seawall looks like, and the kerbs hide the lip.
		var base: float = maxf(ground_height(x, z), plateau_y())
		return base + (0.07 if absf(z - CROSS_Z) <= CROSS_HALF else 0.15)
	return ground_height(x, z)


func constrain(p: Vector3) -> Vector3:
	# Three corridors, joined at the connector. Which one you are in is decided by X, and each
	# one holds you on its own axis: the beach and the avenue run along Z so they clamp X, the
	# connector runs along X so it clamps Z. Clamping the wrong axis is what made an early
	# version yank the player 28 m sideways when they stepped off the kerb in town.
	var on_cross := absf(p.z - CROSS_Z) <= CROSS_WALK
	if p.x > TOWN_EDGE_X:
		# the beach, as before - except on the connector, where the way inland is open
		p.x = clampf(p.x, (AVENUE_X - 12.1) if on_cross else (BOARDWALK_X - 6.2), 4.0)
		return p
	if p.x > AVENUE_X + 12.1:
		p.z = clampf(p.z, CROSS_Z - CROSS_WALK, CROSS_Z + CROSS_WALK)   # the town: the street
		return p
	# the avenue, with the junction left open so you can walk back to the sea
	p.x = clampf(p.x, AVENUE_X - 12.1, 4.0 if on_cross else AVENUE_X + 12.1)
	return p


# The car may use the avenue and the connector, and turn between them.
func constrain_vehicle(p: Vector3) -> Vector3:
	var on_cross := absf(p.z - CROSS_Z) <= CROSS_HALF - 1.0
	var on_avenue := absf(p.x - AVENUE_X) <= StreetContext.ROAD_HALF - 1.0
	if on_cross and on_avenue:
		return p                                          # the junction itself
	if on_cross:
		p.x = clampf(p.x, AVENUE_X - 5.0, -6.0)           # the connector, up to the promenade
		return p
	p.x = clampf(p.x, AVENUE_X - 5.0, AVENUE_X + 5.0)
	return p


func wetness_at(p: Vector3) -> float:
	if p.x < BLUFF_X:
		return 0.0        # no wet sand in town
	return super.wetness_at(p)
