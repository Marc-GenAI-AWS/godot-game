extends Node3D

# Composition root. Picks a world from the URL fragment (#world=beach) or the
# command line (--world=beach), builds its context and layer stack, and runs
# the tick loop. Worlds live in worlds/<name>/<name>_world.gd and expose
# make_context() / make_layers() / validators().

var WORLDS := {"beach": BeachWorld, "street": StreetWorld, "coast": CoastWorld}
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
var _perf := false
var _perf_t := 0.0
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
	if flags.has("eye"):
		# --eye=<distance>,<height> pulls the chase camera back for an overview. The coast world
		# is 250 m across, and no ground-level shot shows how its districts sit together.
		var e := str(flags["eye"]).split(",")
		if e.size() >= 2:
			ctx.camera_profile["dist"] = float(e[0])
			ctx.camera_profile["height"] = float(e[1])
			# a third number aims the camera: 0 looks straight down, which is the only way to see
			# what is actually under the player rather than what is in front of them
			ctx.camera_profile["look"] = float(e[2]) if e.size() >= 3 else float(e[1]) * 0.35
	if flags.has("at"):
		# --at=x,z (and optionally a heading in radians) drops the player anywhere in the world.
		# A world you can walk across in two minutes did not need this; the coast world is 250 m
		# wide, so a screenshot of the town is otherwise a two-minute scripted walk.
		var parts := str(flags["at"]).split(",")
		if parts.size() >= 2:
			ctx.player_pos = Vector3(float(parts[0]), 0.0, float(parts[1]))
			ctx.player_pos.y = ctx.walk_height(ctx.player_pos.x, ctx.player_pos.z)
		if parts.size() >= 3:
			ctx.player_heading = float(parts[2])
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
	if flags.has("wear"):
		# --wear=<sex>,<outfit>[,<hair>] dresses the player at startup, the same way the menu does.
		# Useful for a screenshot, and the only way to see that a rebuild reached the body.
		_wear.call_deferred(str(flags["wear"]))
	if flags.has("menutest"):
		_menu_selftest.call_deferred()
	if flags.has("menushot"):
		_menu_shot.call_deferred(str(flags["menushot"]))
	if flags.has("perf"):
		_perf = true
	if flags.has("census"):
		_census.call_deferred()
	if flags.has("coasttest"):
		_coast_selftest.call_deferred()
	if flags.has("traffictest"):
		_traffic_selftest.call_deferred()
	if flags.has("crowdtest"):
		_crowd_selftest.call_deferred()
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
	if _perf:
		_perf_t += delta
		if _perf_t > 2.0:
			_perf_t = 0.0
			# fps is useless in a browser - it is pinned to vsync - so report the time actually
			# spent. If process time is near the 16.7 ms budget the cost is ours; if it is small
			# and the frame rate is still low, the cost is the GPU's.
			print("PERF cpu %.2f ms  physics %.2f ms  draw calls %d  objects %d  fps %d" % [
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				Engine.get_frames_per_second()])
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
	# The layer's identity, not just the context field: setting ctx.player_outfit proves nothing -
	# it is set whether or not the player was rebuilt, which is exactly how dressing stayed broken
	# in two worlds while this test passed.
	var was_id := _player_layer_id()
	dress_player("M", "trunks_blue")
	await get_tree().create_timer(1.0).timeout
	var now_id := _player_layer_id()
	print("MENUTEST dressed sex=%s outfit=%s kept_position=%s rebuilt=%s" % [ctx.player_sex, ctx.player_outfit,
		  str(ctx.player_pos != Vector3.ZERO and before != Vector3.ZERO), str(now_id != was_id and now_id != 0)])
	if now_id == was_id:
		print("MENUTEST FAILED: the player layer was not rebuilt, so the outfit never reached the body")
		get_tree().quit(1)
		return
	set_player_hair("buzz")
	await get_tree().create_timer(1.0).timeout
	var hair_id := _player_layer_id()
	print("MENUTEST hair=%s rebuilt=%s" % [ctx.player_hair, str(hair_id != now_id and hair_id != 0)])
	if hair_id == now_id:
		print("MENUTEST FAILED: the hair change did not rebuild the player")
		get_tree().quit(1)
		return
	# Change again, twice: the first rebuild is the one that leaves a freed car behind, and the
	# damage only shows on the frames after it. One change each was not enough to catch a storm
	# of 180 errors a second.
	dress_player("F", "onepiece_teal")
	await get_tree().create_timer(0.6).timeout
	set_player_hair("long")
	await get_tree().create_timer(0.6).timeout
	print("MENUTEST changed again outfit=%s hair=%s drivable_cars=%d" % [ctx.player_outfit, ctx.player_hair, ctx.parked_cars.size()])
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


