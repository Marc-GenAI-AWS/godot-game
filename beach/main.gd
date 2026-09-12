extends Node3D

# Beach Walk composition root. The world is a stack of independent layers
# (see layers/). Each layer builds itself from the shared WorldContext and
# updates itself every frame. To specialise part of the scene, edit or
# replace that one layer.

var ctx := WorldContext.new()
var layers: Array[BeachLayer] = []


func _ready() -> void:
	add_child(ctx)
	ctx.make_textures()
	if OS.has_feature("web"):
		var hash_v = JavaScriptBridge.eval("window.location.hash", true)
		ctx.inspect = str(hash_v).begins_with("#inspect")
		if str(hash_v).find("crowd") >= 0:
			ctx.inspect_offset = Vector3(-19.0, 0.0, -8.0)
		ctx.lite = str(hash_v).find("lite") >= 0
		if str(hash_v).find("mpfb") >= 0:
			ctx.variant = "mpfb"
	elif OS.get_cmdline_user_args().has("--inspect"):
		ctx.inspect = true

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

	# Cross-layer wiring is explicit and lives only here.
	crowd.furniture = furniture
	camera.player_layer = player

	# Order matters only where a layer reads another's build output.
	for l in [sky, ocean, sand, tracks, architecture, vegetation, furniture, crowd, player, fauna, camera, hud]:
		var layer: BeachLayer = l
		layer.name = layer.get_script().get_global_name()
		add_child(layer)
		layer.setup(ctx)
		layers.append(layer)


func _process(delta: float) -> void:
	ctx.tick(delta)
	for l in layers:
		l.tick(delta)
