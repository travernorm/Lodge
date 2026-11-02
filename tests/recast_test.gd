extends SceneTree
## Headless tests for casting again after the fly has landed: every new cast,
## including a pick-up straight off the water, starts back at Short, so
## Middle and Long always take false casts.
##   godot --headless --path . --script res://tests/recast_test.gd

const DT := 1.0 / 60.0
const OVERLAP := 0.08
const CHASSIS := [
	"res://data/cast_rules/classic.tres",
	"res://data/cast_rules/count_false_casts.tres",
	"res://data/cast_rules/find_your_tempo.tres",
]

var _t := 0.0
var _failures := 0


func _initialize() -> void:
	_test_recast_after_long_starts_short()
	_test_tiered_recast_climbs_again()
	if _failures == 0:
		print("Recast tests passed.")
		quit(0)
	else:
		printerr("%d recast test(s) failed." % _failures)
		quit(1)


# --- Tests -----------------------------------------------------------------

func _test_recast_after_long_starts_short() -> void:
	for path in CHASSIS:
		var m := _model(path)
		_play(m, 5)
		_check(CastRules.distance_label(m.last_reach) == "Long",
			"%s: first cast reaches Long (%.1f m)" % [m.rules.display_name, m.last_reach])
		# Pick the line straight up off the water and deliver with no false casts.
		_play(m, 0)
		_check(CastRules.distance_label(m.last_reach) == "Short",
			"%s: recast with no false casts lands Short again (%.1f m)" % [m.rules.display_name, m.last_reach])


func _test_tiered_recast_climbs_again() -> void:
	var m := _model(CHASSIS[1])
	_play(m, 2)
	_check(CastRules.distance_label(m.last_reach) == "Long", "tiered: two false casts reach Long (%.1f m)" % m.last_reach)
	_play(m, 1)
	_check(CastRules.distance_label(m.last_reach) == "Middle",
		"tiered: recast with one false cast reaches Middle, not Long (%.1f m)" % m.last_reach)


# --- Helpers ---------------------------------------------------------------

func _model(path: String) -> CastModel:
	_t = 0.0
	var rules := (load(path) as CastRules).duplicate()
	return CastModel.new(CastTuning.new(), 1234, rules)


## Plays a whole cast with every stroke held to its ideal, then waits for it to land.
func _play(m: CastModel, false_casts: int) -> void:
	var strokes := (false_casts + 1) * 2
	for i in strokes:
		var back := i % 2 == 0
		_hold(m, DT, back, not back)
		_hold(m, m.phase_ideal - (_t - m.phase_start), back, not back)
		if i < strokes - 1:
			_hold(m, OVERLAP, true, true)
	_hold(m, DT, false, false)
	_hold(m, m.tuning.flight_time + 0.05, false, false)
	_check(m.state == CastModel.State.LANDED, "%s: cast with %d false cast(s) lands" % [m.rules.display_name, false_casts])


func _hold(m: CastModel, seconds: float, r: bool, l: bool) -> void:
	var steps := maxi(1, roundi(seconds / DT))
	for i in steps:
		_t += DT
		m.update(_t, r, l)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
