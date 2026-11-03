class_name Boulder
extends RiverFeature
## A boulder: a slow cushion in front, a slack pocket behind (with a little
## back-flow right behind it) and a seam off each side.

## Boulder wake: how long the slack pocket runs, in rock radii.
const WAKE_LENGTH := 6.0
## How fast the wake spreads sideways with distance downstream.
const WAKE_SPREAD := 0.12
## 1 = dead slack right behind the rock; a bit more gives a little back-flow.
const WAKE_STRENGTH := 1.12

@export var centre := Vector2.ZERO
@export var radius := 1.0


static func make(p_centre: Vector2, p_radius: float) -> Boulder:
	var b := Boulder.new()
	b.centre = p_centre
	b.radius = p_radius
	return b


func blocks(p: Vector2) -> bool:
	return p.distance_squared_to(centre) < radius * radius


## Ideal flow past a cylinder, then the slack pocket behind it. Works in the
## current's own frame, so it suits a river running in any direction.
func shape_flow(p: Vector2, v: Vector2) -> Vector2:
	var rel := p - centre
	var d2 := rel.length_squared()
	var r2 := radius * radius
	if d2 < r2:
		return Vector2.ZERO
	var speed := v.length()
	var angle := v.angle() if speed > 0.0 else 0.0
	if angle != 0.0:
		rel = rel.rotated(-angle)
	var r4 := d2 * d2
	# Potential flow past a cylinder in a stream along +x, unit speed.
	var u := 1.0 - r2 * (rel.x * rel.x - rel.y * rel.y) / r4
	var w := -2.0 * r2 * rel.x * rel.y / r4
	var shaped := Vector2(u, w) * speed
	if rel.x > 0.0:
		var half := radius * (1.0 + WAKE_SPREAD * rel.x / radius)
		var wake := exp(-pow(rel.y / half, 2.0)) * exp(-(rel.x - radius) / (WAKE_LENGTH * radius))
		shaped.x *= 1.0 - WAKE_STRENGTH * clampf(wake, 0.0, 1.0)
	return shaped.rotated(angle) if angle != 0.0 else shaped


## Just outside its edge, on four sides: at least one is in the river.
func river_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for a in 4:
		out.append(centre + Vector2.from_angle(a * PI * 0.5) * (radius + 0.5))
	return out


func footprint() -> PackedVector2Array:
	var out := PackedVector2Array()
	for a in 12:
		out.append(centre + Vector2.from_angle(a * TAU / 12.0) * radius)
	return out
