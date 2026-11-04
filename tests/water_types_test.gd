extends SceneTree
## Headless tests for water types (REQ-0010): sorting the demo stretch's water
## into riffle, run, pool, tail-out, pocket, seam and eddy, species habitat,
## and the fish generator stocking each lie with a species that suits it.
##   godot --headless --path . --script res://tests/water_types_test.gd

const W := WaterTypeRules.WaterType

var _failures := 0
var _rules := WaterTypeRules.shared()
var _calendar: Calendar = load("res://data/calendar.tres")
var _climate: Climate = load("res://data/climates/central_oregon.tres")
var _stretch: Stretch = load("res://data/stretches/demo_freestone.tres")
var _brook: FishSpecies = load("res://data/fish/brook.tres")
var _field := RiverField.new()
var _types: WaterTypes


func _initialize() -> void:
	_field.build_stretch(_stretch)
	_types = WaterTypes.classify(_field, _rules)
	_test_rules()
	_test_every_cell_one_type()
	_test_known_spots()
	_test_same_every_time()
	_test_habitat_for()
	_test_pick_by_habitat()
	_test_species_follow_their_water()
	_test_no_habitat_is_as_before()
	if _failures == 0:
		print("Water types tests passed.")
		quit(0)
	else:
		printerr("%d water types test(s) failed." % _failures)
		quit(1)


func _test_rules() -> void:
	_check(_rules != null, "rules: data/water_types.tres loads as WaterTypeRules")
	_check(WaterTypeRules.LABELS.size() == W.size(), "rules: a label per water type")
	_check(WaterTypeRules.label(W.TAIL_OUT) == "Tail-out" and WaterTypeRules.label(WaterTypes.NONE) == "Bank",
		"rules: labels read as an angler says them")


## Acceptance 1: every wet cell has exactly one type, and each type but
## Tail-out turns up on the demo stretch.
func _test_every_cell_one_type() -> void:
	var ok := true
	for j in _field.rows:
		for i in _field.cols:
			var wet := _field.is_water(_field.cell_pos(i, j))
			var t := _types.cells[j * _field.cols + i]
			ok = ok and (t != 255) == wet and (t == 255 or t < W.size())
	_check(ok, "cells: a type for every wet cell, none on the bank")
	var counts := _types.counts()
	for t in W.size():
		if t != W.TAIL_OUT:
			_check(counts[t] > 0, "cells: the demo stretch has %s (%d cells)" % [WaterTypeRules.label(t), counts[t]])


## Acceptance 2: spots an angler would name.
func _test_known_spots() -> void:
	var spots := [
		[Vector2(10, 15), W.RIFFLE, "the head riffle"],
		[Vector2(25.5, 17.25), W.POCKET, "the slack behind the first boulder"],
		[Vector2(57.5, 41), W.POOL, "the pool below the bend"],
		[Vector2(108.75, 53.75), W.POOL, "the cut-bank pool"],
	]
	for s in spots:
		var t := _types.type_at(s[0])
		_check(t == s[1], "spots: %s is %s (%s)" % [s[2], WaterTypeRules.label(s[1]), WaterTypeRules.label(t)])
		_check(WaterTypes.at(_field, _rules, s[0]) == t, "spots: one point and the whole map agree at %s" % s[2])
	var eddy := 0
	for f in _stretch.features:
		if f is Eddy:
			for dx in range(-3, 4):
				for dy in range(-3, 4):
					if _types.type_at(f.centre + Vector2(dx, dy)) == W.EDDY:
						eddy += 1
	_check(eddy > 0, "spots: the eddy turns back upstream (%d eddy points)" % eddy)
	_check(_types.type_at(Vector2(-5, -5)) == WaterTypes.NONE, "spots: off the map is no water")


## Acceptance 3.
func _test_same_every_time() -> void:
	_check(WaterTypes.classify(_field, _rules).cells == _types.cells, "same: sorting the water twice gives the same map")


