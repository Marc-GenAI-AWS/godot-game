extends Node3D

# Composition root. Picks a world from the URL fragment (#world=beach) or the
# command line (--world=beach), builds its context and layer stack, and runs
# the tick loop. Worlds live in worlds/<name>/<name>_world.gd and expose
# make_context() / make_layers() / validators().

var WORLDS := {"beach": BeachWorld, "street": StreetWorld}
const DEFAULT_WORLD := "beach"

var ctx: WorldContext
var layers: Array[SceneLayer] = []
var world_name := DEFAULT_WORLD

# Verifier hooks (native capture, no browser): --capture=<dir> saves the
# viewport at --shots=4,9 seconds after "world ready" and writes stats.json
# (fps, draw calls, published palette), then quits. --script=6:ArrowUp~2,
# 8:Drag_-260_0 injects the same key/drag script the browser harness uses.
var capture_dir := ""
var shots: Array[float] = []
var script_events: Array = []      # [time, kind, key/dx, hold/dy]
var _held: Array = []              # [release_time, keycode]
var _drag_delta := Vector2.ZERO    # where the current injected drag ended
var _fps_samples: Array[float] = []
var _draw_calls := 0
var _ready_time := 0.0
var _world                      # the world class, so a runtime swap can reassemble it
var _segment_of := {}           # layer node -> segment name, for swapping one layer in place


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
	if flags.has("variant"):
		ctx.variant = str(flags["variant"])
	if flags.has("crowd"):
		ctx.inspect_offset = Vector3(-14.2, 0.0, -6.0)
	if flags.has("swap"):
		for pair in str(flags["swap"]).split(";"):
			var kv2 := pair.split(":", true, 1)   # segment:res://path (the path has its own colon)
			if kv2.size() == 2:
				ctx.overrides[kv2[0]] = kv2[1]
	if flags.has("capture"):
		capture_dir = str(flags["capture"])
		# keep the capture window out of the way on a shared desktop (rendering
		# continues off-screen; --minimized=0 to watch it)
		# (a minimised window stops rendering under GNOME, so instead an unmanaged
		# borderless window is parked beyond the screen edge; --offscreen=0 to watch)
		if str(flags.get("offscreen", "1")) != "0":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
			var screen := DisplayServer.screen_get_size()
			DisplayServer.window_set_position(Vector2i(screen.x + 50, screen.y + 50))
		for t in str(flags.get("shots", "4,9")).split(","):
			shots.append(float(t))
		if flags.has("script"):
			_parse_script(str(flags["script"]))
	_world = world
	add_child(ctx)
	ctx.make_textures()
	for layer in world.make_layers(ctx):
		var gname: String = layer.get_script().get_global_name()
		layer.name = gname if gname != "" else str(layer.get_script().resource_path).get_file().get_basename()
		layer.set_meta("segment", ctx.built_of.get(layer.get_instance_id(), ""))
		add_child(layer)
		layer.setup(ctx)
		layers.append(layer)
	if capture_dir == "" and not flags.has("nomenu"):
		var menu := SceneMenuLayer.new()
		menu.name = "SceneMenuLayer"
		add_child(menu)
		menu.setup(ctx)
		layers.append(menu)
	if capture_dir != "":
		for l in layers:
			if l is HudLayer:          # the judge should not read the HUD
				l.visible = false
				for c in l.find_children("*", "CanvasLayer", true, false):
					(c as CanvasLayer).visible = false
	if DisplayServer.get_name() == "headless" or flags.has("validate"):
		world.validators(layers)
	if flags.has("menutest"):
		_menu_selftest.call_deferred()
	if flags.has("menushot"):
		_menu_shot.call_deferred(str(flags["menushot"]))
	print("world ready: ", world_name)   # capture harness syncs its clock to this line
	_ready_time = ctx.time


