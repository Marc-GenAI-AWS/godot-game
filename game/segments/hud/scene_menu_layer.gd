class_name SceneMenuLayer
extends SceneLayer

# Right-click menu for trying things without reloading the page: swap the sky,
# ground, planting or furniture for any layer a model has written, and dress the
# player from the same wardrobe the crowd uses.
#
# Generated layers are discovered from segments/<segment>/generated/*.gd, so a new
# scene appears here as soon as the director installs it. Everything else in the
# scene is left alone: swapping one layer rebuilds only that layer.

const SEGMENTS := ["sky", "ground", "vegetation", "props"]
const PRETTY := {"sky": "Sky", "ground": "Ground", "vegetation": "Planting", "props": "Furniture"}

var menu: PopupMenu
var _entries: Array = []          # [kind, a, b] per menu id
var _root: CanvasLayer


func build() -> void:
	_root = CanvasLayer.new()
	_root.layer = 50
	add_child(_root)
	menu = PopupMenu.new()
	menu.id_pressed.connect(_on_pressed)
	_root.add_child(menu)
	ctx.menu_available = true
	_fill()


# The menu is rebuilt each time it opens: a director run can install a new layer
# while the game is running.
func _fill() -> void:
	menu.clear()
	_entries.clear()
	for seg in SEGMENTS:
		var found := _generated(seg)
		if found.is_empty():
			continue
		var sub := PopupMenu.new()
		sub.name = seg
		sub.id_pressed.connect(_on_pressed)
		menu.add_child(sub)
		_add(sub, "Original (hand-built)", ["segment", seg, ""])
		sub.add_separator()
		for path in found:
			_add(sub, _title(path), ["segment", seg, path])
		menu.add_submenu_item(PRETTY.get(seg, seg.capitalize()), seg)
	menu.add_separator()

	var wardrobe := PopupMenu.new()
	wardrobe.name = "wardrobe"
	wardrobe.id_pressed.connect(_on_pressed)
	menu.add_child(wardrobe)
	# a labelled separator, so it is obvious which half of the list is which
	for sex in ["F", "M"]:
		wardrobe.add_separator("Women" if sex == "F" else "Men")
		for outfit in _outfits(sex):
			_add(wardrobe, _outfit_title(outfit), ["outfit", sex, outfit])
	menu.add_submenu_item("Character", "wardrobe")

	var hair := PopupMenu.new()
	hair.name = "hair"
	hair.id_pressed.connect(_on_pressed)
	menu.add_child(hair)
	# the hair meshes are cut for one body or the other, so say which is which
	hair.add_separator("Women")
	for h in ["long", "buns"]:
		_add(hair, h.capitalize(), ["hair", h, ""])
	hair.add_separator("Men")
	for h in ["parted", "buzz"]:
		_add(hair, h.capitalize(), ["hair", h, ""])
	hair.add_separator()
	_add(hair, "None", ["hair", "none", ""])
	menu.add_submenu_item("Hair", "hair")
	menu.add_separator()
	_add(menu, "Reset scene", ["reset", "", ""])


func _add(to: PopupMenu, label: String, entry: Array) -> void:
	to.add_item(label, _entries.size())
	_entries.append(entry)


# Only layers written for this world. A ground layer from the beach reads tide_reach off
# the context and brings the street down with it; a sky is world-agnostic, so those are
# offered everywhere. Layers whose name says neither world are shown for the sky only,
# since there is no safe way to tell what they assume.
func _generated(segment: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://segments/%s/generated" % segment)
	if dir == null:
		return out
	# The coast world is hosted by the beach, so its swappable layers are the beach's; the street
	# ones live inside the avenue district and are not the host's to replace. Offering them here
	# would hand a StreetGround a CoastContext, and its `ctx as StreetContext` is null.
	var t := ctx.world_title.to_lower()
	var world: String = "beach" if (t.contains("beach") or t.contains("coast")) else "street"
	var other: String = "street" if world == "beach" else "beach"
	for f in dir.get_files():
		var name := f.trim_suffix(".remap")           # exported builds list .gd.remap
		if not name.ends_with(".gd"):
			continue
		var lower := name.to_lower()
		if lower.contains(other) or lower.contains("rejected"):   # keep failed attempts out of the menu
			continue
		if segment != "sky" and not lower.contains(world):
			continue
		out.append("res://segments/%s/generated/%s" % [segment, name])
	out.sort()
	return out


func _title(path: String) -> String:
	var base := path.get_file().get_basename()
	base = base.trim_prefix("v4-").trim_prefix("scene-")
	return base.replace("-", " ").replace("_", " ").capitalize()


func _outfits(sex: String) -> Array:
	# the coast world starts you on the sand, so swimwear belongs in its wardrobe too
	var w := ctx.world_title.to_lower()
	var beach: bool = w.contains("beach") or w.contains("coast")
	var f_beach := ["onepiece_red", "onepiece_navy", "onepiece_black", "onepiece_teal", "onepiece_pink", "onepiece_floral"]
	var m_beach := ["trunks_blue", "trunks_red", "trunks_floral", "trunks_black"]
	var casual := ["tee_white_jeans", "tee_red_shorts", "tee_navy_chinos", "tee_green_shorts", "tee_black_jeans"]
	if sex == "F":
		return (f_beach + casual) if beach else casual
	return (m_beach + casual) if beach else casual


func _outfit_title(outfit: String) -> String:
	var words := outfit.split("_")
	var garment: String = words[0]
	var rest := " ".join(words.slice(1))
	match garment:
		"onepiece": garment = "one-piece"
		# tee_white_jeans is two garments, so name both: "white tee with jeans"
		"tee": return "%s tee with %s" % [" ".join(words.slice(1, words.size() - 1)), words[-1]]
	return "%s %s" % [rest, garment]


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		_fill()
		# Embedded sub-windows (the web build, and the editor) place popups in viewport
		# coordinates; real OS windows want screen coordinates.
		var at := Vector2i(get_viewport().get_mouse_position())
		if not get_viewport().gui_embed_subwindows:
			at += DisplayServer.window_get_position()
		menu.reset_size()
		menu.position = at
		menu.popup()
		get_viewport().set_input_as_handled()


func _on_pressed(id: int) -> void:
	if id < 0 or id >= _entries.size():
		return
	var e: Array = _entries[id]
	ctx.menu_used = true
	var main := get_parent()
	match e[0]:
		"segment":
			if main.has_method("swap_segment"):
				main.swap_segment(e[1], e[2])
		"outfit":
			if main.has_method("dress_player"):
				main.dress_player(e[1], e[2])
		"hair":
			if main.has_method("set_player_hair"):
				main.set_player_hair(e[1])
		"reset":
			if main.has_method("reset_scene"):
				main.reset_scene()
