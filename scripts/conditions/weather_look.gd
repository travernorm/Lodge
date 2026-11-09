@tool
class_name WeatherLook
extends Resource
## How the weather and the time of day look on screen (REQ-0009, REQ-0015):
## one WeatherStyle per weather, a light key per time slot (the light blends
## from one to the next as the day moves), the clouds and lightning, and how
## long a change of weather takes to fade in. WeatherView paints it; WeatherMix does the sums.
## Edit it in the Inspector (data/weather_looks/*.tres) with the game running.

@export var sunny: WeatherStyle:
	set(v):
		sunny = _watch(sunny, v)
@export var overcast: WeatherStyle:
	set(v):
		overcast = _watch(overcast, v)
@export var rain: WeatherStyle:
	set(v):
		rain = _watch(rain, v)
@export var snow: WeatherStyle:
	set(v):
		snow = _watch(snow, v)
@export var storm: WeatherStyle:
	set(v):
		storm = _watch(storm, v)

@export_group("Time of day")
## The light on the bright parts of the picture, per slot (Dawn, Morning,
## Noon, Afternoon, Dusk, Night). Multiplies the weather's tint.
@export var slot_tint := PackedColorArray([Color("ffe0d0"), Color.WHITE, Color.WHITE,
		Color("fff4e6"), Color("ffc89a"), Color("8aa0e0")]):
	set(v):
		slot_tint = v
		emit_changed()
## The light in the dark parts of the picture and under a cloud, per slot.
## Cooler than slot_tint gives warm light with blue shadows.
@export var slot_shadow_tint := PackedColorArray([Color("dbd9ff"), Color("e6f0ff"), Color("f0f5ff"),
		Color("e6ebff"), Color("ccc2ff"), Color("9eb8ff")]):
	set(v):
		slot_shadow_tint = v
		emit_changed()
## Multiplies the weather's brightness, per slot.
@export var slot_brightness := PackedFloat32Array([0.85, 1.0, 1.05, 1.0, 0.85, 0.5]):
	set(v):
		slot_brightness = v
		emit_changed()

## Minutes a visit takes to drift from the start of its slot's light to the
## end (the fish and hatch don't change). 0 holds the light at mid-slot.
@export_range(0.0, 60.0, 0.5) var slot_minutes := 10.0:
	set(v):
		slot_minutes = v
		emit_changed()

@export_group("Clouds and lightning")
## About how big one cloud shadow is (m).
@export_range(2.0, 60.0, 0.5) var cloud_size_m := 14.0:
	set(v):
		cloud_size_m = v
		emit_changed()
## How much faster the shadows travel in a full storm wind (m/s added).
@export_range(0.0, 20.0, 0.1) var cloud_wind_mps := 4.0:
	set(v):
		cloud_wind_mps = v
		emit_changed()
## Scales every lightning flash. 0 = no flashes at all.
@export_range(0.0, 1.0, 0.01) var flash_strength := 1.0:
	set(v):
		flash_strength = v
		emit_changed()
## How far the wind leans the rain and snow (degrees at a full storm wind).
@export_range(0.0, 45.0, 1.0) var wind_slant_deg := 20.0:
	set(v):
		wind_slant_deg = v
		emit_changed()

@export_group("Change")
## Seconds a change of weather or slot takes to fade in.
@export_range(0.0, 10.0, 0.1) var fade_seconds := 2.0:
	set(v):
		fade_seconds = v
		emit_changed()
## Seconds a storm takes to build and to pass.
@export_range(0.0, 60.0, 0.5) var storm_fade_seconds := 10.0:
	set(v):
		storm_fade_seconds = v
		emit_changed()


## The style for one weather.
func style(w: Calendar.Weather) -> WeatherStyle:
	match w:
		Calendar.Weather.OVERCAST: return overcast
		Calendar.Weather.RAIN: return rain
		Calendar.Weather.SNOW: return snow
		Calendar.Weather.STORM: return storm
	return sunny


## How long a change between two weathers takes: a storm builds and passes
## slowly, the rest fade quickly.
func fade_for(from: Calendar.Weather, to: Calendar.Weather) -> float:
	var storm := Calendar.Weather.STORM
	return storm_fade_seconds if (from == storm) != (to == storm) else fade_seconds


## True when every weather has a style and every slot its light key.
func is_complete() -> bool:
	for w in Calendar.Weather.size():
		if style(w as Calendar.Weather) == null:
			return false
	var n := Calendar.Slot.size()
	return slot_tint.size() == n and slot_shadow_tint.size() == n and slot_brightness.size() == n


## Passes a style's edits on, so the game repaints while it's being tuned.
func _watch(old: WeatherStyle, new: WeatherStyle) -> WeatherStyle:
	if old != null and old.changed.is_connected(emit_changed):
		old.changed.disconnect(emit_changed)
	if new != null and not new.changed.is_connected(emit_changed):
		new.changed.connect(emit_changed)
	emit_changed()
	return new
