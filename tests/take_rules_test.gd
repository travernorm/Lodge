extends SceneTree
## Headless tests for the bite rules (DriftPastRules): the odds of a pass, the
## fly's slip against the water, and a fish following the fly through its window.
##   godot --headless --path . --script res://tests/take_rules_test.gd

const DT := 1.0 / 60.0

var _failures := 0
var _rng := RandomNumberGenerator.new()
var _redband: FishSpecies = load("res://data/fish/redband.tres")
var _drift_past: DriftPastRules = load("res://data/take_rules/drift_past.tres")


func _initialize() -> void:
	_rng.seed = 11
	_test_slip_is_zero_in_the_current()
	_test_drag_shows_as_slip()
	_test_early_mend_shows_as_slip()
	_test_drift_past_odds()
	_test_one_roll_per_pass()
	_test_landing_on_the_fish_counts_as_a_pass()
	_test_a_new_pass_rolls_again()
	_test_fly_that_misses_the_window_never_rolls()
	_test_pass_remembers_the_worst_slip()
	_test_mending_raises_the_odds_of_a_pass()
	_test_pass_rate_matches_the_odds()
	if _failures == 0:
		print("Take rules tests passed.")
		quit(0)
	else:
		printerr("%d take rules test(s) failed." % _failures)
		quit(1)


# --- Slip ------------------------------------------------------------------

func _test_slip_is_zero_in_the_current() -> void:
	var d := DriftModel.new()
	d.start(Vector2(20, 16.25), Vector2(20, 11.25))
	_run_drift(d, 0.5, func(_p: Vector2): return Vector2(2.5, 0))
	_check(d.slip < 0.05, "slip: a fly riding even current has no slip (%.2f m/s)" % d.slip)


func _test_drag_shows_as_slip() -> void:
	var d := DriftModel.new()
	d.start(Vector2(20, 16.25), Vector2(20, 8.75))
	_run_drift(d, 2.0, _drag_flow)
	_check(d.slip > _drift_past.slip_full, "slip: a dragging fly slips past the clean limit (%.2f m/s, drag %.2f)" % [d.slip, d.drag])


func _test_early_mend_shows_as_slip() -> void:
	var d := DriftModel.new()
	d.start(Vector2(20, 16.25), Vector2(20, 8.75))
	d.mend()
	_run_drift(d, 0.15, func(_p: Vector2): return Vector2(1.25, 0))
	_check(d.slip > _drift_past.slip_free, "slip: the jolt of an early mend shows as slip (%.2f m/s)" % d.slip)


# --- Odds ------------------------------------------------------------------

func _test_drift_past_odds() -> void:
	var f := Fish.new(_redband, _rng)
	var base := _redband.bite_chance
	var near := f.lie + Vector2(-1.5, 0)
	var far := f.lie + Vector2(-10, 0)
	var best: float = _drift_past.pass_odds(f, near, "Delicate", 0.0).chance
	_check(is_equal_approx(best, base), "odds: delicate landing near it and no drag gets the full chance (%.2f)" % best)
	var fair: float = _drift_past.pass_odds(f, near, "Fair", 0.0).chance
	var splashy: float = _drift_past.pass_odds(f, near, "Splashy", 0.0).chance
	_check(fair < best and splashy < fair, "odds: fair, then splashy, earn less of the landing share")
	_check(is_equal_approx(splashy, base * 2.0 / 3.0), "odds: a splashy landing isn't punished, it just misses the bonus (%.2f)" % splashy)
	var far_delicate: float = _drift_past.pass_odds(f, far, "Delicate", 0.0).chance
	var far_splashy: float = _drift_past.pass_odds(f, far, "Splashy", 0.0).chance
	_check(is_equal_approx(far_delicate, far_splashy), "odds: a landing far upstream doesn't count either way")
	var dragged: float = _drift_past.pass_odds(f, near, "Delicate", 2.0).chance
	_check(is_equal_approx(dragged, base * 2.0 / 3.0), "odds: a dragging fly loses the drift share (%.2f)" % dragged)
	var some: float = _drift_past.pass_odds(f, near, "Delicate", 0.55).chance
	_check(some > dragged and some < best, "odds: a little drag loses part of it (%.2f)" % some)
	var worst: float = _drift_past.pass_odds(f, far, "Splashy", 2.0).chance
	_check(is_equal_approx(worst, base / 3.0), "odds: just coming through its lane still gets a third (%.2f)" % worst)
	var text: String = _drift_past.pass_odds(f, near, "Delicate", 0.0).text
	_check(text == "(Lane 20 + Delicate 20 + No drag 20) × Any fly 1 = 60%", "odds: spelled out on screen (%s)" % text)


# --- Passes ----------------------------------------------------------------

