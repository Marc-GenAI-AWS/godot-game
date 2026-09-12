class_name HudLayer
extends BeachLayer

var label: Label


func build() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(18, 14)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(label)


func tick(_delta: float) -> void:
	label.text = "Beach Walk   %d fps\nLeft / Right or A / D to steer   Space or tap to stop and go" % Engine.get_frames_per_second()