# Is the coast world actually one place? Walking from the surf to the avenue is 244 m through
# three districts, and the two ways it can silently fail are a constrain() that will not let you
# leave your own district and a walk_height() step you fall through. This samples the route the
# way the player walks it, one metre at a time.
func _coast_selftest() -> void:
	var c := ctx as CoastContext
	if c == null:
		print("COASTTEST not a coast world")
		get_tree().quit(1)
		return
	var pp: Vector3 = ctx.player.position if ctx.player != null else Vector3.ZERO
	print("COASTTEST player stands at (%.1f, %.2f, %.1f); walk_height there %.2f, on a road: %s"
		  % [pp.x, pp.y, pp.z, c.walk_height(pp.x, pp.z),
			 str(CoastContext.on_road(pp.x, pp.z, CoastContext.CROSS_HALF))])
	_what_is_here(Vector3(pp.x, pp.y, pp.z))
	var z: float = CoastContext.CROSS_Z[1]      # the middle inland street
	var x := 3.0
	var worst_step := 0.0
	var worst_at := 0.0
	var blocked_at := 1000.0
	var prev: float = c.walk_height(x, z)
	while x > CoastContext.AVENUE_X:
		var want := Vector3(x - 1.0, 0.0, z)
		var got: Vector3 = c.constrain(want)
		if absf(got.x - want.x) > 0.01:          # the corridor refused to let us go further
			blocked_at = want.x
			break
		x = got.x
		var h: float = c.walk_height(x, z)
		var step: float = absf(h - prev)
		if step > worst_step:
			worst_step = step
			worst_at = x
		prev = h
	print("COASTTEST reached x=%.1f (avenue is %.1f)%s" % [x, CoastContext.AVENUE_X,
		  "" if blocked_at > 999.0 else "  BLOCKED at %.1f" % blocked_at])
	print("COASTTEST largest height step %.2f m at x=%.1f" % [worst_step, worst_at])
	# stepping off the connector in town must hold you on the street, not fling you across it
	var off: Vector3 = c.constrain(Vector3(-150.0, 0.0, z + 40.0))
	print("COASTTEST off the kerb in town: z %.1f -> %.1f, x held at %.1f" % [z + 40.0, off.z, off.x])
	# and away from the connector the beach must still be a dead end at the hedges
	var sea: Vector3 = c.constrain(Vector3(-61.0, 0.0, 0.0))
	print("COASTTEST on the beach away from the connector, x=-61 clamps to %.1f" % sea.x)
	var ok: bool = x <= CoastContext.AVENUE_X + 1.0 and worst_step < 0.5
	# the streets must all be reachable, and every parked car must be one you could drive
	var reach := 0
	for cz: float in CoastContext.CROSS_Z:
		var q: Vector3 = c.constrain(Vector3(-150.0, 0.0, cz))
		if absf(q.z - cz) < 0.01:
			reach += 1
	print("COASTTEST inland streets reachable: %d/%d" % [reach, CoastContext.CROSS_Z.size()])
	var mid: Vector3 = c.constrain(Vector3(CoastContext.MID_X, 0.0, -75.0))
	print("COASTTEST the coast street holds at x=%.1f (want %.1f)" % [mid.x, CoastContext.MID_X])
	var inside: Vector3 = c.constrain(Vector3(-120.0, 0.0, -75.0))   # middle of a block
	print("COASTTEST inside a block -> pushed to (%.1f, %.1f)" % [inside.x, inside.z])
	print("COASTTEST parked cars you can drive: %d" % ctx.parked_cars.size())
	# Can a car actually get from the avenue to the sea? Walking corridors are one thing; a hotel
	# standing across the road is another, and that is exactly what the beach's own layers did -
	# they were written for a shore with nothing behind it, so their row ran unbroken through
	# every crossing. Sample each roadway and ask whether anything is parked in it.
	var clear_min := 1000.0
	var clear_at := Vector3.ZERO
	var blocked := 0
	for cz: float in CoastContext.CROSS_Z:
		var sx := -50.0
		while sx > CoastContext.AVENUE_X:
			var probe := Vector3(sx, 0.0, cz)
			var near: Array = ctx.nearest_obstacle(probe)
			if float(near[0]) < clear_min:
				clear_min = float(near[0])
				clear_at = probe
			if float(near[0]) < 0.0:
				blocked += 1
			sx -= 1.0
	print("COASTTEST roadway samples inside an obstacle: %d" % blocked)
	print("COASTTEST tightest clearance %.1f m at x=%.0f z=%.0f" % [clear_min, clear_at.x, clear_at.z])
	ok = ok and blocked == 0
	ok = ok and reach == CoastContext.CROSS_Z.size() and ctx.parked_cars.size() > 0
	print("COASTTEST %s" % ("DONE" if ok else "FAILED"))
	get_tree().quit(0 if ok else 1)


