class_name Wind
extends RefCounted
## The wind over the land (REQ-0012): how hard it blows now, which way, and the
## gusts that roll across the bank. The grass reads it; later it could move the
## line or the fly.
##
## The day's weather and its intensity set a target strength from a table of
## winds per weather (the grass look's `wind_by_weather`). The strength eases
## toward it, so a storm builds and dies away over a few seconds instead of
## snapping on. Gusts are bands that travel downwind, so a field of grass waves
## in rows. Everything is in metres and seconds, and the only randomness (the
## day's wind direction and gust phase) comes from a seeded RNG (R8).

## Weaker weather of a kind blows this share of its full wind (intensity 0);
## the strongest blows all of it (intensity 1).
const LIGHT_SHARE := 0.6

## How hard it blows now (0 calm to 1 a full storm), and where it's heading.
var strength := 0.0
var target := 0.0
var direction := Vector2.RIGHT
## Seconds to ease from calm to a full storm.
var ease_seconds := 3.0
## Gust bands: the distance between them (m) and how fast they roll (m/s).
var gust_size_m := 9.0
var gust_speed_mps := 5.0

var _time := 0.0
var _phase := 0.0


## A wind for the day. `rng` picks the direction (mostly across the screen, so
## blades visibly lean) and where the gusts start.
func _init(rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		return
	var angle := rng.randf_range(-0.35, 0.35)
	direction = Vector2.from_angle(angle) * (1.0 if rng.randf() < 0.5 else -1.0)
	_phase = rng.randf() * TAU


## The target strength for a day: its weather's wind, scaled by intensity.
static func strength_for(c: Conditions, by_weather: PackedFloat32Array) -> float:
	if c == null or c.weather >= by_weather.size():
		return 0.0
	return clampf(by_weather[c.weather] * lerpf(LIGHT_SHARE, 1.0, c.intensity), 0.0, 1.0)


## A new day or a change of weather: the wind eases toward its strength.
func blow_for(c: Conditions, by_weather: PackedFloat32Array) -> void:
	target = strength_for(c, by_weather)


## Advances the clock and eases the strength toward the target.
func step(delta: float) -> void:
	_time += delta
	strength = move_toward(strength, target, delta / maxf(ease_seconds, 0.01))


## How far grass at `p` (m) leans downwind right now, 0 (upright) to about 1.
## A steady lean from the strength, plus gust bands rolling downwind, plus a
## little flutter so even a calm day breathes.
func lean_at(p: Vector2) -> float:
	var along := p.dot(direction)
	var t := (along - _time * gust_speed_mps) / maxf(gust_size_m, 0.1)
	var band := 0.5 + 0.5 * sin(t * TAU + _phase)
	var ripple := 0.5 + 0.5 * sin(t * TAU * 2.7 + _phase * 1.3 + 1.1)
	var gust := band * band * (0.7 + 0.3 * ripple)
	var flutter := sin(_time * 3.1 + p.x * 1.7 + p.y * 2.3) * (0.05 + 0.1 * strength)
	return strength * (0.45 + 0.55 * gust) + flutter


## The sideways part of the lean, as the screen shows it (+ is to the right).
func sway_at(p: Vector2) -> float:
	return lean_at(p) * direction.x
