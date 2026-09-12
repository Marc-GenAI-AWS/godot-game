class_name BeachWorld
extends RefCounted

# Assembles the beach: its context and the ordered layer stack, with the
# only explicit cross-layer wiring (crowd needs furniture spots, camera needs
# the player's heading).

static func make_context() -> WorldContext:
	return BeachContext.new()


static func make_layers(ctx: WorldContext) -> Array[SceneLayer]:
	var sky := SkyLayer.new()
	var ocean := OceanLayer.new()
	var sand := SandLayer.new()
	var tracks := TracksLayer.new()
	var architecture := ArchitectureLayer.new()
	var vegetation := VegetationLayer.new()
	var furniture := FurnitureLayer.new()
	var crowd := CrowdLayer.new()
	var fauna := FaunaLayer.new()
	var player: PlayerLayer = MpfbPlayerLayer.new() if ctx.variant == "mpfb" else SkinnedPlayerLayer.new()
	var camera := CameraLayer.new()
	var hud := HudLayer.new()
	crowd.furniture = furniture
	camera.player_layer = player
	var out: Array[SceneLayer] = [sky, ocean, sand, tracks, architecture, vegetation, furniture, crowd, player, fauna, camera, hud]
	return out


static func validators(layers: Array[SceneLayer]) -> void:
	for l in layers:
		if l is CrowdLayer:
			(l as CrowdLayer).validate_contacts()
