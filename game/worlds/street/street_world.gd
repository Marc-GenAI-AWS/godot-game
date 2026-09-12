class_name StreetWorld
extends RefCounted

static func make_context() -> WorldContext:
	return StreetContext.new()


static func make_layers(ctx: WorldContext) -> Array[SceneLayer]:
	var sky := SkyLayer.new()
	var ground := StreetGround.new()
	var architecture := StreetArchitecture.new()
	var vegetation := StreetVegetation.new()
	var props := StreetProps.new()
	var crowd := StreetCrowd.new()
	var traffic := StreetTraffic.new()
	var player: PlayerLayer = SkinnedPlayerLayer.new() if ctx.variant == "walk" else VehiclePlayerLayer.new()
	var camera := CameraLayer.new()
	var hud := HudLayer.new()
	camera.player_layer = player
	if ctx.variant != "walk":
		ctx.hud_hint = "Up: accelerate   Down: brake / reverse   Left / Right: steer   Drag: look around"
	var out: Array[SceneLayer] = [sky, ground, architecture, vegetation, props, traffic, crowd, player, camera, hud]
	return out


static func validators(_layers: Array[SceneLayer]) -> void:
	pass
