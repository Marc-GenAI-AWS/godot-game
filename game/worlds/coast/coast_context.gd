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

# The town's streets. Three run inland (along X) at fixed Z, joining the promenade to the avenue;
# one runs along Z through the middle of town, crossing all three. With the avenue that makes a
# 2 x 4 grid of blocks and, more usefully, eight junctions for cars and people to turn at.
#
# Everything downstream - what the player may walk on, how high the ground is, where cars can go,
# where pedestrians turn - is derived from these two lists rather than written out per street, so
# adding a fourth cross street is one number.
const CROSS_Z := [-40.0, -100.0, -160.0]
const MID_X := -152.0              # the one street running along Z through the town
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


# --- the road network -------------------------------------------------------------------
# Every question the rest of the world asks about the town reduces to one of these.

# Centre Z of the cross street within `half` of z, or NAN.
static func cross_near(z: float, half: float) -> float:
	for cz: float in CROSS_Z:
		if absf(z - cz) <= half:
			return cz
	return NAN


static func on_cross(z: float, half: float) -> bool:
	return not is_nan(cross_near(z, half))


static func on_mid(x: float, half: float) -> bool:
	return absf(x - MID_X) <= half


# Is this point on any road? `half` is how far off a street's centre line still counts - the
# walker may use the footways (CROSS_WALK), a car only the asphalt - and `av` is the same for the
# avenue, which is the street world's and wider than the town's.
static func on_road(x: float, z: float, half: float, av := 12.1) -> bool:
	if on_cross(z, half) and x <= -50.0 and x >= AVENUE_X - av:
		return true
	if on_mid(x, half) and x <= TOWN_EDGE_X:
		return true
	return absf(x - AVENUE_X) <= av


# Push a point back onto the nearest road. The player moves a few centimetres per frame, so the
# nearest road is the one they were just on - which is what makes this behave like a kerb rather
# than a teleport.
static func snap_to_road(p: Vector3, half: float, av := 12.1) -> Vector3:
	if on_road(p.x, p.z, half, av):
		return p
	var best := p
	var best_d := INF
	for cz: float in CROSS_Z:                       # clamp Z onto a cross street
		var q := Vector3(clampf(p.x, AVENUE_X - av, -50.0), p.y, clampf(p.z, cz - half, cz + half))
		var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
		if d < best_d:
			best_d = d
			best = q
	for cx: float in [MID_X, AVENUE_X]:             # or X onto a street running along Z
		var lim: float = half if cx == MID_X else av
		var q := Vector3(clampf(p.x, cx - lim, cx + lim), p.y, p.z)
		var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
		if d < best_d:
			best_d = d
			best = q
	return best


# The junctions, in world coordinates: where an agent may turn.
static func junctions() -> Array:
	var out: Array = []
	for cz: float in CROSS_Z:
		out.append(Vector3(MID_X, 0.0, cz))
		out.append(Vector3(AVENUE_X, 0.0, cz))
	return out


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
	if on_cross(z, CROSS_WALK) and x <= STEP_X0 and x >= STEP_X1:
		var t := clampf((STEP_X0 - x) / (STEP_X0 - STEP_X1), 0.0, 1.0)
		return lerpf(ground_height(STEP_X0, z), deck, t)                # the steps
	if x < BOARDWALK_X + 1.2 and x > BOARDWALK_X - 9.0:
		return deck                                                     # the deck itself
	if x <= BOARDWALK_X - 9.0 and on_road(x, z, CROSS_WALK):
		# The streets run level with the deck. Behind the deck the sand has not finished rising,
		# so they sit up to 26 cm proud of it for 9 m - which is what a road behind a seawall
		# looks like, and the kerbs hide the lip.
		var base: float = maxf(ground_height(x, z), plateau_y())
		var paved: bool = on_cross(z, CROSS_HALF) or on_mid(x, CROSS_HALF)
		return base + (0.07 if paved else 0.15)
	return ground_height(x, z)


func constrain(p: Vector3) -> Vector3:
	# Three corridors, joined at the connector. Which one you are in is decided by X, and each
	# one holds you on its own axis: the beach and the avenue run along Z so they clamp X, the
	# connector runs along X so it clamps Z. Clamping the wrong axis is what made an early
	# version yank the player 28 m sideways when they stepped off the kerb in town.
	if p.x > TOWN_EDGE_X:
		# the beach, as before - except where a street meets the promenade, which is open
		var lo: float = (AVENUE_X - 12.1) if on_cross(p.z, CROSS_WALK) else (BOARDWALK_X - 6.2)
		p.x = clampf(p.x, lo, 4.0)
		return p
	# inland it is the street network that decides, so blocks read as blocks
	return snap_to_road(p, CROSS_WALK)


# The car may use the avenue and the connector, and turn between them.
func constrain_vehicle(p: Vector3) -> Vector3:
	# The car is held to the asphalt, which on this grid means: on a street, or in a junction
	# where two of them cross. Same rule as the walker, one lane narrower.
	if p.x > TOWN_EDGE_X:
		return p                                          # off the town grid (the promenade end)
	# a car gets the asphalt only, and on the avenue that is the street world's own road width
	return snap_to_road(p, CROSS_HALF - 1.0, StreetContext.ROAD_HALF - 1.0)


func wetness_at(p: Vector3) -> float:
	if p.x < BLUFF_X:
		return 0.0        # no wet sand in town
	return super.wetness_at(p)
