class_name WeatherYear
extends RefCounted
## A year of weather from WeatherGenerator (REQ-0008): 120 days, Spring 1 to
## Winter 30. It hands out the Conditions for any day and slot, which is all
## the fish and the views read. Until the Clock exists the fishing node holds
## one per load and picks a day from it with roll().

var calendar: Calendar
var climate: Climate
## Day 0 is Spring 1 (Calendar.day_of_year()).
var days: Array[WeatherDay] = []


func _init(p_calendar: Calendar, p_climate: Climate) -> void:
	calendar = p_calendar
	climate = p_climate


func day(season: Calendar.Season, p_day: int) -> WeatherDay:
	return days[Calendar.day_of_year(season, p_day)]


## The Conditions for one slot of one day.
func conditions(season: Calendar.Season, p_day: int, slot: Calendar.Slot, spring_fed := false) -> Conditions:
	var d := day(season, p_day)
	return Conditions.at(calendar, climate, season, p_day, slot, d.weather_in(slot), d.high_f, spring_fed, d.intensity)


## A season, day and slot picked from `rng`, and their Conditions.
func roll(rng: RandomNumberGenerator, spring_fed := false) -> Conditions:
	var season := rng.randi_range(0, Calendar.Season.size() - 1) as Calendar.Season
	var d := rng.randi_range(1, Calendar.DAYS_PER_SEASON)
	var slot := rng.randi_range(0, Calendar.Slot.size() - 1) as Calendar.Slot
	return conditions(season, d, slot, spring_fed)


## For the debug overlay: "rain, day 2 of 3".
func describe(c: Conditions) -> String:
	var d := day(c.season, c.day)
	return "%s, day %d of %d" % [String(Calendar.Weather.keys()[d.weather]).to_lower(), d.spell_day, d.spell_length]