# Flags from the URL fragment ("#world=beach&inspect" or the legacy
# "#inspect-crowd", "#mpfb") or from command-line user args ("--inspect").
func _flags() -> Dictionary:
	var out := {}
	var raw := ""
	if OS.has_feature("web"):
		raw = str(JavaScriptBridge.eval("window.location.hash", true))
	for a in OS.get_cmdline_user_args():
		raw += "&" + a.trim_prefix("--")
	raw = raw.replace("inspect-crowd", "inspect&crowd")   # legacy fragment form
	for part in raw.trim_prefix("#").split("&"):
		if part == "":
			continue
		var kv := part.split("=")
		out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func _process(delta: float) -> void:
	ctx.tick(delta)
	for l in layers:
		l.tick(delta)
	if capture_dir != "":
		_capture_tick()


# --- verifier hooks -------------------------------------------------------

const KEYS := {"ArrowUp": KEY_UP, "ArrowDown": KEY_DOWN, "ArrowLeft": KEY_LEFT, "ArrowRight": KEY_RIGHT, "Space": KEY_SPACE, "KeyE": KEY_E, "Enter": KEY_ENTER}


func _parse_script(spec: String) -> void:
	for item in spec.split(","):
		var kv := item.split(":")
		if kv.size() != 2:
			continue
		var t := float(kv[0])
		var name := kv[1]
		if name.begins_with("Drag_") or name.begins_with("Look_"):
			# Drag_ releases at the press point, which the walker reads as a tap
			# (toggles walking); older recipes rely on that. Look_ releases where
			# the drag ended, so it only orbits the camera.
			var hold := 0.3
			if "~" in name:
				var nh := name.split("~")
				name = nh[0]
				hold = float(nh[1])
			var p := name.split("_")
			script_events.append([t, "drag", float(p[1]), float(p[2]), hold, p[0] == "Look"])
		else:
			var hold := 0.12
			if "~" in name:
				var nh := name.split("~")
				name = nh[0]
				hold = float(nh[1])
			if KEYS.has(name):
				script_events.append([t, "key", KEYS[name], hold])
	script_events.sort_custom(func(a, b): return a[0] < b[0])


