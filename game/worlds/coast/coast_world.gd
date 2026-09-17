class_name CoastWorld
extends RefCounted

# Beach Walk and Street Drive as one place: walk off the sand, up the promenade, along the
# connector street through the town, and out onto Alta Vista Avenue where the car is parked.
#
# The beach is the host world - its context, its player, its camera - because the player starts
# on the sand and the beach's terrain is the one that varies. The street is hosted as a district
# (see DistrictLayer): it keeps its own StreetContext and builds in its own coordinates, so its
# road is still at x = 0 as far as its layers are concerned, and every layer a specialist wrote
# for it still works. The town in between is new (segments/town).
#
# Layer order matters twice over: the sky must build first so its palette is published before
# anything reads it, and the district must build after the sky for the same reason.

static func make_context() -> WorldContext:
	return CoastContext.new()


static func make_layers(ctx: WorldContext) -> Array[SceneLayer]:
	var sky := ctx.layer("sky", SkyLayer)
	var ocean := ctx.layer("water", BeachWater)
	var sand := ctx.layer("ground", BeachGround)
	var tracks := ctx.layer("tracks", TracksLayer)
	var architecture := ctx.layer("architecture", BeachArchitecture)
	var vegetation := ctx.layer("vegetation", BeachVegetation)
	var furniture: SceneLayer = ctx.layer("props", BeachProps)
	var crowd: BeachCrowd = ctx.layer("crowd", BeachCrowd)
	var fauna := ctx.layer("fauna", BeachFauna)
	var town := ctx.layer("town", CoastTown)
	var traffic := ctx.layer("vehicles", CoastTraffic)
	var avenue := _avenue(ctx)
	# On foot by default, but with a car parked on the inland street by the promenade: the point
	# of one world is that you can walk off the beach and drive away. &variant=walk keeps the
	# plain beach walker for capture recipes that expect it.
	var player: PlayerLayer
	if ctx.variant == "walk" or ctx.variant == "mpfb":
		player = ctx.layer("player", MpfbPlayerLayer if ctx.variant == "mpfb" else SkinnedPlayerLayer)
	else:
		var d := DriverLayer.new()
		d.walker_class = SkinnedPlayerLayer      # the beach body: you start on the sand, not the kerb
		d.start_pos = Vector3(-96.0, CoastContext.plateau_y(), CoastContext.CROSS_Z[1] - 4.2)
		d.start_yaw = PI * 0.5                      # nose inland, parked on the left kerb
		player = d
		ctx.built_of[d.get_instance_id()] = "player"
	var camera: CameraLayer = ctx.layer("camera", CameraLayer)
	var hud := ctx.layer("hud", HudLayer)
	crowd.furniture = furniture
	camera.player_layer = player
	ctx.hud_hint = "Up: faster   Down: slower   Left / Right: steer   Space: jump   Drag: look around   (the avenue is inland)"
	var out: Array[SceneLayer] = [sky, ocean, sand, tracks, architecture, vegetation, furniture,
								  crowd, town, traffic, avenue, player, fauna, camera, hud]
	return out


# The street world, hosted inland. Its own player, camera and HUD are left out - this world
# already has one of each - so the district is scenery plus its traffic and its pedestrians.
static func _avenue(ctx: WorldContext) -> DistrictLayer:
	var d := DistrictLayer.new()
	d.title = "Avenue"
	d.origin = Vector3(CoastContext.AVENUE_X, CoastContext.plateau_y(), 0.0)
	var sc := StreetContext.new()
	sc.variant = ctx.variant
	# the street's lawn is 400 m wide when it is the whole world, which would slide out over the
	# beach; here it only has to cover its own lots
	sc.lawn_width = 90.0
	d.sub_ctx = sc
	d.make_layers = func(c: WorldContext) -> Array[SceneLayer]:
		var ground := c.layer("ground", StreetGround)
		var arch := c.layer("architecture", StreetArchitecture)
		var veg := c.layer("vegetation", StreetVegetation)
		var props := c.layer("props", StreetProps)
		var crowd := c.layer("crowd", StreetCrowd)
		var traffic := c.layer("vehicles", StreetTraffic)
		var out: Array[SceneLayer] = [ground, arch, veg, props, traffic, crowd]
		return out
	return d


static func validators(layers: Array[SceneLayer]) -> void:
	for l in layers:
		if l is BeachCrowd:
			(l as BeachCrowd).validate_contacts()