## A fly drifting in a straight line from 3 m upstream to 3 m past the fish.
func _test_one_roll_per_pass() -> void:
	var f := Fish.new(_redband, _rng)
	var rolls := []
	var x := -3.0
	while x <= 3.0:
		if f.watch_pass(f.lie + Vector2(x, 0.3), 0.0, 1.0, DT):
			rolls.append(x)
		x += 0.05
	_check(rolls.size() == 1, "pass: one roll per pass (%d)" % rolls.size())
	if rolls.size() == 1:
		_check(rolls[0] > 0.0 and rolls[0] < 0.2, "pass: it rolls as the fly passes its nose (at %.2f m)" % rolls[0])


func _test_landing_on_the_fish_counts_as_a_pass() -> void:
	var f := Fish.new(_redband, _rng)
	var rolled_at := -1
	for i in 30:
		if f.watch_pass(f.lie + Vector2(0.05 * i, 0), 0.0, 1.0, DT):
			rolled_at = i
			break
	_check(rolled_at >= 0 and rolled_at <= 3, "pass: a fly landing on the fish rolls right away (frame %d)" % rolled_at)


func _test_a_new_pass_rolls_again() -> void:
	var f := Fish.new(_redband, _rng)
	var rolls := 0
	for lap in 2:  # through the window, out, and back through (an eddy)
		var x := -2.0
		while x <= 2.0:
			if f.watch_pass(f.lie + Vector2(x, 0), 0.0, 1.0, DT):
				rolls += 1
			x += 0.05
	_check(rolls == 2, "pass: coming back through the window is a new pass (%d rolls)" % rolls)
	f.reset_pass()
	var stalled := 0
	for i in roundi(1.5 / DT):  # a fly sitting still beside it
		if f.watch_pass(f.lie + Vector2(0.5, 0), 0.0, 1.0, DT):
			stalled += 1
	_check(stalled == 1, "pass: a fly stalled in the window gets one roll after a second (%d)" % stalled)


func _test_fly_that_misses_the_window_never_rolls() -> void:
	var f := Fish.new(_redband, _rng)
	var x := -3.0
	var rolled := false
	while x <= 3.0:
		rolled = rolled or f.watch_pass(f.lie + Vector2(x, 1.2), 0.0, 1.0, DT)
		x += 0.05
	_check(not rolled, "pass: a fly 1.2 m off its lane never gets a roll")


func _test_pass_remembers_the_worst_slip() -> void:
	var f := Fish.new(_redband, _rng)
	var x := -1.0
	while x <= 1.0:
		var slip := 1.5 if x < -0.5 else 0.0  # skating as it came in, clean after
		if f.watch_pass(f.lie + Vector2(x, 0), slip, 1.0, DT):
			break
		x += 0.05
	_check(is_equal_approx(f.pass_worst_slip, 1.5), "pass: drag anywhere in the pass counts (%.2f)" % f.pass_worst_slip)


## The same drag setup as fishing_test's mend test, with a fish downstream of the
## fly in the slow water. Mended, the fly reaches it clean and gets the full
## odds. Unmended, the drag drags it out of the fish's lane, or gets there late
## and dragging: either way, worse odds.
func _test_mending_raises_the_odds_of_a_pass() -> void:
	var unmended := maxf(_pass_chance(false), 0.0)
	var mended := _pass_chance(true)
	_check(is_equal_approx(mended, _redband.bite_chance) and mended > unmended,
		"pass: mending keeps the fly clean so the fish gets better odds (%.2f vs %.2f unmended)" % [mended, unmended])


func _test_pass_rate_matches_the_odds() -> void:
	var f := Fish.new(_redband, _rng)
	var chance: float = _drift_past.pass_odds(f, f.lie, "Fair", 0.0).chance
	var bites := 0
	var passes := 2000
	for i in passes:
		f.roll(chance, _drift_past.rise_delay())
		if f.state == Fish.State.WAITING:
			bites += 1
		f.state = Fish.State.HOLDING
	var rate := float(bites) / passes
	_check(absf(rate - chance) < 0.04, "pass: bite rate over %d passes is %.2f (expected %.2f)" % [passes, rate, chance])


# --- Helpers ---------------------------------------------------------------

func _drag_flow(p: Vector2) -> Vector2:
	return Vector2(6.25 if p.y > 10.625 else 1.5, 0)


## Drifts a fly in the drag setup toward a fish 2.5 m downstream and returns the
## pass odds the fish works out, or -1 if the fly never reached it.
func _pass_chance(mend: bool) -> float:
	var d := DriftModel.new()
	d.start(Vector2(20, 16.25), Vector2(20, 8.75))
	var f := Fish.new(_redband, _rng)
	f.lie = Vector2(22.5, 8.75)
	for i in 240:
		d.update(DT, _drag_flow)
		if mend and d.bow() > 1.0:
			d.mend()
		if f.watch_pass(d.fly, d.slip, _drift_past.window(), DT):
			return _drift_past.pass_odds(f, Vector2(20, 8.75), "Delicate", f.pass_worst_slip).chance
	return -1.0


func _run_drift(d: DriftModel, seconds: float, flow: Callable) -> void:
	for i in roundi(seconds / DT):
		d.update(DT, flow)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