func _test_habitat_for() -> void:
	_check(is_equal_approx(_brook.habitat_for(W.POCKET, 0.2), 1.0), "habitat: a brook trout loves a pocket")
	_check(is_equal_approx(_brook.habitat_for(W.RIFFLE, 0.2), 0.2), "habitat: a type it doesn't list gets the stray weight")
	_check(is_equal_approx(FishSpecies.new().habitat_for(W.RIFFLE, 0.2), 1.0), "habitat: no list likes all water")


func _test_pick_by_habitat() -> void:
	var pools := _species(&"pools", W.POOL)
	var riffles := _species(&"riffles", W.RIFFLE)
	var entries: Array[SpawnEntry] = [_entry(pools, 0.5), _entry(riffles, 0.5)]
	var rng := FishGenerator.seeded(3)
	var hits := 0
	for n in 1000:
		if FishGenerator.pick_species_for(entries, W.POOL, 0.2, rng) == pools:
			hits += 1
	# 0.5 x 1 against 0.5 x 0.2: about 83%.
	_check(absf(hits / 1000.0 - 1.0 / 1.2) < 0.04, "pick: a pool lie goes to the pool fish %d in 1000" % hits)


## Acceptance 4 (on today's lies): two equally common species, one liking
## only seams and one only pockets. Most fish in each kind of water are the
## species that likes it. (Counted per water, because the demo stretch has
## about twice as many pocket lies as seam lies.)
func _test_species_follow_their_water() -> void:
	var seams := _species(&"seams", W.SEAM)
	var pockets := _species(&"pockets", W.POCKET)
	var st: Stretch = _stretch.duplicate()
	st.spawn = [_entry(seams, 0.5), _entry(pockets, 0.5)] as Array[SpawnEntry]
	var gen := FishGenerator.new(st, _field, _calendar)
	var home := {W.SEAM: 0, W.POCKET: 0}
	var total := {W.SEAM: 0, W.POCKET: 0}
	var typed := true
	for s in 200:
		for p in gen.generate(_summer_dusk(), FishGenerator.seeded(s)):
			typed = typed and p.water_type == _types.type_at(p.lie)
			if p.water_type == W.SEAM or p.water_type == W.POCKET:
				total[p.water_type] += 1
				if p.water_type == p.species.habitat[0].type:
					home[p.water_type] += 1
	_check(typed, "follow: every planned fish knows its lie's water type")
	for t in [W.SEAM, W.POCKET]:
		var share := float(home[t]) / maxi(total[t], 1)
		_check(total[t] > 50 and share >= 0.7, "follow: %.0f%% of %d fish in %s are the species that likes it" % [share * 100, total[t], WaterTypeRules.label(t)])


## Acceptance 5: species with no habitat list are picked by abundance alone,
## the same as before water types.
func _test_no_habitat_is_as_before() -> void:
	var a := FishSpecies.new()
	var b := FishSpecies.new()
	var entries: Array[SpawnEntry] = [_entry(a, 0.7), _entry(b, 0.3)]
	var same := true
	for s in 50:
		var r1 := FishGenerator.seeded(s)
		var r2 := FishGenerator.seeded(s)
		for t in W.size():
			same = same and FishGenerator.pick_species_for(entries, t, 0.2, r1) == FishGenerator.pick_species(entries, r2)
	_check(same, "no habitat: the same picks as abundance alone")


func _species(id: StringName, likes: WaterTypeRules.WaterType) -> FishSpecies:
	var sp := FishSpecies.new()
	sp.id = id
	var h := HabitatEntry.new()
	h.type = likes
	sp.habitat = [h] as Array[HabitatEntry]
	return sp


func _entry(sp: FishSpecies, abundance: float) -> SpawnEntry:
	var e := SpawnEntry.new()
	e.species = sp
	e.abundance = abundance
	return e


func _summer_dusk() -> Conditions:
	return Conditions.at(_calendar, _climate, Calendar.Season.SUMMER, 12, Calendar.Slot.DUSK,
		Calendar.Weather.OVERCAST, 80, false)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
