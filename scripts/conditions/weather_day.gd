class_name WeatherDay
extends RefCounted
## One day of a WeatherYear (REQ-0008): its weather, the weather in each slot
## (a storm day is fair until the storm hits), how hard it falls, the day's
## high and where the day sits in its spell.

var season := Calendar.Season.SPRING
var day := 1
## The day's weather, which also names its spell.
var weather := Calendar.Weather.SUNNY
## The weather in each slot, Dawn ... Night.
var slots := PackedInt32Array()
## 0 to 1, for rain, snow and storms; 0 otherwise.
var intensity := 0.0
## The day's air high before the weather, as a band's lower °F.
var high_f := 50
## Which day of its spell this is (1 is the first), and how long the spell runs.
var spell_day := 1
var spell_length := 1


## The weather in one slot.
func weather_in(slot: Calendar.Slot) -> Calendar.Weather:
	return slots[slot] as Calendar.Weather