# Does the traffic actually behave? Screenshots show cars in a street; they do not show whether
# anyone turned, whether anyone drove through a building, or whether two cars ended up in the
# same place. This steps the layer at a fixed rate so a minute of traffic takes a second, and
# measures the three things that matter.
func _traffic_selftest() -> void:
	await get_tree().create_timer(1.0).timeout
	var t: CoastTraffic = null
	for l in layers:
		if l is CoastTraffic:
			t = l
	if t == null:
		print("TRAFFICTEST no traffic layer")
		get_tree().quit(1)
		return
	var dt := 1.0 / 60.0
	var turns := 0
	var off_road := 0
	var overlaps := 0
	var still := 0
	var was: Array = []
	for car in t.cars:
		was.append(str(car["axis"]) + str(car["sign"]))
	var moved := {}
	for step in 3600:                      # a minute of traffic
		ctx.tick(dt)
		t.tick(dt)
		for i in t.cars.size():
			var car: Dictionary = t.cars[i]
			var key := str(car["axis"]) + str(car["sign"])
			if key != was[i]:
				turns += 1
				was[i] = key
			var pos: Vector3 = (car["node"] as Node3D).position
			moved[i] = float(moved.get(i, 0.0)) + car["speed"] * dt
			# 3 m of slack: a car mid-turn is briefly across the corner of its own lane
			if not CoastContext.on_road(pos.x, pos.z, CoastContext.CROSS_HALF + 3.0,
									   StreetContext.ROAD_HALF + 3.0):
				off_road += 1
		for i in t.cars.size():
			for k in range(i + 1, t.cars.size()):
				var a: Vector3 = (t.cars[i]["node"] as Node3D).position
				var b: Vector3 = (t.cars[k]["node"] as Node3D).position
				if a.distance_to(b) < 2.2:
					overlaps += 1
	for i in t.cars.size():
		if float(moved.get(i, 0.0)) < 20.0:
			still += 1
	print("TRAFFICTEST %d cars, one minute" % t.cars.size())
	print("TRAFFICTEST turns taken: %d" % turns)
	print("TRAFFICTEST car-frames off the road: %d (of %d)" % [off_road, t.cars.size() * 3600])
	print("TRAFFICTEST frames with two cars overlapping: %d" % overlaps)
	print("TRAFFICTEST cars that barely moved: %d" % still)
	var ok: bool = turns > 0 and off_road == 0 and still <= 1
	print("TRAFFICTEST %s" % ("DONE" if ok else "FAILED"))
	get_tree().quit(0 if ok else 1)


# The claim worth testing about the town crowd is that they wait for cars. Stepping the crowd and
# the traffic together at a fixed rate makes a minute of town take a second, and counts what
# actually happened at the kerbs.
func _crowd_selftest() -> void:
	await get_tree().create_timer(1.0).timeout
	var c: CoastCrowd = null
	var t: CoastTraffic = null
	for l in layers:
		if l is CoastCrowd:
			c = l
		if l is CoastTraffic:
			t = l
	if c == null or t == null:
		print("CROWDTEST missing a layer")
		get_tree().quit(1)
		return
	var dt := 1.0 / 60.0
	var waits := 0
	var crossings := 0
	var gave_up := 0
	var off := 0
	var states: Array = []
	var moved := {}
	for person in c.people:
		states.append(str(person["state"]))
	for step in 3600:
		ctx.tick(dt)
		t.tick(dt)
		c.tick(dt)
		for i in c.people.size():
			var person: Dictionary = c.people[i]
			var now := str(person["state"])
			if now != states[i]:
				if now == "wait":
					waits += 1
				elif now == "cross":
					crossings += 1
				elif now == "walk" and states[i] == "wait":
					gave_up += 1
				states[i] = now
			if now == "wait":
				moved[i] = float(moved.get(i, 0.0)) + dt      # time actually spent at the kerb
			var pos: Vector3 = (person["node"] as Node3D).position
			if not CoastContext.on_road(pos.x, pos.z, CoastCrowd.WALK_OFFSET + 2.5):
				off += 1
	var stuck := 0
	for person in c.people:
		if str(person["state"]) == "wait" and float(person["wait"]) > CoastCrowd.PATIENCE:
			stuck += 1
	print("CROWDTEST %d people, one minute, alongside %d cars" % [c.people.size(), t.cars.size()])
	print("CROWDTEST stepped to a kerb to cross: %d" % waits)
	print("CROWDTEST crossings started once the road was clear: %d" % crossings)
	print("CROWDTEST gave up waiting and walked on: %d" % gave_up)
	var total := 0.0
	var longest := 0.0
	for k in moved:
		total += float(moved[k])
		longest = maxf(longest, float(moved[k]))
	print("CROWDTEST time held at kerbs by traffic: %.1f s in total, longest single person %.1f s" % [total, longest])
	print("CROWDTEST person-frames off the streets: %d (of %d)" % [off, c.people.size() * 3600])
	print("CROWDTEST still stuck at a kerb at the end: %d" % stuck)
	var ok: bool = waits > 0 and crossings > 0 and off == 0 and stuck == 0
	print("CROWDTEST %s" % ("DONE" if ok else "FAILED"))
	get_tree().quit(0 if ok else 1)


