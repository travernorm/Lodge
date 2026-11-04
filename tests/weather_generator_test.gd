extends SceneTree
## Headless tests for the weather generator (REQ-0008): the same seed gives
## the same year, weathers keep their season's share, spells last longer with
## persistence, highs wander slowly and follow the season, storms wait for
## their slots, intensity, the Conditions it hands out, the fishing node's
## weather change, and the weather_year tool on every climate.
##   godot --headless --path . --script res://tests/weather_generator_test.gd

const YEARS := 100

var _failures := 0
var _calendar: Calendar = load("res://data/calendar.tres")
var _climate: Climate = load("res://data/climates/central_oregon.tres")


func _initialize() -> void:
	_test_same_seed()
	_test_shares()
	_test_spells()
	_test_highs()
	_test_season_curve()
	_test_storms()
	_test_intensity()
	_test_conditions()
	_test_tool()
	_finish.call_deferred()


## The scene needs a few frames to build its river before the fishing node
## has fish, so the scene test runs last.
func _finish() -> void:
	await _test_weather_change()
	if _failures == 0:
		print("Weather generator tests passed.")
		quit(0)
	else:
		printerr("%d weather generator test(s) failed." % _failures)
		quit(1)


func _year(p_seed: int, climate := _climate) -> WeatherYear:
	return WeatherGenerator.year(climate, _calendar, p_seed)


## Acceptance 1.
func _test_same_seed() -> void:
	var a := _year(42)
	var b := _year(42)
	var c := _year(43)
	var same := a.days.size() == 120
	var differs := false
	for n in a.days.size():
		same = same and a.days[n].weather == b.days[n].weather and a.days[n].high_f == b.days[n].high_f \
			and a.days[n].intensity == b.days[n].intensity and a.days[n].slots == b.days[n].slots
		differs = differs or a.days[n].weather != c.days[n].weather
	_check(same, "seed: the same climate and seed give the same 120 days")
	_check(differs, "seed: another seed gives another year")


## Acceptance 2.
func _test_shares() -> void:
	var counts := {}
	for y in 4 * YEARS:
		for d in _year(1000 + y).days:
			var k := Vector2i(d.season, d.weather)
			counts[k] = counts.get(k, 0) + 1
	var worst := 0.0
	for s in Calendar.Season.size():
		var odds := _climate.weather_odds(s)
		for w in Calendar.Weather.size():
			var share := float(counts.get(Vector2i(s, w), 0)) / (4 * YEARS * Calendar.DAYS_PER_SEASON)
			worst = maxf(worst, absf(share - odds[w]))
	_check(worst < 0.03, "shares: each weather's share per season is within 3%% of its odds (worst %.3f)" % worst)


## Acceptance 3.
func _test_spells() -> void:
	var sticky := _average_spell(_climate)
	var fresh := _climate.duplicate() as Climate
	fresh.persistence = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var loose := _average_spell(fresh)
	_check(sticky >= 1.5 * loose, "spells: persistence 0.5 gives longer spells (%.2f days) than 0 (%.2f)" % [sticky, loose])
	var y := _year(7)
	var marked := true
	for n in y.days.size():
		var d := y.days[n]
		marked = marked and d.spell_day >= 1 and d.spell_day <= d.spell_length
		if n > 0 and d.spell_day > 1:
			marked = marked and y.days[n - 1].weather == d.weather
	_check(marked, "spells: each day knows where it sits in its spell")


func _average_spell(climate: Climate) -> float:
	var spells := 0
	var days := 0
	for y in YEARS:
		for d in _year(2000 + y, climate).days:
			days += 1
			spells += 1 if d.spell_day == 1 else 0
	return float(days) / spells


## Acceptance 4. Inside a season the high moves at most swing_bands a day; it
## always stays in the season's range, whole bands.
func _test_highs() -> void:
	var swing := _climate.swing_bands * Calendar.BAND
	var steady := true
	var in_range := true
	for y in 20:
		var days := _year(3000 + y).days
		for n in days.size():
			var d := days[n]
			in_range = in_range and d.high_f >= _climate.high_min_f[d.season] and d.high_f <= _climate.high_max_f[d.season] \
				and d.high_f % Calendar.BAND == 0
			if n > 0 and d.day > 1:
				steady = steady and absi(d.high_f - days[n - 1].high_f) <= swing
	_check(steady, "highs: never more than %d band(s) from one day to the next inside a season" % _climate.swing_bands)
	_check(in_range, "highs: whole bands inside the season's range")


## Acceptance 5.
func _test_season_curve() -> void:
	var early := PackedFloat32Array([0, 0, 0, 0])
	var late := PackedFloat32Array([0, 0, 0, 0])
	for y in YEARS:
		for d in _year(4000 + y).days:
			if d.day <= 10:
				early[d.season] += d.high_f
			elif d.day > 20:
				late[d.season] += d.high_f
	_check(late[Calendar.Season.SPRING] > early[Calendar.Season.SPRING], "curve: spring warms up (%.0f to %.0f)" % [
		early[0] / (10 * YEARS), late[0] / (10 * YEARS)])
	_check(late[Calendar.Season.FALL] < early[Calendar.Season.FALL], "curve: fall cools down (%.0f to %.0f)" % [
		early[2] / (10 * YEARS), late[2] / (10 * YEARS)])


