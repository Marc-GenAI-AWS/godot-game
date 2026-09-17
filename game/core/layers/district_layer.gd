class_name DistrictLayer
extends SceneLayer

# One world's layers, hosted inside another world at an offset.
#
# The beach and the street are both 200 m Z-loops, but each one's layers cast the context to
# their own type (`ctx as BeachContext`, `ctx as StreetContext`), so a single merged context
# cannot serve both - GDScript has one base class. Instead each district keeps its own context
# and builds in its own local coordinates, exactly as it does when it is the whole world, and
# this layer translates the result into the host world.
#
# That is what makes the merge cheap: not one line of the beach or street layers changes, and
# every model-written layer in segments/*/generated stays valid, because inside a district the
# road is still at x = 0 and the ground is still flat.
#
# What has to cross the boundary is handled here:
#   * obstacles      - registered in the district AND forwarded to the host, so the host's
#                      player collides with district hedges and the district's crowd still
#                      collides with them locally
#   * the player     - a proxy node tracks the host player in district coordinates, so district
#                      crowds and traffic react to the real player
#   * the palette    - the host's sky publishes the colours; the district reads them each frame,
#                      so swapping the sky relights everything
#   * the Z wrap     - the host player emits world_wrapped; the district's layers need it too
#
# Everything else (textures, time) is copied by reference at build time.

var origin := Vector3.ZERO                 # where the district's (0, 0, 0) sits in the host world
var sub_ctx: WorldContext                  # set before setup(): the district's own context
var make_layers: Callable                  # func(sub_ctx) -> Array[SceneLayer]
var title := "district"

var subs: Array[SceneLayer] = []
var root: Node3D
var _proxy: Node3D


func build() -> void:
	root = Node3D.new()
	root.name = title
	root.position = origin
	add_child(root)

	sub_ctx.host = ctx
	sub_ctx.host_origin = origin
	add_child(sub_ctx)                      # a WorldContext is a Node; the host only ticks its own
	_share_textures()
	_read_palette()

	# district crowds and traffic steer around the real player, in their own coordinates
	_proxy = Node3D.new()
	_proxy.name = "PlayerProxy"
	root.add_child(_proxy)
	sub_ctx.player = _proxy

	for l in make_layers.call(sub_ctx):
		var gname: String = l.get_script().get_global_name()
		l.name = gname if gname != "" else str(l.get_script().resource_path).get_file().get_basename()
		l.set_meta("segment", sub_ctx.built_of.get(l.get_instance_id(), ""))
		l.set_meta("district", title)
		root.add_child(l)
		l.setup(sub_ctx)
		subs.append(l)

	ctx.world_wrapped.connect(_on_host_wrapped)


func tick(delta: float) -> void:
	if root == null:
		return
	if ctx.player != null:
		_proxy.position = ctx.player.position - origin
	sub_ctx.tick(delta)                     # advances its clock and clears its dynamic obstacles
	_read_palette()
	for l in subs:
		l.tick(delta)
	# moving obstacles were re-registered during those ticks; hand them to the host so the
	# player is blocked by district traffic too (the host cleared its own list this frame)
	for ob in sub_ctx.dynamic_obstacles:
		ctx.dynamic_obstacles.append([ob[0] + origin, ob[1]])


func _on_host_wrapped(dz: float) -> void:
	sub_ctx.world_wrapped.emit(dz)


func _share_textures() -> void:
	# by reference: a second set would double the VRAM and the generation cost for no gain
	for p in ["noise_tex", "sand_normal_tex", "cloud_tex", "cloud_cover_tex",
			  "window_tex", "frond_tex", "soft_disc_tex"]:
		sub_ctx.set(p, ctx.get(p))


func _read_palette() -> void:
	for p in ["sky_zenith", "sky_horizon", "sun_dir", "sun_color", "fog_color"]:
		sub_ctx.set(p, ctx.get(p))
