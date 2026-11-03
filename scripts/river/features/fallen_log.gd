@tool
class_name FallenLog
extends RiverFeature
## A fallen log: slack water tucked along it.

## How far (m) its slack water reaches, and how much it slows the current.
const REACH := 1.0
const SLOW := 0.9

@export var a := Vector2.ZERO
@export var b := Vector2(1, 0)


func calm(p: Vector2) -> float:
	var d := b - a
	var t := clampf((p - a).dot(d) / maxf(d.length_squared(), 0.0001), 0.0, 1.0)
	var dist := p.distance_to(a + d * t)
	if dist < REACH * 2.5:
		return 1.0 - SLOW * exp(-pow(dist / REACH, 2.0))
	return 1.0


## Either end reaches the water.
func river_points() -> PackedVector2Array:
	return PackedVector2Array([a, b])


func footprint() -> PackedVector2Array:
	return PackedVector2Array([a, b])