func _key_event(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _drag(dx: float, dy: float) -> void:
	# press + move; the release is scheduled by the caller so the orbit holds
	var centre := get_viewport().get_visible_rect().size * 0.5
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = centre
	Input.parse_input_event(down)
	var move := InputEventMouseMotion.new()
	move.position = centre + Vector2(dx, dy)
	move.relative = Vector2(dx, dy)
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(move)


func _drag_release() -> void:
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	# Look_ releases where the drag ended (not a tap); Drag_ at the press point
	up.position = get_viewport().get_visible_rect().size * 0.5 + _drag_delta
	Input.parse_input_event(up)


func _capture_tick() -> void:
	var t := ctx.time - _ready_time
	while script_events.size() > 0 and script_events[0][0] <= t:
		var ev: Array = script_events.pop_front()
		if ev[1] == "drag":
			_drag(ev[2], ev[3])
			_drag_delta = Vector2(ev[2], ev[3]) if ev[5] else Vector2.ZERO
			_held.append([t + ev[4], -1])          # -1 = mouse release
		else:
			_key_event(ev[2], true)
			_held.append([t + ev[3], ev[2]])
	var still: Array = []
	for h in _held:
		if h[0] <= t:
			if h[1] == -1:
				_drag_release()
			else:
				_key_event(h[1], false)
		else:
			still.append(h)
	_held = still
	if t > 1.0:
		_fps_samples.append(Engine.get_frames_per_second())
		_draw_calls = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	if shots.size() > 0 and t >= shots[0]:
		var at: float = shots.pop_front()
		_save_shot(at)
	elif shots.size() == 0:
		_write_stats()
		get_tree().quit()


func _save_shot(at: float) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var fn := "%s/%s_%ds.png" % [capture_dir, world_name, int(round(at))]
	DirAccess.make_dir_recursive_absolute(capture_dir)
	img.save_png(fn)
	print("wrote ", fn)


func _write_stats() -> void:
	var fps := 0.0
	for f in _fps_samples:
		fps += f
	fps = fps / maxf(_fps_samples.size(), 1.0)
	# probe of the swapped-in layers: what they placed (chunk 1 for chunked
	# layers) and how many obstacles the scene has, for the verifier's checks
	var probe := {}
	for seg in ctx.overrides:
		for l in layers:
			if str(l.get_script().resource_path) == str(ctx.overrides[seg]):
				var root: Node = l
				if l is ChunkedLayer and (l as ChunkedLayer).chunks.size() > 1:
					root = (l as ChunkedLayer).chunks[1]
				var nodes := []
				for c in root.get_children():
					if c is Node3D:
						var p3: Vector3 = (c as Node3D).position
						nodes.append([c.name, c.get_class(), snappedf(p3.x, 0.01), snappedf(p3.y, 0.01), snappedf(p3.z, 0.01), c.get_child_count()])
				probe[seg] = {"nodes": nodes, "spots": (l.get("spots") as Array).size() if l.get("spots") != null else -1}
	var stats := {
		"world": world_name, "fps_avg": fps, "draw_calls": _draw_calls,
		"overrides": ctx.overrides, "obstacles": ctx.obstacle_count(), "probe": probe,
		"palette": {"sky_zenith": [ctx.sky_zenith.r, ctx.sky_zenith.g, ctx.sky_zenith.b],
			"sky_horizon": [ctx.sky_horizon.r, ctx.sky_horizon.g, ctx.sky_horizon.b],
			"sun_dir": [ctx.sun_dir.x, ctx.sun_dir.y, ctx.sun_dir.z],
			"sun_color": [ctx.sun_color.r, ctx.sun_color.g, ctx.sun_color.b],
			"fog_color": [ctx.fog_color.r, ctx.fog_color.g, ctx.fog_color.b]},
	}
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var f := FileAccess.open(capture_dir + "/stats.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(stats, "  "))
	f.close()
	print("stats ", JSON.stringify(stats))


# --- runtime scene editing (the right-click menu) ---------------------------
# One layer is replaced in place rather than reassembling the world: rebuilding the
# context reallocates every shared texture and mesh, which crashes the renderer when
# two contexts briefly overlap. Only the handful of references between layers need
# fixing up, and they are listed in _rewire().

var _rebuilding := false


func swap_segment(segment: String, path: String) -> void:
	if _rebuilding:
		return
	if path == "":
		ctx.overrides.erase(segment)
	else:
		ctx.overrides[segment] = path
	_replace_layer(segment)
	# the crowd sits on the furniture's spots, so it has to be rebuilt behind new furniture
	if segment == "props":
		_replace_layer("crowd")
	_rewire()


func dress_player(sex: String, outfit: String) -> void:
	ctx.player_sex = sex
	ctx.player_outfit = outfit
	_replace_layer("player")
	_rewire()


func set_player_hair(style: String) -> void:
	ctx.player_hair = style
	_replace_layer("player")
	_rewire()


func reset_scene() -> void:
	var touched := ctx.overrides.keys()
	ctx.overrides.clear()
	ctx.player_sex = ""
	ctx.player_outfit = ""
	ctx.player_hair = ""
	for segment in touched:
		_replace_layer(segment)
	_replace_layer("player")
	if touched.has("props"):
		_replace_layer("crowd")
	_rewire()


# Build the segment afresh from the current overrides and put it where the old one was.
func _replace_layer(segment: String) -> void:
	if not ctx.defaults.has(segment):
		return
	var old: SceneLayer = null
	var at := -1
	for i in layers.size():
		if layers[i].get_meta("segment", "") == segment:
			old = layers[i]
			at = i
			break
	var fresh := ctx.layer(segment, ctx.defaults[segment])
	fresh.set_meta("segment", segment)
	var gname: String = fresh.get_script().get_global_name()
	fresh.name = gname if gname != "" else str(fresh.get_script().resource_path).get_file().get_basename()
	if old != null:
		remove_child(old)
		old.queue_free()
		layers[at] = fresh
	else:
		layers.append(fresh)
	add_child(fresh)
	if at >= 0:
		move_child(fresh, at)
	fresh.setup(ctx)


# The only references layers hold to each other.
func _rewire() -> void:
	var by_segment := {}
	for l in layers:
		by_segment[l.get_meta("segment", "")] = l
	var crowd = by_segment.get("crowd")
	var furniture = by_segment.get("props")
	if crowd != null and furniture != null and "furniture" in crowd:
		crowd.furniture = furniture
	var camera = by_segment.get("camera")
	var player = by_segment.get("player")
	if camera != null and player != null and "player_layer" in camera:
		camera.player_layer = player


# Exercises the right-click menu's actions without a GUI: --menutest boots the world,
# swaps a generated layer in, dresses the player, resets, and reports. The menu has no
# other headless coverage, and a broken swap is invisible until someone clicks it.
func _menu_selftest() -> void:
	await get_tree().create_timer(1.0).timeout
	var menu: SceneMenuLayer = null
	for l in layers:
		if l is SceneMenuLayer:
			menu = l
	print("MENUTEST layers=%d menu=%s" % [layers.size(), menu != null])
	if menu == null:
		get_tree().quit(1)
		return
	for seg in ["sky", "ground", "vegetation", "props"]:
		var found: Array = menu._generated(seg)
		print("MENUTEST %s options=%d" % [seg, found.size()])
		if found.size() > 0:
			swap_segment(seg, found[0])
			await get_tree().create_timer(1.0).timeout
			print("MENUTEST after %s swap layers=%d override=%s" % [seg, layers.size(), str(ctx.overrides.get(seg, "")).get_file()])
			if seg == "props":
				for l in layers:
					if l.get_meta("segment", "") == "crowd" and l.has_method("validate_contacts"):
						l.validate_contacts()
	var before: Vector3 = ctx.player_pos
	dress_player("M", "trunks_blue")
	await get_tree().create_timer(1.0).timeout
	print("MENUTEST dressed sex=%s outfit=%s kept_position=%s" % [ctx.player_sex, ctx.player_outfit, str(ctx.player_pos != Vector3.ZERO and before != Vector3.ZERO)])
	set_player_hair("buzz")
	await get_tree().create_timer(1.0).timeout
	print("MENUTEST hair=%s" % ctx.player_hair)
	reset_scene()
	await get_tree().create_timer(1.0).timeout
	print("MENUTEST reset overrides=%d outfit=%s" % [ctx.overrides.size(), "'" + ctx.player_outfit + "'"])
	print("MENUTEST DONE")
	get_tree().quit(0)


# A frame for the project page, with the menu actually open. On the desktop a PopupMenu is
# its own OS window, so a screen grab of the game window misses it; embedding sub-windows -
# which is what the web build does anyway - puts the menu in the framebuffer we can save.
func _menu_shot(path: String) -> void:
	await get_tree().create_timer(3.0).timeout
	get_viewport().gui_embed_subwindows = true
	var menu_layer: SceneMenuLayer = null
	for l in layers:
		if l is SceneMenuLayer:
			menu_layer = l
	if menu_layer == null:
		print("MENUSHOT no menu layer")
		get_tree().quit(1)
		return
	menu_layer._fill()
	var root: PopupMenu = menu_layer.menu
	root.reset_size()
	root.position = Vector2i(90, 110)
	root.popup()
	await get_tree().process_frame
	var sub := root.get_node_or_null("wardrobe") as PopupMenu
	if sub != null:
		sub.reset_size()
		sub.position = Vector2i(root.position.x + root.size.x + 2, max(8, 710 - sub.size.y))
		sub.popup()
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("MENUSHOT %s %dx%d" % [path, img.get_width(), img.get_height()])
	get_tree().quit(0)
