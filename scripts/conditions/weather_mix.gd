class_name WeatherMix
extends RefCounted
## What the screen shows for one moment of one day (REQ-0009, REQ-0015): the
## colour grade for the light and the shadows, the clouds, what falls and what
## happens on the water, worked out from a WeatherLook, the day's Conditions
## and the time of day. WeatherView paints it.
##
## A light day (intensity near 0) shows half the grade and a quarter of the
## falling; a full day (1) shows it all. Sunny and Overcast have no intensity
## and always show their full grade.

## The days the debug key steps through, in order: [weather, intensity].
const DEBUG_STEPS := [
	[Calendar.Weather.SUNNY, 0.0], [Calendar.Weather.OVERCAST, 0.0],
	[Calendar.Weather.RAIN, 0.3], [Calendar.Weather.RAIN, 1.0],
	[Calendar.Weather.SNOW, 0.3], [Calendar.Weather.SNOW, 1.0],
	[Calendar.Weather.STORM, 1.0],
]
## The most drops or flakes ever on screen, whatever the look asks for.
const MAX_FALL := 400
## How far the debug key moves the time of day with the debug overlay open.
const SCRUB_SLOTS := 0.5

## The light on the bright parts of the picture, and on the dark parts.
var tint := Color.WHITE
var shadow_tint := Color.WHITE
var brightness := 1.0
var saturation := 1.0
var contrast := 1.0
## Cloud shadows: how dark, how much of the sky, how fast in a calm (m/s).
var clouds := 0.0
var cloud_cover := 0.0
var cloud_speed_mps := 0.0
## Drops on screen (a float, so a change can fade in).
var fall_amount := 0.0
var fall_texture: Texture2D
var fall_variants := 1
var fall_slant_rows := 1
var splash_texture: Texture2D
var splash_frames := 1
var fall_colour := Color(1, 1, 1, 0)
var fall_speed_mps := 0.0
var fall_length_m := 0.0
var fall_slant_deg := 0.0
var fall_sway_m := 0.0
var ripples := 0.0
var flashes_per_minute := 0.0


## How much of a weather's look shows: 1 for Sunny and Overcast, 0.5 to 1 with
## the intensity for the rest.
static func strength(c: Conditions) -> float:
	return 1.0 if c.intensity <= 0.0 else lerpf(0.5, 1.0, c.intensity)

## The look for `c` at `day_time` (in slots, see SkyLight; left out, the
## middle of the day's own slot). The light blends between the two nearest
## slots' keys. A missing look or day gives the picture as drawn.
static func of(look: WeatherLook, c: Conditions, day_time := -1.0) -> WeatherMix:
	var m := WeatherMix.new()
	if look == null or c == null or not look.is_complete():
		return m
	var s := look.style(c.weather)
	var k := strength(c)
	var key := SkyLight.keys_at(day_time if day_time >= 0.0 else float(c.slot) + 0.5)
	var a: int = key[0]
	var b: int = key[1]
	var t: float = key[2]
	m.tint = Color.WHITE.lerp(s.tint, k) * look.slot_tint[a].lerp(look.slot_tint[b], t)
	m.tint.a = 1.0
	m.shadow_tint = Color.WHITE.lerp(s.tint, k) * look.slot_shadow_tint[a].lerp(look.slot_shadow_tint[b], t)
	m.shadow_tint.a = 1.0
	m.brightness = lerpf(1.0, s.brightness, k) * lerpf(look.slot_brightness[a], look.slot_brightness[b], t)
	m.saturation = lerpf(1.0, s.saturation, k)
	m.contrast = lerpf(1.0, s.contrast, k)
	m.clouds = s.clouds
	m.cloud_cover = s.cloud_cover
	m.cloud_speed_mps = s.cloud_speed_mps
	if s.fall_amount > 0:
		var share := 1.0 if c.intensity <= 0.0 else lerpf(0.25, 1.0, c.intensity)
		m.fall_amount = minf(s.fall_amount * share, MAX_FALL)
		_take_shape(m, s)
	m.ripples = s.ripples * k
	m.flashes_per_minute = s.flashes_per_minute * k
	return m


