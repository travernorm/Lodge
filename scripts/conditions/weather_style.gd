@tool
class_name WeatherStyle
extends Resource
## How one weather looks (REQ-0009): a colour grade over the whole picture,
## what falls from the sky, and what it does to the water. A WeatherLook holds
## one per weather. Edit them in the Inspector (data/weather_looks/*.tres).
##
## The rain, snow and storm numbers are for a full-strength day (intensity 1).
## A drizzle or flurries shows less, scaled by the day's intensity.

@export_group("Grade")
## Multiplies every colour on screen. White leaves the picture as it is.
@export var tint := Color.WHITE:
	set(v):
		tint = v
		emit_changed()
## 1 = as drawn, below 1 darker.
@export_range(0.0, 2.0, 0.01) var brightness := 1.0:
	set(v):
		brightness = v
		emit_changed()
## 1 = as drawn, 0 = grey.
@export_range(0.0, 2.0, 0.01) var saturation := 1.0:
	set(v):
		saturation = v
		emit_changed()
## 1 = as drawn, below 1 flatter.
@export_range(0.0, 2.0, 0.01) var contrast := 1.0:
	set(v):
		contrast = v
		emit_changed()
## Drifting cloud shadows, 0 = none (version C only).
@export_range(0.0, 1.0, 0.01) var clouds := 0.0:
	set(v):
		clouds = v
		emit_changed()

@export_group("Falling (rain, snow)")
## What falls. Empty = a plain streak (rain) or dot (snow) in fall_colour.
@export var fall_texture: Texture2D:
	set(v):
		fall_texture = v
		emit_changed()
## How many drops or flakes are on screen at full strength. 0 = nothing falls.
@export_range(0, 400) var fall_amount := 0:
	set(v):
		fall_amount = v
		emit_changed()
@export var fall_colour := Color(0.85, 0.9, 1.0, 0.5):
	set(v):
		fall_colour = v
		emit_changed()
## How fast it falls across the screen (m/s).
@export_range(0.0, 40.0, 0.1) var fall_speed_mps := 20.0:
	set(v):
		fall_speed_mps = v
		emit_changed()
## Length of a rain streak (m). 0 draws a dot, for snow.
@export_range(0.0, 2.0, 0.05) var fall_length_m := 0.5:
	set(v):
		fall_length_m = v
		emit_changed()
## Lean from straight down, in degrees. Storms blow sideways.
@export_range(-60.0, 60.0, 1.0) var fall_slant_deg := 8.0:
	set(v):
		fall_slant_deg = v
		emit_changed()
## Side to side drift (m), for snow.
@export_range(0.0, 2.0, 0.05) var fall_sway_m := 0.0:
	set(v):
		fall_sway_m = v
		emit_changed()

@export_group("On the water (version C)")
## Rain dimples on the water, 0 = none.
@export_range(0.0, 1.0, 0.01) var ripples := 0.0:
	set(v):
		ripples = v
		emit_changed()
## Lightning flashes a minute at full strength.
@export_range(0.0, 20.0, 0.1) var flashes_per_minute := 0.0:
	set(v):
		flashes_per_minute = v
		emit_changed()
