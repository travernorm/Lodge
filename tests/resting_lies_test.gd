extends SceneTree
## Headless tests for resting lies (REQ-0011): the resting score, fish along
## the whole river, and resting fish slow to come up for a dry fly.
##   godot --headless --path . --script res://tests/resting_lies_test.gd

const DAYS := 300

var _failures := 0
var _stretch: Stretch = load("res://data/stretches/demo_freestone.tres")
var _calendar: Calendar = load("res://data/calendar.tres")
var _climate: Climate = load("res://data/climates/central_oregon.tres")
var _redband: FishSpecies = load("res://data/fish/redband.tres")
var _rules: DriftPastRules = load("res://data/take_rules/drift_past.tres")
var _dry: FlyPattern = load("res://data/tackle/flies/parachute_adams.tres")
var _field := RiverField.new()
var _rest: RestingLies


func _initialize() -> void:
	_field.build_stretch(_stretch)
	_rest = RestingLies.new(_field)
	_test_score_range()
	_test_cut_bank_rests()
	_test_fish_along_the_river()
	_test_dry_fly_discount()
	if _failures == 0:
		print("Resting lies tests passed.")
		quit(0)
	else:
		printerr("%d resting lies test(s) failed." % _failures)
		quit(1)


## Acceptance 1.
func _test_score_range() -> void:
	var hold := RiverField.HOLD_SPEED * RiverField.WATER_SPEED
	var in_range := true
	var dry_land := true
	var too_fast := true
	for j in _field.rows:
		for i in _field.cols:
			var idx := j * _field.cols + i
			var r := _rest.rest[idx]
			var p := _field.cell_pos(i, j)
			in_range = in_range and r >= 0.0 and r <= 1.0
			if not _field.is_water(p) or _field.is_solid(p):
				dry_land = dry_land and r == 0.0
			elif _field.velocity[idx].length() >= hold.y:
				too_fast = too_fast and r == 0.0
	_check(_rest.rest.size() == _field.cols * _field.rows, "score: one resting score per field cell")
	_check(in_range, "score: every resting score is 0 to 1")
	_check(dry_land, "score: none on land or rock")
	_check(too_fast, "score: none in water too fast to hold in")


## Acceptance 2: the cut-bank pool (tenths 6 and 7 of the river) rests fish,
## where the feeding score has none.
func _test_cut_bank_rests() -> void:
	var resting := 0
	var feeding := 0
	for j in _field.rows:
		for i in _field.cols:
			var p := _field.cell_pos(i, j)
			if not _field.is_water(p):
				continue
			var tenth := int(_field.nearest_centre(p) * 10 / _field.centre.size())
			if tenth != 6 and tenth != 7:
				continue
			var idx := j * _field.cols + i
			if _rest.rest[idx] >= FishGenerator.MIN_LIE_SCORE:
				resting += 1
			if _field.lie[idx] >= FishGenerator.MIN_LIE_SCORE:
				feeding += 1
	_check(resting > 50 and resting > feeding * 5, "cut bank: %d resting lies in the cut-bank pool (%d feeding)" % [resting, feeding])
	var p := Vector2(80, 60)
	_check(is_equal_approx(_rest.score_at(p), maxf(_field.lie_at(p), _rest.rest_at(p))), "score_at is the better of feeding and resting")


## Acceptance 3 and 4.
func _test_fish_along_the_river() -> void:
	var gen := FishGenerator.new(_stretch, _field, _calendar)
	var reaches := gen.reach_count()
	var days_with_fish := PackedInt32Array()
	days_with_fish.resize(reaches)
	days_with_fish.fill(0)
	var fish_in := PackedInt32Array()
	fish_in.resize(reaches)
	fish_in.fill(0)
	var lower := 0
	var resting_fish := 0
	var counts_ok := true
	var total := 0
	for s in DAYS:
		var rng := FishGenerator.seeded(s)
		var day := Conditions.at(_calendar, _climate, Calendar.Season.SUMMER, 12, Calendar.Slot.DUSK, Calendar.Weather.OVERCAST, 80)
		var plans := gen.generate(day, rng)
		counts_ok = counts_ok and plans.size() == _stretch.fish_count()
		var seen := {}
		for p in plans:
			total += 1
			var r := gen.reach_at(p.lie)
			fish_in[r] += 1
			seen[r] = true
			if int(_field.nearest_centre(p.lie) * 10 / _field.centre.size()) >= 5:
				lower += 1
			if p.resting:
				resting_fish += 1
				counts_ok = counts_ok and _rest.rest_at(p.lie) > _field.lie_at(p.lie)
		for r in seen:
			days_with_fish[r] += 1
	_check(counts_ok, "spread: every day still holds fish_count() fish, and resting fish sit on resting lies")
	_check(lower > total / 5, "spread: the lower half of the river holds %d of %d fish (it held 4 in 1,500 before)" % [lower, total])
	_check(resting_fish > 0, "spread: some fish hold on resting lies (%d)" % resting_fish)
	var quota := gen.reach_quota(1000, FishGenerator.seeded(1))
	var lengths_total := 0.0
	for r in reaches:
		lengths_total += quota[r]
	for r in reaches:
		var share := float(fish_in[r]) / maxf(total, 1)
		var expected := float(quota[r]) / maxf(lengths_total, 1)
		if expected <= 0.0:
			continue
		_check(share <= expected * 2.0 + 0.02, "spread: reach %d gets %.0f%% of fish for a %.0f%% share" % [r, share * 100, expected * 100])
		if expected * _stretch.fish_count() >= 1.0:
			_check(days_with_fish[r] >= DAYS / 2, "spread: reach %d holds fish on %d of %d days" % [r, days_with_fish[r], DAYS])


## Acceptance 7 and 8.
func _test_dry_fly_discount() -> void:
	var rng := FishGenerator.seeded(4)
	var feeding := Fish.from_plan(FishPlan.new(_redband, 12.0, Vector2(20, 12), 0.8, 1.0), rng)
	var plan := FishPlan.new(_redband, 12.0, Vector2(20, 12), 0.8, 1.0)
	plan.resting = true
	var resting := Fish.from_plan(plan, rng)
	_check(resting.resting and not feeding.resting, "plan: the fish knows it's on a resting lie")
	var near := Vector2(18.5, 12)
	var base: Dictionary = _rules.pass_odds(feeding, near, "Delicate", 0.0, _dry)
	var rest: Dictionary = _rules.pass_odds(resting, near, "Delicate", 0.0, _dry)
	_check(is_equal_approx(rest.chance, base.chance * _rules.resting_dry_factor),
		"dry: a resting fish's odds are x%s (%.2f vs %.2f)" % [_rules.resting_dry_factor, rest.chance, base.chance])
	_check("Resting lie" in rest.text and not "Resting lie" in base.text, "dry: the odds line names it (%s)" % rest.text)
	for t in [FlyPattern.Type.NYMPH, FlyPattern.Type.STREAMER]:
		var sunk: FlyPattern = _dry.duplicate()
		sunk.fly_type = t
		var a: Dictionary = _rules.pass_odds(resting, near, "Delicate", 0.0, sunk)
		var b: Dictionary = _rules.pass_odds(feeding, near, "Delicate", 0.0, sunk)
		_check(is_equal_approx(a.chance, b.chance) and not "Resting lie" in a.text,
			"%s: full odds over a resting fish" % String(FlyPattern.Type.keys()[t]).to_lower())


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
