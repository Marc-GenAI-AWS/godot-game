class_name StreetWorld
extends RefCounted

static func make_context() -> WorldContext:
	return StreetContext.new()


static func make_layers(ctx: WorldContext) -> Array[SceneLayer]:
	var sky := ctx.layer("sky", SkyLayer)
	var ground := ctx.layer("ground", StreetGround)
	var architecture := ctx.layer("architecture", StreetArchitecture)
	var vegetation := ctx.layer("vegetation", StreetVegetation)
	var props := ctx.layer("props", StreetProps)
	var crowd := ctx.layer("crowd", StreetCrowd)
	var traffic := ctx.layer("vehicles", StreetTraffic)
	# default: the full loop (on foot, get in, drive, get out); &variant=walk
	# or &variant=drive isolate one mode for the player specialist
	# Through ctx.layer() so the menu can rebuild it: dressing the player silently did nothing in
	# this world, because _replace_layer() can only rebuild a segment whose default it was told.
	var player: PlayerLayer
	match ctx.variant:
		"walk":
			player = ctx.layer("player", StreetWalkerLayer)
		"drive":
			player = ctx.layer("player", VehiclePlayerLayer)
			(player as VehiclePlayerLayer).with_driver = true
			ctx.hud_hint = "Up: accelerate   Down: brake / reverse   Left / Right: steer   Drag: look around"
		_:
			player = ctx.layer("player", DriverLayer)
	var camera: CameraLayer = ctx.layer("camera", CameraLayer)
	var hud := ctx.layer("hud", HudLayer)
	camera.player_layer = player
	var out: Array[SceneLayer] = [sky, ground, architecture, vegetation, props, traffic, crowd, player, camera, hud]
	return out


static func validators(_layers: Array[SceneLayer]) -> void:
	pass
