extends SceneTree
## Fly rods (REQ-0005): fly type compatibility and the tackle, the longest
## line under every casting rule set, timing forgiveness, and a fish too big
## for the rod.
##   godot --headless --path . --script res://tests/rod_test.gd

const RULES := [
	"res://data/cast_rules/classic.tres",
	"res://data/cast_rules/count_false_casts.tres",
	"res://data/cast_rules/find_your_tempo.tres",
]

var _failures := 0
var _tuning: CastTuning = load("res://data/cast_tuning.tres")
var _redband: FishSpecies = load("res://data/fish/redband.tres")


func _initialize() -> void:
	_test_throws()
	_test_tackle_filters_flies()
	_test_starter_rods()
	_test_line_cap_every_rule_set()
	_test_forgiveness_every_rule_set()
	_test_overlap_forgiveness()
	_test_rod_load()
	_test_oversized_fish_snaps_sooner()
	if _failures == 0:
		print("Rod tests passed.")
		quit(0)
	else:
		printerr("%d rod test(s) failed." % _failures)
		quit(1)


# --- Compatibility ---------------------------------------------------------

func _test_throws() -> void:
	var rod := _rod(1 | 4)  # dries and streamers
	_check(rod.throws(_fly(FlyPattern.Type.DRY)), "a dry and streamer rod throws a dry")
	_check(not rod.throws(_fly(FlyPattern.Type.NYMPH)), "it doesn't throw a nymph")
	_check(rod.throws(_fly(FlyPattern.Type.STREAMER)), "it throws a streamer")
	_check(not rod.throws(null), "no fly is never thrown")
	_check(rod.types_text() == "dries, streamers", "its types read 'dries, streamers' (%s)" % rod.types_text())


func _test_tackle_filters_flies() -> void:
	var dry_a := _fly(FlyPattern.Type.DRY)
	var nymph := _fly(FlyPattern.Type.NYMPH)
	var dry_b := _fly(FlyPattern.Type.DRY)
	var flies: Array[FlyPattern] = [dry_a, nymph, dry_b]
	var rods: Array[FlyRod] = [_rod(1), _rod(2 | 4), _rod(1 | 2)]
	var t := Tackle.new(rods, flies)
	_check(t.rod() == rods[0] and t.fly() == dry_a, "starts on the first rod and the first fly it throws")
	var usable := t.usable_flies()
	_check(usable.size() == 2 and usable[0] == dry_a and usable[1] == dry_b, "a dry-only rod's fly box skips the nymph")
	t.next_fly()
	_check(t.fly() == dry_b, "Y skips the nymph")
	t.next_fly()
	_check(t.fly() == dry_a, "and comes back round")
	t.next_rod()
	_check(t.fly() == nymph, "a nymph rod ties on the nymph in place of the dry")
	_check(not t.next_fly(), "with only one fly it throws, Y has nowhere to go")
	t.next_rod()
	_check(t.fly() == nymph, "a rod that throws the tied-on fly keeps it")
	t.next_rod()
	_check(t.rod() == rods[0] and t.fly() == dry_a, "L2 comes back round to the first rod and a dry")
	var bare := Tackle.new([_rod(4)] as Array[FlyRod], flies)
	_check(bare.fly() == null and bare.usable_flies().is_empty(), "a streamer rod with no streamers has no fly")
	_check(bare.cycle_fly() == "No fly in the box suits this rod.", "and says so")
	var none := Tackle.new([] as Array[FlyRod], flies)
	_check(none.rod() == null and none.fly() == dry_a, "with no rods, every fly works")


func _test_starter_rods() -> void:
	var cat := Catalog.shared()
	var dads := cat.rod(&"dads_glass_4wt")
	var five := cat.rod(&"graphite_5wt")
	var seven := cat.rod(&"fast_7wt")
	_check(dads != null and five != null and seven != null, "the three starter rods are in the catalog")
	if dads == null or five == null or seven == null:
		return
	var adams := cat.fly(&"parachute_adams")
	_check(dads.throws(adams) and five.throws(adams), "the 4- and 5-weight throw the Parachute Adams")
	_check(not seven.throws(adams), "the 7-weight doesn't throw dries (Traver, 2026-11-03)")
	_check(dads.max_line_m <= CastRules.MIDDLE_MAX, "Dad's rod can't reach Long")
	_check(seven.max_line_m > five.max_line_m and five.max_line_m > dads.max_line_m, "longer line from the 4- to the 5- to the 7-weight")
	_check(dads.forgiveness > five.forgiveness and five.forgiveness > seven.forgiveness, "Dad's is the most forgiving, the 7-weight the least")
	_check(is_equal_approx(five.forgiveness, 1.0), "the 5-weight keeps today's timing windows")
	_check(seven.rated_length_in > five.rated_length_in and five.rated_length_in > dads.rated_length_in, "heavier rods are rated for bigger fish")


# --- Casting ---------------------------------------------------------------

