extends SceneTree
## Headless tests for the fish generator (REQ-0007): the calendar and the day,
## who's in the water, how many, how big, where, the hatch and how often fish
## rise, and the generate_fish tool on every stretch.
##   godot --headless --path . --script res://tests/fish_generator_test.gd

const RUNS := 1000

var _failures := 0
var _calendar: Calendar = load("res://data/calendar.tres")
var _climate: Climate = load("res://data/climates/central_oregon.tres")
var _stretch: Stretch = load("res://data/stretches/demo_freestone.tres")
var _redband: FishSpecies = load("res://data/fish/redband.tres")
var _brook: FishSpecies = load("res://data/fish/brook.tres")
var _cutthroat: FishSpecies = load("res://data/fish/cutthroat.tres")
var _caddis: Insect = load("res://data/insects/caddis.tres")
var _pmd: Insect = load("res://data/insects/pmd.tres")
var _field := RiverField.new()
var _gen: FishGenerator


func _initialize() -> void:
	_field.build_stretch(_stretch)
	_gen = FishGenerator.new(_stretch, _field, _calendar)
	_test_season_window()
	_test_conditions()
	_test_same_seed_same_fish()
	_test_who_can_be_here()
	_test_abundance()
	_test_count_and_gaps()
	_test_sizes()
	_test_big_fish_best_lies()
	_test_hatch()
	_test_activity()
	_test_planned_fish()
	_test_tool()
	if _failures == 0:
		print("Fish generator tests passed.")
		quit(0)
	else:
		printerr("%d fish generator test(s) failed." % _failures)
		quit(1)


func _day(season: Calendar.Season, day: int, slot: Calendar.Slot, weather: Calendar.Weather, high: int,
		spring_fed := false) -> Conditions:
	return Conditions.at(_calendar, _climate, season, day, slot, weather, high, spring_fed)


func _summer_dusk() -> Conditions:
	return _day(Calendar.Season.SUMMER, 12, Calendar.Slot.DUSK, Calendar.Weather.OVERCAST, 80)


func _test_season_window() -> void:
	var w := SeasonWindow.new()
	w.from_season = Calendar.Season.SPRING
	w.from_day = 15
	w.to_season = Calendar.Season.SUMMER
	w.to_day = 30
	_check(w.contains(Calendar.Season.SPRING, 15) and w.contains(Calendar.Season.SUMMER, 30), "window: both ends are in")
	_check(not w.contains(Calendar.Season.SPRING, 14) and not w.contains(Calendar.Season.FALL, 1), "window: outside is out")
	w.from_season = Calendar.Season.FALL
	w.from_day = 20
	w.to_season = Calendar.Season.SPRING
	w.to_day = 10
	_check(w.contains(Calendar.Season.WINTER, 5) and w.contains(Calendar.Season.SPRING, 10), "window: wraps across the new year")
	_check(not w.contains(Calendar.Season.SUMMER, 5), "window: and still leaves summer out")
	_check(SeasonWindow.allows(null, Calendar.Season.SUMMER, 3), "window: none means all year")


