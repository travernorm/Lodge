@tool
class_name Eddy
extends RiverFeature
## An eddy: water circulating back upstream along the bank. The swirl is the
## curl of a Gaussian stream function, so it has no sources or sinks and its
## streamlines close on themselves. Inside it the main current is calmed so the
## swirl takes over.

## The main current is calmed by this much at the centre.
const CALM := 0.7

@export var centre := Vector2.ZERO
## Size (m): the swirl peaks at one radius from the centre.
@export var radius := 3.0
## Peak swirl speed as a fraction of RiverField.WATER_SPEED.
@export_range(0.0, 2.0) var strength := 0.45


## Which way it turns, +1 or -1: back upstream along its nearer bank.
func prepare(field: RiverField) -> float:
	var frame := field.flow_frame(centre)
	var down: Vector2 = frame[0]
	var right := Vector2(-down.y, down.x)
	var side: float = frame[1]
	var bank := right * side
	return -signf(Vector2(-bank.y, bank.x).dot(down))


func calm(p: Vector2) -> float:
	return 1.0 - CALM * exp(-(p - centre).length_squared() / (2.0 * radius * radius))


func swirl(p: Vector2, spin: float) -> Vector2:
	var rel := p - centre
	var g := exp(-rel.length_squared() / (2.0 * radius * radius))
	if g < 0.0005:
		return Vector2.ZERO
	return Vector2(-rel.y, rel.x) / radius * g * exp(0.5) * strength * RiverField.WATER_SPEED * spin


## Four radii out it has faded to almost nothing (a Gaussian, 4 sigma).
func reach() -> Rect2:
	var r := radius * 4.0
	return Rect2(centre - Vector2(r, r), Vector2(r, r) * 2.0)


func river_points() -> PackedVector2Array:
	return PackedVector2Array([centre])