# Which meshes actually cover a point. The scene has no collision bodies, so a raycast finds
# nothing; this walks the tree and tests every mesh's world-space box instead. It is the only
# way to answer "what am I standing on" when the geometry is all batched.
func _what_is_here(at: Vector3) -> void:
	var hits: Array = []
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var box: AABB = m.global_transform * m.mesh.get_aabb()
		if at.x >= box.position.x and at.x <= box.end.x and at.z >= box.position.z and at.z <= box.end.z \
				and at.y >= box.position.y - 0.3 and at.y <= box.end.y + 0.3:
			hits.append("%s (top y %.2f)" % [str(m.get_path()).replace("/root/Main/", ""), box.end.y])
	print("COASTTEST under the player: %s" % ("nothing" if hits.is_empty() else ", ".join(hits)))


# What the frame has to carry. In the web build everything runs on one thread, so the counts that
# matter are skeletons (posed every frame) and draw calls, not triangles.
func _census() -> void:
	await get_tree().create_timer(2.0).timeout
	var skel := find_children("*", "Skeleton3D", true, false).size()
	var anim := find_children("*", "AnimationPlayer", true, false).size()
	var mesh := find_children("*", "MeshInstance3D", true, false).size()
	var nodes := 0
	for n in find_children("*", "Node", true, false):
		nodes += 1
	var live := 0
	var posed := 0
	for n in find_children("*", "AnimationPlayer", true, false):
		var a := n as AnimationPlayer
		if a.active:
			posed += 1
	for n in find_children("*", "Skeleton3D", true, false):
		if (n as Node3D).is_visible_in_tree():
			live += 1
	print("CENSUS world=%s skeletons=%d (%d drawn, %d animating) meshes=%d nodes=%d"
		  % [world_name, skel, live, posed, mesh, nodes])
	# where the meshes actually live, by layer - the only way to know what to batch
	var by_layer := {}
	for l in layers:
		by_layer[l.name] = l.find_children("*", "MeshInstance3D", true, false).size()
	var pairs: Array = []
	for k in by_layer:
		pairs.append([int(by_layer[k]), str(k)])
	pairs.sort_custom(func(a, b): return a[0] > b[0])
	for pr in pairs:
		if pr[0] > 0:
			print("CENSUS   %-26s %d meshes" % [pr[1], pr[0]])
	for l in layers:                       # a district hides a whole world inside one layer
		if l is DistrictLayer:
			for sub in (l as DistrictLayer).subs:
				print("CENSUS     %-24s %d meshes" % [sub.name, sub.find_children("*", "MeshInstance3D", true, false).size()])
	get_tree().quit(0)


# Which instance is currently the player layer. A rebuild makes a new one, so a changed id is
# proof the swap actually happened.
func _player_layer_id() -> int:
	for l in layers:
		if l.get_meta("segment", "") == "player":
			return l.get_instance_id()
	return 0


func _wear(spec: String) -> void:
	await get_tree().create_timer(0.8).timeout
	var p := spec.split(",")
	if p.size() >= 2:
		dress_player(p[0], p[1])
	if p.size() >= 3:
		await get_tree().create_timer(0.4).timeout
		set_player_hair(p[2])