func _test_conditions() -> void:
	var c := _day(Calendar.Season.SUMMER, 12, Calendar.Slot.NOON, Calendar.Weather.SUNNY, 90)
	_check(c.high_f == 90 and c.air_f == 90 and c.water_f == 70, "day: a 90s summer noon has 70s water (high minus 2 bands)")
	c = _day(Calendar.Season.SUMMER, 12, Calendar.Slot.DAWN, Calendar.Weather.OVERCAST, 90)
	_check(c.high_f == 80 and c.air_f == 60 and c.water_f == 60, "day: overcast takes a band off, dawn two more")
	c = _day(Calendar.Season.SUMMER, 12, Calendar.Slot.NOON, Calendar.Weather.SUNNY, 90, true)
	_check(c.water_f == 50, "day: spring-fed water stays in the 50s in a heat wave")
	c = _day(Calendar.Season.WINTER, 3, Calendar.Slot.NOON, Calendar.Weather.SNOW, 40)
	_check(c.high_f == 30 and c.water_f == 30, "day: snow keeps the high in the 30s, water no colder than the 30s")
	var rng := FishGenerator.seeded(5)
	var year := WeatherGenerator.year(_climate, _calendar, 5)
	var all_ok := true
	for n in 500:
		var r := year.roll(rng)
		all_ok = all_ok and r.day >= 1 and r.day <= 30 and r.water_f >= 30 and r.water_f <= 70 \
			and _climate.weather_odds(r.season)[r.weather] > 0.0
		all_ok = all_ok and (r.weather == Calendar.Weather.SNOW or r.high_f >= _climate.high_min_f[r.season] - 10)
	_check(all_ok, "day: 500 rolled days are all valid, and never a weather the season can't have")
	_check(c.describe().size() == 2 and c.describe()[0].begins_with("Winter 3"), "day: describes itself (%s)" % [c.describe()])


## Acceptance 1.
func _test_same_seed_same_fish() -> void:
	var a := _gen.generate(_summer_dusk(), FishGenerator.seeded(42))
	var b := FishGenerator.new(_stretch, _field, _calendar).generate(_summer_dusk(), FishGenerator.seeded(42))
	var same := a.size() == b.size() and a.size() > 0
	for n in mini(a.size(), b.size()):
		same = same and a[n].species == b[n].species and a[n].length_in == b[n].length_in and a[n].lie == b[n].lie
	_check(same, "seed: the same stretch, day and seed give the same fish")
	var c := _gen.generate(_summer_dusk(), FishGenerator.seeded(43))
	var differs := false
	for n in mini(a.size(), c.size()):
		differs = differs or a[n].lie != c[n].lie or a[n].length_in != c[n].length_in
	_check(differs, "seed: another seed gives other fish")


## Acceptance 2.
func _test_who_can_be_here() -> void:
	var run := _entry(_redband, 1.0)
	run.window = SeasonWindow.new()
	run.window.from_season = Calendar.Season.FALL
	run.window.to_season = Calendar.Season.FALL
	var entries: Array[SpawnEntry] = [run, _entry(_brook, 1.0)]
	var spring := _day(Calendar.Season.SPRING, 5, Calendar.Slot.NOON, Calendar.Weather.SUNNY, 60)
	var ids := FishGenerator.eligible(entries, spring).map(func(e): return e.species.id)
	_check(ids == [&"brook"], "who: a species out of its season window isn't here (%s)" % [ids])
	var hot := _day(Calendar.Season.SUMMER, 5, Calendar.Slot.NOON, Calendar.Weather.SUNNY, 90)
	ids = FishGenerator.eligible(_stretch.spawn, hot).map(func(e): return e.species.id)
	_check(ids == [&"redband"], "who: 70s water leaves only the redband (%s)" % [ids])
	var gen := FishGenerator.new(_stretch, _field, _calendar)
	var ok := true
	for s in 50:
		for p in gen.generate(hot, FishGenerator.seeded(s)):
			ok = ok and p.species == _redband
	_check(ok, "who: the generator never puts a fish in water it can't live in")


## Acceptance 3: over 1,000 picks each species' share matches its abundance.
func _test_abundance() -> void:
	var entries: Array[SpawnEntry] = [_entry(_redband, 0.6), _entry(_cutthroat, 0.3), _entry(_brook, 0.1)]
	var rng := FishGenerator.seeded(7)
	var counts := {}
	for n in RUNS:
		var sp := FishGenerator.pick_species(entries, rng)
		counts[sp] = counts.get(sp, 0) + 1
	for e in entries:
		var share := float(counts.get(e.species, 0)) / RUNS
		_check(absf(share - e.abundance / 1.0) <= 0.03, "abundance: %s %.0f%% of fish for %.0f%% abundance" % [e.species.id, share * 100, e.abundance * 100])


