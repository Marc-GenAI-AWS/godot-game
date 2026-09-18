class_name CoastDriverLayer
extends DriverLayer

# The coast world's player: the beach body on foot, and the car parked on the middle inland
# street by the promenade.
#
# It exists as a class rather than a configured DriverLayer because the right-click menu rebuilds
# the player layer whenever you change an outfit or a hair style, and a rebuild goes through
# ctx.layer(segment, default_script) - it can only reconstruct something it can name. A layer
# configured after construction comes back as a plain DriverLayer: the street world's man in a
# blue shirt, parked somewhere else.


func _init() -> void:
	walker_class = SkinnedPlayerLayer              # you start on the sand, not on a kerb
	start_pos = Vector3(-96.0, CoastContext.plateau_y(), CoastContext.CROSS_Z[1] - 4.2)
	start_yaw = PI * 0.5                           # nose inland, parked on the left kerb
