@tool
class_name WeatherLook
extends Resource
## How the weather and the time of day look on screen (REQ-0009): one
## WeatherStyle per weather, a grade per time slot, and how long a change of
## weather takes to fade in. WeatherView paints it; WeatherMix does the sums.
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
## Multiplies the weather's tint, per slot (Dawn, Morning, Noon, Afternoon,
## Dusk, Night).
@export var slot_tint := PackedColorArray([Color("ffe0d0"), Color.WHITE, Color.WHITE,
		Color("fff4e6"), Color("ffc89a"), Color("8aa0e0")]):
	set(v):
		slot_tint = v
		emit_changed()
## Multiplies the weather's brightness, per slot.
@export var slot_brightness := PackedFloat32Array([0.85, 1.0, 1.05, 1.0, 0.85, 0.5]):
	set(v):
		slot_brightness = v
		emit_changed()

@export_group("Change")
## Seconds a change of weather or slot takes to fade in.
@export_range(0.0, 10.0, 0.1) var fade_seconds := 2.0:
	set(v):
		fade_seconds = v
		emit_changed()


## The style for one weather.
func style(w: Calendar.Weather) -> WeatherStyle:
	match w:
		Calendar.Weather.OVERCAST: return overcast
		Calendar.Weather.RAIN: return rain
		Calendar.Weather.SNOW: return snow
		Calendar.Weather.STORM: return storm
	return sunny


## True when every weather has a style and every slot a tint and brightness.
func is_complete() -> bool:
	for w in Calendar.Weather.size():
		if style(w as Calendar.Weather) == null:
			return false
	return slot_tint.size() == Calendar.Slot.size() and slot_brightness.size() == Calendar.Slot.size()


## Passes a style's edits on, so the game repaints while it's being tuned.
func _watch(old: WeatherStyle, new: WeatherStyle) -> WeatherStyle:
	if old != null and old.changed.is_connected(emit_changed):
		old.changed.disconnect(emit_changed)
	if new != null and not new.changed.is_connected(emit_changed):
		new.changed.connect(emit_changed)
	emit_changed()
	return new