## Acceptance 4.
func _test_count_and_gaps() -> void:
	var expected := _stretch.fish_count()
	_check(expected == 5, "count: the demo stretch holds 5 fish (%d)" % expected)
	var ok := true
	for s in 30:
		var plans := _gen.generate(_summer_dusk(), FishGenerator.seeded(s))
		ok = ok and plans.size() == expected
		for a in plans.size():
			ok = ok and _field.is_water(plans[a].lie) and plans[a].lie_score >= FishGenerator.MIN_LIE_SCORE
			for b in range(a + 1, plans.size()):
				ok = ok and plans[a].lie.distance_to(plans[b].lie) >= FishGenerator.LIE_GAP
	_check(ok, "count: 30 days of %d fish, each on its own good lie in water, %.0f m apart" % [expected, FishGenerator.LIE_GAP])
	var rich: Stretch = _stretch.duplicate()
	rich.fish_per_100m = 20.0
	var many := FishGenerator.new(rich, _field, _calendar).generate(_summer_dusk(), FishGenerator.seeded(1))
	_check(many.size() > expected and many.size() <= rich.fish_count(), "count: a richer stretch holds more, up to what the lies allow (%d)" % many.size())
	var none: Stretch = _stretch.duplicate()
	none.spawn = [] as Array[SpawnEntry]
	_check(FishGenerator.new(none, _field, _calendar).generate(_summer_dusk(), FishGenerator.seeded(1)).is_empty(),
		"count: no species, no fish")


## Acceptance 6.
func _test_sizes() -> void:
	var rng := FishGenerator.seeded(9)
	var inside := true
	var top := 0
	for n in RUNS:
		var l := FishGenerator.roll_length(_redband, rng)
		inside = inside and l >= _redband.min_length_in and l <= _redband.max_length_in
		if l > _redband.max_length_in - 0.1 * (_redband.max_length_in - _redband.min_length_in):
			top += 1
	_check(inside, "size: every length is inside the species range")
	_check(top < RUNS * 0.1, "size: the top 10%% of the range is rare (%d in %d)" % [top, RUNS])


## Acceptance 5.
func _test_big_fish_best_lies() -> void:
	var wins := 0
	var runs := 100
	for s in runs:
		var plans := _gen.generate(_summer_dusk(), FishGenerator.seeded(1000 + s))
		var scores: Array = plans.map(func(p): return p.lie_score)
		scores.sort()
		var biggest: FishPlan = plans[0]
		for p in plans:
			if p.length_in > biggest.length_in:
				biggest = p
		if biggest.lie_score >= scores[scores.size() / 2]:
			wins += 1
	_check(wins >= runs * 0.8, "lies: the biggest fish holds at least the median lie in %d of %d days" % [wins, runs])


## Acceptance 7.
func _test_hatch() -> void:
	var names := func(c: Conditions) -> Array: return _gen.active_hatch(c).map(func(h): return h.insect.id)
	var dusk := _summer_dusk()
	_check(names.call(dusk) == [&"caddis"], "hatch: a summer evening has caddis (%s)" % [names.call(dusk)])
	var morning := _day(Calendar.Season.SUMMER, 12, Calendar.Slot.MORNING, Calendar.Weather.SUNNY, 80)
	_check(&"pmd" in names.call(morning) and not &"caddis" in names.call(morning), "hatch: a summer morning has PMDs, not caddis")
	var bwo_sun := _day(Calendar.Season.FALL, 5, Calendar.Slot.AFTERNOON, Calendar.Weather.SUNNY, 60)
	var bwo_cloud := _day(Calendar.Season.FALL, 5, Calendar.Slot.AFTERNOON, Calendar.Weather.OVERCAST, 60)
	_check(not &"baetis" in names.call(bwo_sun) and &"baetis" in names.call(bwo_cloud), "hatch: BWOs need cloud")
	var winter := _day(Calendar.Season.WINTER, 5, Calendar.Slot.NOON, Calendar.Weather.SUNNY, 30)
	_check(names.call(winter).is_empty(), "hatch: nothing on a sunny winter noon")
	var lines := FishGenerator.describe_day(_gen, dusk, 42)
	_check(lines.size() == 3 and lines[2] == "hatch  Caddis  seed 42", "hatch: the overlay names it and the seed (%s)" % [lines])


