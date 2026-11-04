class_name WeatherGenerator
extends RefCounted
## Rolls a year of weather from a region's Climate and a seed (REQ-0008).
## The same climate and seed always give the same year.
##
##   1. Weather by day: each day keeps yesterday's weather with the season's
##      persistence, otherwise it rolls the season's odds. That makes spells
##      while each weather's long-run share stays at its odds.
##   2. Highs by day: a smooth curve through the year that passes the middle
##      of each season's range mid-season, plus a slow wander, never moving
##      more than swing_bands a day and kept in the season's range.
##   3. Within the day: a storm day is before_storm until the storm slots.
##   4. Intensity: rolled once a day for weathers that have one.


## A year from `climate` and `p_seed`. Each step has its own stream, so tuning
## the highs doesn't reshuffle the weather.
static func year(climate: Climate, calendar: Calendar, p_seed: int) -> WeatherYear:
	var root := RandomNumberGenerator.new()
	root.seed = p_seed
	var weather_rng := _stream(root)
	var high_rng := _stream(root)
	var intensity_rng := _stream(root)
	var out := WeatherYear.new(calendar, climate)
	var total := Calendar.Season.size() * Calendar.DAYS_PER_SEASON
	var weather := -1
	var high := 0
	var wander := 0.0
	for n in total:
		var season := (n / Calendar.DAYS_PER_SEASON) as Calendar.Season
		var odds := climate.weather_odds(season)
		if weather < 0 or odds[weather] <= 0.0 or weather_rng.randf() >= climate.persistence[season]:
			weather = pick_weather(odds, weather_rng)
		wander = clampf(wander + high_rng.randf_range(-0.5, 0.5), -1.5, 1.5)
		var target := roundi(curve_f(climate, n) / Calendar.BAND + wander) * Calendar.BAND
		if n > 0:
			var swing := climate.swing_bands * Calendar.BAND
			target = clampi(target, high - swing, high + swing)
		high = clampi(target, climate.high_min_f[season], climate.high_max_f[season])
		var d := WeatherDay.new()
		d.season = season
		d.day = n % Calendar.DAYS_PER_SEASON + 1
		d.weather = weather as Calendar.Weather
		d.high_f = high
		d.slots.resize(Calendar.Slot.size())
		for s in Calendar.Slot.size():
			var storm_waits := weather == Calendar.Weather.STORM and not climate.storms_in(s)
			d.slots[s] = climate.before_storm if storm_waits else weather
		var lo := climate.intensity_min[weather]
		var hi := climate.intensity_max[weather]
		d.intensity = intensity_rng.randf_range(lo, hi) if hi > 0.0 else 0.0
		out.days.append(d)
	_mark_spells(out.days)
	return out


## Where the year's smooth high sits on day `n` (0 is Spring 1), in °F: each
## season's mid-range on its 15th day, straight lines between, wrapping from
## winter back to spring.
static func curve_f(climate: Climate, n: int) -> float:
	var seasons := Calendar.Season.size()
	var per := float(Calendar.DAYS_PER_SEASON)
	var t := fposmod(float(n) - (per - 1.0) * 0.5, per * seasons) / per
	var a := int(t) % seasons
	var b := (a + 1) % seasons
	return lerpf(_mid(climate, a), _mid(climate, b), t - floorf(t))


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


static func _mid(climate: Climate, season: int) -> float:
	return (climate.high_min_f[season] + climate.high_max_f[season]) * 0.5


## Numbers each run of same-weather days: day 1 of 3, 2 of 3, 3 of 3.
static func _mark_spells(days: Array[WeatherDay]) -> void:
	var start := 0
	for n in days.size() + 1:
		if n < days.size() and days[n].weather == days[start].weather:
			continue
		for k in range(start, n):
			days[k].spell_day = k - start + 1
			days[k].spell_length = n - start
		start = n


static func _stream(rng: RandomNumberGenerator) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = rng.randi()
	return r