## Part way from `a` to `b` (t 0 to 1), for a change fading in. What falls
## takes `b`'s shape at once and fades its amount; with nothing falling in
## `b`, `a`'s drops thin out in their own shape. Lightning comes and goes
## with the fade, so a storm builds before it strikes.
static func blend(a: WeatherMix, b: WeatherMix, t: float) -> WeatherMix:
	t = clampf(t, 0.0, 1.0)
	var m := WeatherMix.new()
	m.tint = a.tint.lerp(b.tint, t)
	m.shadow_tint = a.shadow_tint.lerp(b.shadow_tint, t)
	m.brightness = lerpf(a.brightness, b.brightness, t)
	m.saturation = lerpf(a.saturation, b.saturation, t)
	m.contrast = lerpf(a.contrast, b.contrast, t)
	m.clouds = lerpf(a.clouds, b.clouds, t)
	m.cloud_cover = lerpf(a.cloud_cover, b.cloud_cover, t)
	m.cloud_speed_mps = lerpf(a.cloud_speed_mps, b.cloud_speed_mps, t)
	m.ripples = lerpf(a.ripples, b.ripples, t)
	m.flashes_per_minute = lerpf(a.flashes_per_minute, b.flashes_per_minute, t * t)
	m.fall_amount = lerpf(a.fall_amount, b.fall_amount, t)
	_take_shape(m, b if b.fall_amount > 0.0 else a)
	return m


## Copies what falls (not how much) from a style or another mix.
static func _take_shape(m: WeatherMix, from: Object) -> void:
	m.fall_texture = from.fall_texture
	m.fall_variants = from.fall_variants
	m.fall_slant_rows = from.fall_slant_rows
	m.splash_texture = from.splash_texture
	m.splash_frames = from.splash_frames
	m.fall_colour = from.fall_colour
	m.fall_speed_mps = from.fall_speed_mps
	m.fall_length_m = from.fall_length_m
	m.fall_slant_deg = from.fall_slant_deg
	m.fall_sway_m = from.fall_sway_m


## The debug key's next day: the same date, slot and stretch with the next
## weather in DEBUG_STEPS. The temperatures follow the new weather.
static func next_debug_day(calendar: Calendar, climate: Climate, c: Conditions) -> Conditions:
	var step: Array = DEBUG_STEPS[(debug_step(c) + 1) % DEBUG_STEPS.size()]
	# The day's high before the weather took its share, and whether this
	# stretch is spring fed (the water temperature says).
	var high := c.high_f + climate.weather_drop[c.weather] * Calendar.BAND
	if c.weather == Calendar.Weather.SNOW:
		high = climate.high_min_f[c.season]
	var spring_fed := Conditions.at(calendar, climate, c.season, c.day, c.slot, c.weather, high, true).water_f == c.water_f \
			and Conditions.at(calendar, climate, c.season, c.day, c.slot, c.weather, high, false).water_f != c.water_f
	return Conditions.at(calendar, climate, c.season, c.day, c.slot, step[0], high, spring_fed, step[1])


## Where `c` sits in DEBUG_STEPS: its weather, at the nearest intensity.
static func debug_step(c: Conditions) -> int:
	var best := 0
	var best_gap := INF
	for i in DEBUG_STEPS.size():
		if DEBUG_STEPS[i][0] == c.weather and absf(DEBUG_STEPS[i][1] - c.intensity) < best_gap:
			best = i
			best_gap = absf(DEBUG_STEPS[i][1] - c.intensity)
	return best


## "Rain 0.3  Dusk +0.25", for the corner of the screen: the weather, and
## the slot the light is in with how far through it.
static func describe(c: Conditions, day_time: float) -> String:
	var w := String(Calendar.Weather.keys()[c.weather]).capitalize()
	if c.intensity > 0.0:
		w += " %.1f" % c.intensity
	var slot := int(floorf(fposmod(day_time, float(Calendar.Slot.size()))))
	return "%s  %s +%.2f" % [w, String(Calendar.Slot.keys()[slot]).capitalize(), fposmod(day_time, 1.0)]
