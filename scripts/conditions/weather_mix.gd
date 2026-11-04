class_name WeatherMix
extends RefCounted
## What the screen shows for one slot's Conditions (REQ-0009): the colour
## grade, what falls and what happens on the water, worked out from a
## WeatherLook. WeatherView paints it. Three versions are on trial, and each
## adds to the one before:
##   A  the grade only (tint, brightness, saturation, contrast per weather and slot)
##   B  plus rain and snow falling
##   C  plus cloud shadows, rain dimples on the water and lightning
##
## A light day (intensity near 0) shows half the grade and a quarter of the
## falling; a full day (1) shows it all. Sunny and Overcast have no intensity
## and always show their full grade.

enum Version { GRADE, FALLING, WATER }

const VERSION_NAMES := ["A grade", "B + falling", "C + on the water"]
## The days the debug key steps through, in order: [weather, intensity].
const DEBUG_STEPS := [
	[Calendar.Weather.SUNNY, 0.0], [Calendar.Weather.OVERCAST, 0.0],
	[Calendar.Weather.RAIN, 0.3], [Calendar.Weather.RAIN, 1.0],
	[Calendar.Weather.SNOW, 0.3], [Calendar.Weather.SNOW, 1.0],
	[Calendar.Weather.STORM, 1.0],
]
## The most drops or flakes ever on screen, whatever the look asks for.
const MAX_FALL := 400

var tint := Color.WHITE
var brightness := 1.0
var saturation := 1.0
var contrast := 1.0
var clouds := 0.0
## Drops on screen (a float, so a change can fade in).
var fall_amount := 0.0
var fall_texture: Texture2D
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


## The look for `c` in one version. A missing look or day gives the picture
## as drawn.
static func of(look: WeatherLook, c: Conditions, version: Version) -> WeatherMix:
	var m := WeatherMix.new()
	if look == null or c == null or not look.is_complete():
		return m
	var s := look.style(c.weather)
	var k := strength(c)
	m.tint = Color.WHITE.lerp(s.tint, k) * look.slot_tint[c.slot]
	m.tint.a = 1.0
	m.brightness = lerpf(1.0, s.brightness, k) * look.slot_brightness[c.slot]
	m.saturation = lerpf(1.0, s.saturation, k)
	m.contrast = lerpf(1.0, s.contrast, k)
	if version >= Version.FALLING and s.fall_amount > 0:
		var share := 1.0 if c.intensity <= 0.0 else lerpf(0.25, 1.0, c.intensity)
		m.fall_amount = minf(s.fall_amount * share, MAX_FALL)
		m.fall_texture = s.fall_texture
		m.fall_colour = s.fall_colour
		m.fall_speed_mps = s.fall_speed_mps
		m.fall_length_m = s.fall_length_m
		m.fall_slant_deg = s.fall_slant_deg
		m.fall_sway_m = s.fall_sway_m
	if version == Version.WATER:
		m.clouds = s.clouds
		m.ripples = s.ripples * k
		m.flashes_per_minute = s.flashes_per_minute * k
	return m


## Part way from `a` to `b` (t 0 to 1), for a change fading in. What falls
## takes `b`'s shape at once and fades its amount; with nothing falling in
## `b`, `a`'s drops thin out in their own shape.
static func blend(a: WeatherMix, b: WeatherMix, t: float) -> WeatherMix:
	t = clampf(t, 0.0, 1.0)
	var m := WeatherMix.new()
	m.tint = a.tint.lerp(b.tint, t)
	m.brightness = lerpf(a.brightness, b.brightness, t)
	m.saturation = lerpf(a.saturation, b.saturation, t)
	m.contrast = lerpf(a.contrast, b.contrast, t)
	m.clouds = lerpf(a.clouds, b.clouds, t)
	m.ripples = lerpf(a.ripples, b.ripples, t)
	m.flashes_per_minute = b.flashes_per_minute
	m.fall_amount = lerpf(a.fall_amount, b.fall_amount, t)
	var shape := b if b.fall_amount > 0.0 else a
	m.fall_texture = shape.fall_texture
	m.fall_colour = shape.fall_colour
	m.fall_speed_mps = shape.fall_speed_mps
	m.fall_length_m = shape.fall_length_m
	m.fall_slant_deg = shape.fall_slant_deg
	m.fall_sway_m = shape.fall_sway_m
	return m


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


## "Rain 0.3  Dusk   look B + falling", for the corner of the screen.
static func describe(c: Conditions, version: Version) -> String:
	var w := String(Calendar.Weather.keys()[c.weather]).capitalize()
	if c.intensity > 0.0:
		w += " %.1f" % c.intensity
	return "%s  %s   look %s" % [w, String(Calendar.Slot.keys()[c.slot]).capitalize(), VERSION_NAMES[version]]