## Acceptance 6.
func _test_storms() -> void:
	var storm_days := 0
	var ok := true
	for y in 20:
		for d in _year(5000 + y).days:
			if d.weather != Calendar.Weather.STORM:
				ok = ok and Array(d.slots).all(func(w): return w == d.weather)
				continue
			storm_days += 1
			for s in Calendar.Slot.size():
				var expect := Calendar.Weather.STORM if _climate.storms_in(s) else _climate.before_storm
				ok = ok and d.weather_in(s) == expect
	_check(storm_days > 0, "storms: some storm days in 20 years (%d)" % storm_days)
	_check(ok, "storms: a storm day is fair until its storm slots; other days keep one weather")
	var c := _year(5000).conditions(Calendar.Season.SUMMER, 1, Calendar.Slot.MORNING)
	_check(c.weather != Calendar.Weather.STORM, "storms: never a storm in the morning")


## Acceptance 7.
func _test_intensity() -> void:
	var ok := true
	for y in 20:
		for d in _year(6000 + y).days:
			var lo := _climate.intensity_min[d.weather]
			var hi := _climate.intensity_max[d.weather]
			ok = ok and (d.intensity == 0.0 if hi == 0.0 else d.intensity >= lo and d.intensity <= hi)
	_check(ok, "intensity: 0 for Sunny and Overcast, inside the climate's range otherwise")


## The year hands out the same Conditions value the fish generator reads.
func _test_conditions() -> void:
	var y := _year(8)
	var all_ok := true
	for n in y.days.size():
		var d := y.days[n]
		for s in Calendar.Slot.size():
			var c := y.conditions(d.season, d.day, s)
			all_ok = all_ok and c.season == d.season and c.day == d.day and c.slot == s and c.weather == d.weather_in(s) \
				and c.water_f >= 30 and c.water_f <= 70 and c.air_f <= c.high_f \
				and (c.intensity == 0.0 or _climate.intensity_max[c.weather] > 0.0)
	_check(all_ok, "conditions: every slot of the year is a valid day")
	var rain := Conditions.at(_calendar, _climate, Calendar.Season.SPRING, 5, Calendar.Slot.NOON, Calendar.Weather.RAIN, 60, false, 0.7)
	var sun := Conditions.at(_calendar, _climate, Calendar.Season.SPRING, 5, Calendar.Slot.NOON, Calendar.Weather.SUNNY, 60, false, 0.7)
	_check(is_equal_approx(rain.intensity, 0.7) and sun.intensity == 0.0, "conditions: intensity only for weathers that have one")
	_check(rain.describe()[0] == "Spring 5  Noon  Rain 0.7", "conditions: describes the intensity (%s)" % rain.describe()[0])
	var spring_fed := y.conditions(Calendar.Season.SUMMER, 10, Calendar.Slot.NOON, true)
	_check(spring_fed.water_f >= 40 and spring_fed.water_f <= 50, "conditions: spring-fed water stays in the 40s to 50s")
	_check(y.describe(rain).contains("day "), "conditions: the year describes the spell (%s)" % y.describe(rain))


## A weather change on the same water (Traver, 2026-11-04): the fish stay,
## their activity follows the new hatch, and the change is signalled.
func _test_weather_change() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var fishing := main.find_child("Fishing", true, false)
	var heard: Array[Conditions] = []
	fishing.conditions_changed.connect(func(c: Conditions): heard.append(c))
	fishing.stock(null, 11)
	_check(heard.size() == 1 and heard[0] == fishing.conditions and fishing.weather != null,
		"fishing: stocking rolls a day from the year and signals it")
	var dusk := Conditions.at(_calendar, _climate, Calendar.Season.SUMMER, 12, Calendar.Slot.DUSK, Calendar.Weather.OVERCAST, 80)
	var noon := Conditions.at(_calendar, _climate, Calendar.Season.SUMMER, 12, Calendar.Slot.NOON, Calendar.Weather.STORM, 80)
	fishing.stock(dusk, 11)
	var before: Array = fishing.fish.duplicate()
	fishing.set_conditions(dusk)
	var dusk_activity := PackedFloat32Array(fishing.fish.map(func(f): return f.activity))
	fishing.set_conditions(noon)
	var same_fish: bool = fishing.fish.size() == before.size() and not before.is_empty()
	for n in mini(before.size(), fishing.fish.size()):
		same_fish = same_fish and fishing.fish[n] == before[n]
	var calmer := true
	for n in fishing.fish.size():
		calmer = calmer and fishing.fish[n].activity <= dusk_activity[n]
	_check(same_fish, "fishing: a weather change keeps the same fish (%d)" % before.size())
	_check(calmer and heard.size() == 4 and heard[3] == noon, "fishing: a stormy noon calms the fish an overcast dusk woke, and both are signalled")
	main.free()


## Acceptance 9.
func _test_tool() -> void:
	var tool: GDScript = load("res://tools/weather_year.gd")
	var names: PackedStringArray = tool.climates()
	_check(not names.is_empty(), "tool: finds the climates")
	for name in names:
		var out: PackedStringArray = tool.run(PackedStringArray(["--climate", name, "--seed", "3"]))
		_check(out.size() > 120 and not out[0].begins_with("error"), "tool: prints a year of %s (%d lines)" % [name, out.size()])
		out = tool.run(PackedStringArray(["--climate", name, "--years", "10"]))
		_check(out.size() == 2 + Calendar.Season.size() and "10 years" in out[0], "tool: summarises 10 years of %s" % name)
	var bad: PackedStringArray = tool.run(PackedStringArray(["--climate", "atlantis"]))
	_check(bad[0].begins_with("error"), "tool: an unknown climate is an error (%s)" % bad[0])


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
