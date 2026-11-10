@tool
class_name WeatherStyle
extends Resource
## How one weather looks (REQ-0009, REQ-0015): a colour grade over the whole
## picture, its clouds, what falls from the sky, and what it does to the water. A WeatherLook holds
## one per weather. Edit them in the Inspector (data/weather_looks/*.tres).
##
## The rain, snow and storm numbers are for a full-strength day (intensity 1).
## A drizzle or flurries shows less, scaled by the day's intensity.

## Each row of a rain sheet leans this many degrees more than the one above.
const FALL_ROW_DEG := 12.0

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

@export_group("Clouds")
## How dark and cool a cloud's shadow is, 0 = none.
@export_range(0.0, 1.0, 0.01) var clouds := 0.0:
	set(v):
		clouds = v
		emit_changed()
## How much of the sky is cloud, 0 clear to 1 solid. A broken sky (around 0.4)
## gives shadows that come and go; a solid one gives flat light.
@export_range(0.0, 1.0, 0.01) var cloud_cover := 0.0:
	set(v):
		cloud_cover = v
		emit_changed()
## How fast the shadows cross the ground (m/s) in a calm; wind adds to it.
@export_range(0.0, 10.0, 0.05) var cloud_speed_mps := 0.6:
	set(v):
		cloud_speed_mps = v
		emit_changed()

@export_group("Falling (rain, snow)")
## What falls: a sheet of square cells, `fall_variants` across (different
## drops or flakes, small to large) and `fall_slant_rows` down (the same drops
## leaning further, FALL_ROW_DEG more per row; one row for snow). Empty = a
## plain streak (rain) or dot (snow) in fall_colour.
@export var fall_texture: Texture2D:
	set(v):
		fall_texture = v
		emit_changed()
@export_range(1, 8) var fall_variants := 4:
	set(v):
		fall_variants = v
		emit_changed()
@export_range(1, 8) var fall_slant_rows := 1:
	set(v):
		fall_slant_rows = v
		emit_changed()
## Where a drop lands: a strip of `splash_frames` square frames. Empty = none.
@export var splash_texture: Texture2D:
	set(v):
		splash_texture = v
		emit_changed()
@export_range(1, 8) var splash_frames := 4:
	set(v):
		splash_frames = v
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
## Lean from straight down in a calm, in degrees. The wind adds to it.
@export_range(-60.0, 60.0, 1.0) var fall_slant_deg := 8.0:
	set(v):
		fall_slant_deg = v
		emit_changed()
## Side to side drift (m), for snow.
@export_range(0.0, 2.0, 0.05) var fall_sway_m := 0.0:
	set(v):
		fall_sway_m = v
		emit_changed()

@export_group("On the water and in the sky")
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