## Acceptance 8.
func _test_activity() -> void:
	var dusk := _summer_dusk()
	var bare: Stretch = _stretch.duplicate()
	bare.hatches = [] as Array[HatchEntry]
	var no_hatch := FishGenerator.new(bare, null, _calendar)
	_check(_gen.activity(_brook, dusk) > no_hatch.activity(_brook, dusk), "activity: a fish rises more when the hatch it eats is on")
	var noon := _day(Calendar.Season.SUMMER, 12, Calendar.Slot.NOON, Calendar.Weather.SUNNY, 80)
	_check(_gen.activity(_brook, dusk) > _gen.activity(_brook, noon), "activity: busier on an overcast evening than a sunny noon")
	var storm := _day(Calendar.Season.WINTER, 1, Calendar.Slot.NIGHT, Calendar.Weather.STORM, 30)
	_check(no_hatch.activity(_redband, storm) >= _calendar.min_activity, "activity: never below the floor")
	# Rises: a keener fish dimples more often.
	var keen := _rises(1.0)
	var slow := _rises(_calendar.min_activity)
	_check(keen > slow * 3, "activity: a keen fish rises more often (%d vs %d rises in 2 minutes)" % [keen, slow])


func _rises(activity: float) -> int:
	var f := Fish.from_plan(FishPlan.new(_redband, 12.0, Vector2(20, 12), 0.8, activity), FishGenerator.seeded(3))
	var n := 0
	for i in 120 * 60:
		if f.update(1.0 / 60.0, Vector2(-50, -50), false) == &"dimple":
			n += 1
	return n


func _test_planned_fish() -> void:
	var f := Fish.from_plan(FishPlan.new(_cutthroat, 13.5, Vector2(30, 20), 0.7, 0.5), FishGenerator.seeded(2))
	_check(f.lie == Vector2(30, 20) and f.pos == f.lie and f.length_in == 13.5 and f.activity == 0.5,
		"plan: the fish holds its planned lie, length and activity")
	f.state = Fish.State.HOOKED
	f.leave()
	for i in roundi((Fish.GONE_TIME + 0.5) * 60):
		f.update(1.0 / 60.0, Vector2(-50, -50), false)
	_check(f.state == Fish.State.HOLDING and f.lie == Vector2(30, 20) and f.length_in == 13.5,
		"plan: after a break-off it comes back to the same lie, the same size")


## Acceptance 9: the tool runs on every stretch in the catalog.
func _test_tool() -> void:
	var tool: GDScript = load("res://tools/generate_fish.gd")
	for st in Catalog.shared().stretches:
		var id := st.resource_path.get_file().get_basename()
		var out: PackedStringArray = tool.run(PackedStringArray(["--stretch", id, "--season", "summer", "--slot", "dusk", "--seed", "4"]))
		_check(out.size() > 4 and not out[0].begins_with("error"), "tool: runs on stretch %s (%d lines)" % [id, out.size()])
		out = tool.run(PackedStringArray(["--stretch", id, "--runs", "20"]))
		_check(out.size() >= 3 and "20 runs" in out[0], "tool: summarises 20 runs on %s" % id)
	var bad: PackedStringArray = tool.run(PackedStringArray(["--season", "monsoon"]))
	_check(bad[0].begins_with("error"), "tool: a bad season is an error (%s)" % bad[0])


func _entry(sp: FishSpecies, abundance: float) -> SpawnEntry:
	var e := SpawnEntry.new()
	e.species = sp
	e.abundance = abundance
	return e


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
