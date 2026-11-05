@tool
class_name Bridge
extends RiverFeature
## A footbridge (REQ-0014): a deck across the river that the angler can walk
## along and cast from. The water runs under it unchanged. Footing asks
## carries() to know he can stand on it.

## The deck's ends (m), each on a bank.
@export var a := Vector2.ZERO
@export var b := Vector2(1, 0)
## How wide the deck is (m).
@export_range(1.0, 8.0) var width_m := 2.5


## True on the deck.
func carries(p: Vector2) -> bool:
	var d := b - a
	var t := (p - a).dot(d) / maxf(d.length_squared(), 0.0001)
	if t < 0.0 or t > 1.0:
		return false
	return p.distance_to(a + d * t) <= width_m * 0.5


## A bridge stands over the water and doesn't touch the current.
func reach() -> Rect2:
	return Rect2()


## Its middle is over the river.
func river_points() -> PackedVector2Array:
	return PackedVector2Array([a.lerp(b, 0.5)])


## The deck's outline.
func footprint() -> PackedVector2Array:
	var d := (b - a).normalized()
	var side := Vector2(-d.y, d.x) * width_m * 0.5
	return PackedVector2Array([a + side, b + side, b - side, a - side])
