class_name SkyLight
extends RefCounted
## The sky over one visit (REQ-0015): where the day has got to inside its
## slot, how much cloud is overhead right now, how far the clouds have drifted
## and how wet the ground is. WeatherMix turns it into colours; WeatherView
## steps it and paints.
##
## The time of day is in slots: 0 is the start of Dawn, 0.5 the middle of Dawn,
## 1 the start of Morning, up to 6 (the end of Night, which is Dawn again). A
## visit starts at the beginning of its slot, drifts to the end over
## `slot_seconds` and holds there: the light moves, the fish and the hatch
## don't. Everything is in metres and seconds, and the only randomness (where
## the cloud cover starts in its cycle) comes from a seeded RNG (R8).

## The cover wanders this far either side of the weather's own cover.
const BREATH := 0.22
## The two slow cycles the cover wanders on (s).
const BREATH_PERIODS := Vector2(71.0, 113.0)
## Seconds for dry ground to look fully wet in rain, and to dry again.
const WET_SECONDS := 20.0
const DRY_SECONDS := 60.0

## Where the day is, in slots (see above).
var day_time := 0.0
## Cloud overhead right now, 0 (clear) to 1 (solid).
var cover := 0.0
## How far the cloud shadows have drifted over the ground (m).
var drift := Vector2.ZERO
## 0 dry to 1 soaked.
var wetness := 0.0
## How long a visit takes to cross its slot. 0 holds the light at mid-slot.
var slot_seconds := 600.0

var _time := 0.0
var _phase := Vector2.ZERO


func _init(rng: RandomNumberGenerator = null) -> void:
	if rng != null:
		_phase = Vector2(rng.randf(), rng.randf()) * TAU


## A new visit: the light starts at the beginning of `slot`.
func begin(slot: Calendar.Slot) -> void:
	day_time = float(slot) + (0.0 if slot_seconds > 0.0 else 0.5)


## Moves the time of day by `slots` (the debug scrub), wrapping round the day.
func scrub(slots: float) -> void:
	day_time = fposmod(day_time + slots, float(Calendar.Slot.size()))


## Advances the sky. `base_cover` is the weather's own cloud cover,
## `cloud_mps` how fast its clouds travel, `wind_dir` where the wind is
## heading, and `raining` whether the ground is getting wet.
func step(delta: float, base_cover: float, cloud_mps: float, wind_dir: Vector2, raining: bool) -> void:
	_time += delta
	if slot_seconds > 0.0:
		var end := floorf(day_time) + 1.0
		if day_time < end - 0.0001:
			day_time = minf(day_time + delta / slot_seconds, end - 0.0001)
	cover = cover_at(base_cover, _time)
	drift += wind_dir * cloud_mps * delta
	if raining:
		wetness = minf(wetness + delta / WET_SECONDS, 1.0)
	else:
		wetness = maxf(wetness - delta / DRY_SECONDS, 0.0)


## The cover `seconds` into the visit: the weather's own, wandering slowly.
## A clear or a solid sky hardly wanders; a broken one swings the most.
func cover_at(base_cover: float, seconds: float) -> float:
	var base := clampf(base_cover, 0.0, 1.0)
	var room := minf(base, 1.0 - base) * 2.0
	var wave := 0.6 * sin(seconds * TAU / BREATH_PERIODS.x + _phase.x) \
			+ 0.4 * sin(seconds * TAU / BREATH_PERIODS.y + _phase.y)
	return clampf(base + BREATH * room * wave, 0.0, 1.0)


## The two slots whose light keys `time` sits between, and how far from the
## first to the second (0 to 1): [slot_a, slot_b, t]. The middle of a slot is
## that slot's key alone; the boundary between two is their even blend.
static func keys_at(time: float) -> Array:
	var n := Calendar.Slot.size()
	var x := fposmod(time - 0.5, float(n))
	var a := int(floorf(x)) % n
	return [a, (a + 1) % n, x - floorf(x)]
