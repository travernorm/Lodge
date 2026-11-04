class_name Climate
extends Resource
## A region's weather (REQ-0008): how warm each season runs, how often each
## weather comes up, how long a spell lasts, when storms hit and how hard rain
## and snow fall. One file per region in data/climates/, so a new region is a
## new file. WeatherGenerator turns it and a seed into a year of days.
##
## Temperatures are the lower °F of a 10°F band: 50 means "the 50s". Lists
## with one number per season run Spring, Summer, Fall, Winter; lists with one
## per weather run Sunny, Overcast, Rain, Snow, Storm.

@export_group("Temperature")
## The day's air high, lowest and highest band, per season.
@export var high_min_f := PackedInt32Array([40, 70, 50, 30])
@export var high_max_f := PackedInt32Array([60, 90, 70, 40])
## How many bands the high can move from one day to the next.
@export_range(0, 3) var swing_bands := 1
## Bands the weather takes off the day's high, per weather. Snow also keeps
## the high in the 30s.
@export var weather_drop := PackedInt32Array([0, 1, 1, 0, 1])

@export_group("Weather")
## Chance of each weather, per season. Each season's five numbers add up to 1.
## They're also each weather's long-run share of the season's days.
@export var weather_spring := PackedFloat32Array([0.35, 0.30, 0.25, 0.05, 0.05])
@export var weather_summer := PackedFloat32Array([0.65, 0.15, 0.05, 0.0, 0.15])
@export var weather_fall := PackedFloat32Array([0.40, 0.35, 0.20, 0.05, 0.0])
@export var weather_winter := PackedFloat32Array([0.30, 0.35, 0.05, 0.30, 0.0])
## Per season, the chance a day simply keeps yesterday's weather before the
## odds are rolled. 0 rolls fresh every day; 0.5 gives spells of 2 to 3 days.
@export var persistence := PackedFloat32Array([0.5, 0.5, 0.5, 0.5])

@export_group("Storms")
## The slots a storm hits in. A storm day's other slots take before_storm.
@export_flags("Dawn", "Morning", "Noon", "Afternoon", "Dusk", "Night") var storm_slots := 0b011000
@export var before_storm := Calendar.Weather.SUNNY

@export_group("Intensity")
## How hard it rains, snows or storms, 0 to 1, rolled once a day from this
## range, per weather. 0 to 0 means the weather has no intensity.
@export var intensity_min := PackedFloat32Array([0.0, 0.0, 0.2, 0.2, 0.5])
@export var intensity_max := PackedFloat32Array([0.0, 0.0, 1.0, 1.0, 1.0])


## The weather odds for one season.
func weather_odds(season: Calendar.Season) -> PackedFloat32Array:
	match season:
		Calendar.Season.SUMMER: return weather_summer
		Calendar.Season.FALL: return weather_fall
		Calendar.Season.WINTER: return weather_winter
	return weather_spring


## True when `slot` is one a storm hits in.
func storms_in(slot: Calendar.Slot) -> bool:
	return (storm_slots & (1 << slot)) != 0
