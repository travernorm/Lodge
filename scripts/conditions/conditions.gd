class_name Conditions
extends Resource
## One time slot on one stretch of water (REQ-0007, REQ-0008): the date, the
## slot, the weather and how hard it's falling, and the temperatures. Fish,
## the fish generator and the weather views read this, never a clock or the
## weather generator. A WeatherYear hands these out; tests and the tools build
## one with at().
##
## It's a Resource so a fixed day can be set in the inspector, but it is built
## at runtime and never saved as content. Temperatures are the lower °F of a
## 10°F band (50 means "the 50s").

@export var season := Calendar.Season.SPRING
@export_range(1, 30) var day := 1
@export var slot := Calendar.Slot.MORNING
@export var weather := Calendar.Weather.SUNNY
## How hard it rains, snows or storms, 0 to 1 (drizzle to downpour). Always 0
## for Sunny and Overcast.
@export_range(0.0, 1.0) var intensity := 0.0
## The day's air high, and the air in this slot.
@export var high_f := 50
@export var air_f := 50
## What the fish feel.
@export var water_f := 50


## A given slot. `high_f` is the day's high before the weather is applied; the
## climate says how much each weather takes off it. `spring_fed` water stays
## cool all year.
static func at(calendar: Calendar, climate: Climate, p_season: Calendar.Season, p_day: int,
		p_slot: Calendar.Slot, p_weather: Calendar.Weather, p_high_f: int, spring_fed := false,
		p_intensity := 0.0) -> Conditions:
	var c := Conditions.new()
	c.season = p_season
	c.day = clampi(p_day, 1, Calendar.DAYS_PER_SEASON)
	c.slot = p_slot
	c.weather = p_weather
	c.intensity = clampf(p_intensity, 0.0, 1.0) if climate.intensity_max[p_weather] > 0.0 else 0.0
	var high := p_high_f - climate.weather_drop[p_weather] * Calendar.BAND
	if p_weather == Calendar.Weather.SNOW:
		high = Calendar.AIR_MIN_F
	c.high_f = clampi(high, Calendar.AIR_MIN_F, Calendar.AIR_MAX_F)
	c.air_f = maxi(c.high_f - calendar.slot_drop[p_slot] * Calendar.BAND, Calendar.AIR_MIN_F)
	var water_range := Calendar.SPRING_FED_RANGE_F if spring_fed else Calendar.WATER_RANGE_F
	c.water_f = clampi(c.high_f - calendar.water_drop * Calendar.BAND, water_range.x, water_range.y)
	return c


## For the debug overlay and the tools: "Summer 12  Dusk  Rain 0.6",
## "air 70s  water 50s".
func describe() -> PackedStringArray:
	var w := _name(Calendar.Weather.keys(), weather)
	if intensity > 0.0:
		w += " %.1f" % intensity
	return PackedStringArray([
		"%s  %s  %s" % [Calendar.date_name(season, day), _name(Calendar.Slot.keys(), slot), w],
		"air %ds  water %ds" % [air_f, water_f],
	])


static func _name(keys: Array, i: int) -> String:
	return String(keys[i]).capitalize()
