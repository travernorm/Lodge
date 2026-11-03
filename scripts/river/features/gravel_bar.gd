class_name GravelBar
extends RiverFeature
## Extra gravel on the bank, drawn on the ground. It doesn't change the water.

@export var centre := Vector2.ZERO
@export var radius := 2.0


func footprint() -> PackedVector2Array:
	var out := PackedVector2Array()
	for a in 12:
		out.append(centre + Vector2.from_angle(a * TAU / 12.0) * radius)
	return out
