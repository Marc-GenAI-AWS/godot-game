extends Node3D

# Composition root. Picks a world from the URL fragment (#world=beach) or the
# command line (--world=beach), builds its context and layer stack, and runs
# the tick loop. Worlds live in worlds/<name>/<name>_world.gd and expose
# make_context() / make_layers() / validators().

var WORLDS := {"beach": BeachWorld}
const DEFAULT_WORLD := "beach"

var ctx: WorldContext
var layers: Array[SceneLayer] = []
var world_name := DEFAULT_WORLD


func _ready() -> void:
	var flags := _flags()
	world_name = flags.get("world", DEFAULT_WORLD)
	if not WORLDS.has(world_name):
		push_warning("Unknown world '%s', using %s" % [world_name, DEFAULT_WORLD])
		world_name = DEFAULT_WORLD
	var world = WORLDS[world_name]
	ctx = world.make_context()
	ctx.inspect = flags.has("inspect")
	ctx.lite = flags.has("lite")
	if flags.has("mpfb"):
		ctx.variant = "mpfb"
	if flags.has("crowd"):
		ctx.inspect_offset = Vector3(-14.2, 0.0, -6.0)
	add_child(ctx)
	ctx.make_textures()
	for layer in world.make_layers(ctx):
		layer.name = layer.get_script().get_global_name()
		add_child(layer)
		layer.setup(ctx)
		layers.append(layer)
	if DisplayServer.get_name() == "headless" or flags.has("validate"):
		world.validators(layers)


# Flags from the URL fragment ("#world=beach&inspect" or the legacy
# "#inspect-crowd", "#mpfb") or from command-line user args ("--inspect").
func _flags() -> Dictionary:
	var out := {}
	var raw := ""
	if OS.has_feature("web"):
		raw = str(JavaScriptBridge.eval("window.location.hash", true))
	for a in OS.get_cmdline_user_args():
		raw += "&" + a.trim_prefix("--")
	for part in raw.trim_prefix("#").replace("-", "&").split("&"):
		if part == "":
			continue
		var kv := part.split("=")
		out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func _process(delta: float) -> void:
	ctx.tick(delta)
	for l in layers:
		l.tick(delta)
