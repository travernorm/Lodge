extends SceneTree
## Headless tests for the bumper casting rhythm (scripts/casting/cast_model.gd).
##   godot --headless --path . --script res://tests/cast_test.gd
## Inputs are fed frame by frame at 60 fps, the way a player would press them.

const DT := 1.0 / 60.0
const OVERLAP := 0.08

var _t := 0.0
var _failures := 0
var _messages: Array[String] = []


func _initialize() -> void:
	_test_clean_cast_lands_delicately()
	_test_false_casts_add_line()
	_test_letting_go_of_r_collapses()
	_test_holding_r_too_long_ticks_grass()
	_test_long_overlap_throws_tailing_loop()
	_test_early_strokes_fall_short()
	_test_aim_swings_cast()
	_test_pick_up_and_recast()
	if _failures == 0:
		print("Cast tests passed.")
		quit(0)
	else:
		printerr("%d cast test(s) failed." % _failures)
		quit(1)


# --- Tests -----------------------------------------------------------------

func _test_clean_cast_lands_delicately() -> void:
	var m := _model()
	_back(m)
	_overlap(m)
	_forward(m)
	_release(m)
	_check(m.state == CastModel.State.FLIGHT, "clean cast: fly is in the air after releasing L")
	_wait_landing(m)
	_check(m.state == CastModel.State.LANDED, "clean cast: fly lands")
	_check(m.presentation == "Delicate", "clean cast: delicate, got %s (q=%.2f)" % [m.presentation, m.last_cast_quality])
	_check(absf(m.landing_offset.length() - m.tuning.line_start) < 1.0,
		"clean cast: reaches full line (%.1f vs %.1f)" % [m.landing_offset.length(), m.tuning.line_start])


func _test_false_casts_add_line() -> void:
	var m := _model()
	_back(m)
	_overlap(m)
	_forward(m)
	for i in 3:
		_overlap(m, true)  # forward into back
		_back_rest(m)
		_overlap(m)
		_forward(m)
	_release(m)
	_wait_landing(m)
	var expected := m.tuning.line_start + 3.0 * m.tuning.line_gain_max
	_check(m.false_casts == 3, "false casts: counted 3, got %d" % m.false_casts)
	_check(is_equal_approx(m.line_out, expected), "false casts: line %.1f, expected %.1f" % [m.line_out, expected])
	_check(m.presentation == "Delicate", "false casts: still delicate, got %s" % m.presentation)
	_check(m.landing_offset.length() > m.tuning.line_start + 40.0, "false casts: cast lands farther out")


func _test_letting_go_of_r_collapses() -> void:
	var m := _model()
	_hold(m, 0.2, true, false)
	_hold(m, 0.2, false, false)
	_check(m.state == CastModel.State.IDLE, "collapse: back to idle")
	_check(_last_message().contains("Overlap"), "collapse: tells the player to overlap, got '%s'" % _last_message())


func _test_holding_r_too_long_ticks_grass() -> void:
	var m := _model()
	var ideal := m.tuning.base_stroke_time + m.tuning.line_start * m.tuning.stroke_time_per_px
	_hold(m, ideal + m.tuning.drop_time + 0.15, true, false)
	_check(m.state == CastModel.State.IDLE, "grass: cast collapses")
	_check(_last_message().contains("grass"), "grass: message mentions grass, got '%s'" % _last_message())


func _test_long_overlap_throws_tailing_loop() -> void:
	var m := _model()
	_back(m)
	_hold(m, m.tuning.tailing_overlap + 0.02, true, true)
	_hold(m, DT, false, true)
	_check(_messages.any(func(s): return s.contains("Tailing")), "tailing: warned about a tailing loop")
	_forward_rest(m)
	_release(m)
	_wait_landing(m)
	_check(m.presentation != "Delicate", "tailing: not a delicate landing")


func _test_early_strokes_fall_short() -> void:
	var m := _model()
	var ideal := m.tuning.base_stroke_time + m.tuning.line_start * m.tuning.stroke_time_per_px
	_hold(m, ideal * 0.4, true, false)
	_hold(m, OVERLAP, true, true)
	_hold(m, ideal * 0.4, false, true)
	_release(m)
	_wait_landing(m)
	_check(m.presentation == "Splashy", "early: splashy, got %s (q=%.2f)" % [m.presentation, m.last_cast_quality])
	_check(m.landing_offset.length() < m.tuning.line_start * 0.85, "early: falls short")
	_check(_messages.any(func(s): return s.contains("Early")), "early: says it was early")


func _test_aim_swings_cast() -> void:
	var m := _model()
	m.aim = 1.0
	_back(m)
	_overlap(m)
	_forward(m)
	_release(m)
	_check(m.landing_offset.x > m.tuning.line_start * 0.5, "aim: cast swings right (x=%.1f)" % m.landing_offset.x)
	_check(m.landing_offset.y < 0.0, "aim: still lands across the river")


func _test_pick_up_and_recast() -> void:
	var m := _model()
	_back(m)
	_overlap(m)
	_forward(m)
	_release(m)
	_wait_landing(m)
	m.line_out = 70.0  # the controller sets this from how far the fly drifted
	_hold(m, DT, true, false)
	_check(m.state == CastModel.State.BACK, "pick-up: R lifts the line into a back cast")
	_check(is_equal_approx(m.line_out, 70.0), "pick-up: keeps the line that was out")
	_check(m.phase_ideal > m.tuning.base_stroke_time + 24.0 * m.tuning.stroke_time_per_px,
		"pick-up: longer line needs a longer stroke")


# --- Helpers ---------------------------------------------------------------

func _model() -> CastModel:
	_t = 0.0
	_messages.clear()
	var m := CastModel.new(CastTuning.new(), 1234)
	m.feedback.connect(func(text: String, _q: float): _messages.append(text))
	return m


func _hold(m: CastModel, seconds: float, r: bool, l: bool) -> void:
	var steps := maxi(1, roundi(seconds / DT))
	for i in steps:
		_t += DT
		m.update(_t, r, l)


## Hold R alone for a whole, perfectly timed back cast (starting it if needed).
func _back(m: CastModel) -> void:
	_back_rest(m)


## Let go of L (after an overlap) and hold R alone until the back cast's ideal moment.
func _back_rest(m: CastModel) -> void:
	_hold(m, DT, true, false)
	_hold(m, m.phase_ideal - (_t - m.phase_start), true, false)


func _forward(m: CastModel) -> void:
	_forward_rest(m)


## Let go of R (after an overlap) and hold L alone until the forward cast's ideal moment.
func _forward_rest(m: CastModel) -> void:
	_hold(m, DT, false, true)
	_hold(m, m.phase_ideal - (_t - m.phase_start), false, true)


func _overlap(m: CastModel, _into_back := false) -> void:
	_hold(m, OVERLAP, true, true)


func _release(m: CastModel) -> void:
	_hold(m, DT, false, false)


func _wait_landing(m: CastModel) -> void:
	_hold(m, m.tuning.flight_time + 0.05, false, false)


func _last_message() -> String:
	return _messages.back() if not _messages.is_empty() else ""


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