## Five clean false casts under every rule set never put out more line than the
## rod carries, and a long rod carries more than a short one.
func _test_line_cap_every_rule_set() -> void:
	for path in RULES:
		var rules: CastRules = load(path).duplicate()
		var short_line := _line_after_false_casts(rules, _rod(1, 10.25), 5)
		var long_line := _line_after_false_casts(load(path).duplicate(), _rod(1, 16.5), 5)
		var none := _line_after_false_casts(load(path).duplicate(), null, 5)
		_check(short_line <= 10.25 + 0.001, "%s: a 10.25 m rod carries at most 10.25 m (%.2f)" % [rules.display_name, short_line])
		_check(long_line > short_line, "%s: a 16.5 m rod carries more line (%.2f vs %.2f)" % [rules.display_name, long_line, short_line])
		_check(long_line <= 16.5 + 0.001, "%s: and never more than its 16.5 m (%.2f)" % [rules.display_name, long_line])
		_check(none > 0.0, "%s: with no rod the rule set's own line applies (%.2f)" % [rules.display_name, none])
	var tiered: TieredCastRules = load(RULES[1]).duplicate()
	var five := _line_after_false_casts(tiered, _rod(1, 12.5), 5)
	_check(is_equal_approx(five, tiered.step_lengths[tiered.step_lengths.size() - 1]),
		"Count the false casts: a 12.5 m rod (the 5-weight) reaches today's Long step (%.2f)" % five)
	var dads := _line_after_false_casts(load(RULES[1]).duplicate(), _rod(1, 10.25), 5)
	_check(CastRules.distance_label(dads) == "Middle", "Count the false casts: Dad's 10.25 m rod tops out at Middle (%.2f)" % dads)


func _test_forgiveness_every_rule_set() -> void:
	for path in RULES:
		var base := CastModel.new(_tuning, 1, load(path).duplicate())
		var soft := CastModel.new(_tuning, 1, load(path).duplicate())
		soft.rod = _rod(1, 12.5, 1.3)
		var same := CastModel.new(_tuning, 1, load(path).duplicate())
		same.rod = _rod(1, 12.5, 1.0)
		for m in [base, soft, same]:
			m.update(0.0, true, false)  # hold the back cast so the windows are live
		var name: String = base.rules.display_name
		_check(is_equal_approx(soft.perfect_window(), base.perfect_window() * 1.3), "%s: forgiveness 1.3 widens the perfect window x1.3" % name)
		_check(is_equal_approx(soft.ok_window(), base.ok_window() * 1.3), "%s: and the okay window" % name)
		_check(is_equal_approx(same.perfect_window(), base.perfect_window()), "%s: forgiveness 1 changes nothing" % name)
		# A stroke just outside the plain perfect window is perfect on the soft rod.
		# (Find your tempo's first stroke only sets the beat, so set it first.)
		for m in [base, soft]:
			if m.rules is TempoCastRules:
				m.rules.beat = m.phase_ideal
		var late := base.phase_ideal + base.perfect_window() * 1.15
		var q_base: float = base.rules.score_stroke(base, late, "back")[0]
		var q_soft: float = soft.rules.score_stroke(soft, late, "back")[0]
		_check(q_base < 1.0 and q_soft >= 1.0, "%s: a slightly late stroke is perfect on a forgiving rod (%.2f vs %.2f)" % [name, q_base, q_soft])


func _test_overlap_forgiveness() -> void:
	var base := CastModel.new(_tuning, 1)
	var soft := CastModel.new(_tuning, 1)
	soft.rod = _rod(1, 12.5, 1.3)
	var overlap := _tuning.overlap_good_max * 1.2
	_check(base.overlap_quality(overlap) < 1.0 and soft.overlap_quality(overlap) >= 1.0, "a forgiving rod forgives a slightly long overlap")
	_check(soft.overlap_quality(_tuning.tailing_overlap) < 1.0, "but never a tailing loop")


# --- Fight -----------------------------------------------------------------

func _test_rod_load() -> void:
	var rod := _rod(1, 12.5, 1.0, 16.0)
	_check(is_equal_approx(FightModel.load_for(rod, 12.0), 1.0), "a fish under the rating loads the rod x1")
	_check(is_equal_approx(FightModel.load_for(rod, 16.0), 1.0), "a fish at the rating loads it x1")
	_check(is_equal_approx(FightModel.load_for(rod, 20.0), 1.5), "a fish 25%% over loads it x1.5 (%.2f)" % FightModel.load_for(rod, 20.0))
	_check(is_equal_approx(FightModel.load_for(null, 30.0), 1.0), "no rod loads nothing")


## Same fish, same pressure, same dice: on a rod it's too big for, the tippet
## goes sooner.
func _test_oversized_fish_snaps_sooner() -> void:
	var fair := _snap_time(1.0)
	var heavy := _snap_time(1.5)
	_check(heavy < fair, "a fish too big for the rod snaps the tippet sooner (%.2f s vs %.2f s)" % [heavy, fair])


func _snap_time(rod_load: float) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var f := FightModel.new(_redband, 6.25, -PI / 2.0, rng, rod_load)
	var t := 0.0
	while t < 30.0:
		t += 1.0 / 60.0
		if f.update(1.0 / 60.0, Vector2(0, -0.8)) == FightModel.Result.SNAPPED:
			return t
	return 30.0


# --- Helpers ---------------------------------------------------------------

## Line out after a clean back cast and `n` clean false casts.
func _line_after_false_casts(rules: CastRules, rod: FlyRod, n: int) -> float:
	var m := CastModel.new(_tuning, 1, rules)
	m.rod = rod
	var now := 0.0
	m.update(now, true, false)
	for i in n:
		now += m.phase_ideal
		m.update(now, true, true)
		now += 0.05
		m.update(now, false, true)
		now += m.phase_ideal
		m.update(now, true, true)
		now += 0.05
		m.update(now, true, false)
	return m.line_out


func _rod(types: int, max_line := 12.5, forgiveness := 1.0, rated := 20.0) -> FlyRod:
	var r := FlyRod.new()
	r.fly_types = types
	r.max_line_m = max_line
	r.forgiveness = forgiveness
	r.rated_length_in = rated
	return r


func _fly(type: FlyPattern.Type) -> FlyPattern:
	var f := FlyPattern.new()
	f.fly_type = type
	return f


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
