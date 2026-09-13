class_name BeachWorld
extends RefCounted

# Assembles the beach: its context and the ordered layer stack, with the
# only explicit cross-layer wiring (crowd needs furniture spots, camera needs
# the player's heading).

static func make_context() -> WorldContext:
	return BeachContext.new()


static func make_layers(ctx: WorldContext) -> Array[SceneLayer]:
	var sky := ctx.layer("sky", SkyLayer)
	var ocean := ctx.layer("water", BeachWater)
	var sand := ctx.layer("ground", BeachGround)
	var tracks := ctx.layer("tracks", TracksLayer)
	var architecture := ctx.layer("architecture", BeachArchitecture)
	var vegetation := ctx.layer("vegetation", BeachVegetation)
	var furniture: SceneLayer = ctx.layer("props", BeachProps)   # any layer exposing `spots`
	var crowd: BeachCrowd = ctx.layer("crowd", BeachCrowd)
	var fauna := ctx.layer("fauna", BeachFauna)
	var player: PlayerLayer = ctx.layer("player", MpfbPlayerLayer if ctx.variant == "mpfb" else SkinnedPlayerLayer)
	var camera: CameraLayer = ctx.layer("camera", CameraLayer)
	var hud := ctx.layer("hud", HudLayer)
	crowd.furniture = furniture
	camera.player_layer = player
	var out: Array[SceneLayer] = [sky, ocean, sand, tracks, architecture, vegetation, furniture, crowd, player, fauna, camera, hud]
	return out


static func validators(layers: Array[SceneLayer]) -> void:
	for l in layers:
		if l is BeachCrowd:
			(l as BeachCrowd).validate_contacts()
