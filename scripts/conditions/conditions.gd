class_name Conditions
extends Resource
## One day on one stretch of water (REQ-0007): the date, the time slot, the
## weather and the temperatures. Fish and the generator read this, never a
## clock. Until the Clock exists the fishing node rolls one per visit from its
## seed; tests and the generate_fish tool build one with at().
##
## It's a Resource so a fixed day can be set in the inspector, but it is built
## at runtime and never saved as content. Temperatures are the lower °F of a
## 10°F band (50 means "the 50s").

@export var season := Calendar.Season.SPRING
@export_range(1, 30) var day := 1
@export var slot := Calendar.Slot.MORNING
@export var weather := Calendar.Weather.SUNNY
## The day's air high, and the air in this slot.
@export var high_f := 50
@export var air_f := 50
## What the fish feel.
@export var water_f := 50


## A day rolled from the calendar: season, day, weather, the day's high band,
## and a slot. `spring_fed` water stays cool all year.
static func roll(calendar: Calendar, rng: RandomNumberGenerator, spring_fed := false) -> Conditions:
	var season := rng.randi_range(0, 3) as Calendar.Season
	var day := rng.randi_range(1, Calendar.DAYS_PER_SEASON)
	var slot := rng.randi_range(0, Calendar.Slot.size() - 1) as Calendar.Slot
	var weather := pick_weather(calendar.weather_odds(season), rng)
	var bands := (calendar.high_max_f[season] - calendar.high_min_f[season]) / Calendar.BAND
	var high := calendar.high_min_f[season] + rng.randi_range(0, bands) * Calendar.BAND
	return at(calendar, season, day, slot, weather, high, spring_fed)


## A given day. `high_f` is the day's high before the weather is applied.
static func at(calendar: Calendar, p_season: Calendar.Season, p_day: int, p_slot: Calendar.Slot,
		p_weather: Calendar.Weather, p_high_f: int, spring_fed := false) -> Conditions:
	var c := Conditions.new()
	c.season = p_season
	c.day = clampi(p_day, 1, Calendar.DAYS_PER_SEASON)
	c.slot = p_slot
	c.weather = p_weather
	var high := p_high_f - calendar.weather_drop[p_weather] * Calendar.BAND
	if p_weather == Calendar.Weather.SNOW:
		high = Calendar.AIR_MIN_F
	c.high_f = clampi(high, Calendar.AIR_MIN_F, Calendar.AIR_MAX_F)
	c.air_f = maxi(c.high_f - calendar.slot_drop[p_slot] * Calendar.BAND, Calendar.AIR_MIN_F)
	var water_range := Calendar.SPRING_FED_RANGE_F if spring_fed else Calendar.WATER_RANGE_F
	c.water_f = clampi(c.high_f - calendar.water_drop * Calendar.BAND, water_range.x, water_range.y)
	return c


## For the debug overlay and the tool: "Summer 12  Dusk  Overcast",
## "air 70s  water 50s".
func describe() -> PackedStringArray:
	return PackedStringArray([
		"%s  %s  %s" % [Calendar.date_name(season, day), _name(Calendar.Slot.keys(), slot), _name(Calendar.Weather.keys(), weather)],
		"air %ds  water %ds" % [air_f, water_f],
	])


## One weather, from a season's odds.
static func pick_weather(odds: PackedFloat32Array, rng: RandomNumberGenerator) -> Calendar.Weather:
	var total := 0.0
	for p in odds:
		total += p
	var r := rng.randf() * total
	for i in odds.size():
		r -= odds[i]
		if r < 0.0:
			return i as Calendar.Weather
	return Calendar.Weather.SUNNY


static func _name(keys: Array, i: int) -> String:
	return String(keys[i]).capitalize()
