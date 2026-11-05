class_name CameraRig
extends Camera2D
## The camera on a stretch (step A2, split from stream_scene.gd): follows the
## angler, looking a little ahead toward the water, inside the world's edges.
## The stream scene owns it and calls follow() each frame. Pixels.

## How far ahead of the angler it looks, toward the water (px).
const LOOK_AHEAD := 40.0


## `world` is the world's size (px).
func setup(world: Vector2, feet: Vector2, facing: Vector2) -> void:
	limit_left = 0
	limit_top = 0
	limit_right = roundi(world.x)
	limit_bottom = roundi(world.y)
	position_smoothing_enabled = true
	position_smoothing_speed = 5.0
	follow(feet, facing)


func follow(feet: Vector2, facing: Vector2) -> void:
	position = feet + Vector2(0, -8) + facing * LOOK_AHEAD


## Top-left of what's on screen (px), for a view `view_size` px across.
func screen_origin(view_size: Vector2) -> Vector2:
	return (get_screen_center_position() - view_size * 0.5).round()
