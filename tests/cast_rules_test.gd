extends SceneTree
## Headless tests for the swappable cast rule sets (scripts/casting/cast_rules.gd
## and scripts/casting/rules/). Each cast is played frame by frame at 60 fps.
##   godot --headless --path . --script res://tests/cast_rules_test.gd

const DT := 1.0 / 60.0
const OVERLAP := 0.08
const IDEAL := -1.0
const CHASSIS := [
	"res://data/cast_rules/classic.tres",
	"res://data/cast_rules/count_false_casts.tres",
	"res://data/cast_rules/find_your_tempo.tres",
]

var _t := 0.0
var _failures := 0
var _messages: Array[String] = []


func _initialize() -> void:
	_test_every_chassis_loads()
	_test_every_chassis_short_and_long()
	_test_tiered_steps()
	_test_tiered_sloppy_does_not_climb()
	_test_tiered_beat_grows_per_step()
	_test_tempo_any_steady_tempo()
	_test_tempo_broken_rhythm()
	_test_tempo_rushed_first_stroke()
	_test_stroke_log()
	if _failures == 0:
		print("Cast rules tests passed.")
		quit(0)
	else:
		printerr("%d cast rules test(s) failed." % _failures)
		quit(1)


# --- Tests -----------------------------------------------------------------

func _test_every_chassis_loads() -> void:
	for path in CHASSIS:
		var r := load(path) as CastRules
		_check(r != null and r.display_name != "" and r.description != "", "%s loads with a name and description" % path.get_file())


func _test_every_chassis_short_and_long() -> void:
	for path in CHASSIS:
		var m := _model(path)
		_play(m, 0)
		_check(CastRules.distance_label(m.last_reach) == "Short",
			"%s: no false casts lands Short (%.0f px)" % [m.rules.display_name, m.last_reach])
		m = _model(path)
		_play(m, 5)
		_check(CastRules.distance_label(m.last_reach) == "Long",
			"%s: five clean false casts land Long (%.0f px)" % [m.rules.display_name, m.last_reach])
		_check(m.presentation == "Delicate", "%s: clean cast is delicate, got %s" % [m.rules.display_name, m.presentation])


func _test_tiered_steps() -> void:
	var expected := ["Short", "Middle", "Long", "Long"]
	for n in expected.size():
		var m := _model(CHASSIS[1])
		_play(m, n)
		var got := CastRules.distance_label(m.last_reach)
		_check(got == expected[n], "tiered: %d false cast(s) -> %s, got %s (%.0f px)" % [n, expected[n], got, m.last_reach])


func _test_tiered_sloppy_does_not_climb() -> void:
	var m := _model(CHASSIS[1])
	# One false cast with both strokes badly rushed.
	_play(m, 1, [0.15, 0.15, IDEAL, IDEAL])
	_check(_messages.any(func(s: String): return s.begins_with("Sloppy")), "tiered: rushed false cast is called sloppy")
	_check(CastRules.distance_label(m.last_reach) == "Short", "tiered: sloppy false cast stays Short (%.0f px)" % m.last_reach)


func _test_tiered_beat_grows_per_step() -> void:
	var m := _model(CHASSIS[1])
	var r := m.rules as TieredCastRules
	_play(m, 3)
	var ideals: Array = []
	for s in m.strokes:
		if s.kind != "overlap":
			ideals.append(snappedf(s.ideal, 0.001))
	var short := r.tempo
	var middle := r.tempo + r.tempo_per_step
	var long := r.tempo + 2.0 * r.tempo_per_step
	var expected := [short, short, middle, middle, long, long, long, long]
	var ok := ideals.size() == expected.size()
	for i in mini(ideals.size(), expected.size()):
		ok = ok and is_equal_approx(ideals[i], expected[i])
	_check(ok, "tiered: beat stretches with each step up, got %s" % [ideals])
	_check(m.presentation == "Delicate", "tiered: following the stretched beat is still delicate, got %s" % m.presentation)

	# A sloppy false cast doesn't climb, so the beat doesn't stretch either.
	m = _model(CHASSIS[1])
	_play(m, 1, [0.15, 0.15, IDEAL, IDEAL])
	_check(is_equal_approx(m.strokes[-1].ideal, r.tempo), "tiered: no step up, no slower beat (%.2f s)" % m.strokes[-1].ideal)


func _test_tempo_any_steady_tempo() -> void:
	for tempo in [0.3, 0.6]:
		var m := _model(CHASSIS[2])
		_play(m, 3, _steady(tempo, 3))
		_check(m.presentation == "Delicate", "tempo: steady %.1f s beat is delicate, got %s (q=%.2f)" % [tempo, m.presentation, m.last_cast_quality])
		_check(_messages.any(func(s: String): return s.begins_with("Tempo set")), "tempo: first stroke sets the beat at %.1f s" % tempo)


func _test_tempo_broken_rhythm() -> void:
	var m := _model(CHASSIS[2])
	_play(m, 3, [0.4, 0.2, 0.65, 0.25, 0.7, 0.2, 0.6, 0.25])
	_check(m.presentation != "Delicate", "tempo: broken rhythm is not delicate, got %s" % m.presentation)
	var steady := _model(CHASSIS[2])
	_play(steady, 3, _steady(0.4, 3))
	_check(m.last_reach < steady.last_reach - 10.0, "tempo: broken rhythm falls short (%.0f vs %.0f px)" % [m.last_reach, steady.last_reach])


func _test_tempo_rushed_first_stroke() -> void:
	var m := _model(CHASSIS[2])
	_play(m, 0, [0.15, 0.25])
	_check(m.strokes[0].quality < 1.0, "tempo: a 0.15 s first back cast is penalised (q=%.2f)" % m.strokes[0].quality)
	_check(_messages.any(func(s: String): return s.begins_with("Rushed the first")), "tempo: tells the player it was rushed")


func _test_stroke_log() -> void:
	var m := _model(CHASSIS[0])
	_play(m, 1)
	var kinds: Array = m.strokes.map(func(s): return s.kind)
	_check(kinds == ["back", "overlap", "forward", "overlap", "back", "overlap", "forward"],
		"stroke log records every stroke and overlap, got %s" % [kinds])


# --- Helpers ---------------------------------------------------------------

func _model(path: String) -> CastModel:
	_t = 0.0
	_messages.clear()
	# Duplicate so a rule set's per-cast state (beat, step) never leaks between tests.
	var rules := (load(path) as CastRules).duplicate()
	var m := CastModel.new(CastTuning.new(), 1234, rules)
	m.feedback.connect(func(text: String, _q: float): _messages.append(text))
	return m


func _steady(seconds: float, false_casts: int) -> Array:
	var out := []
	for i in (false_casts + 1) * 2:
		out.append(seconds)
	return out


## Plays a whole cast: `false_casts` full back/forward cycles, then a delivery.
## `durations` gives each stroke's hold in seconds (IDEAL = the meter's ideal).
func _play(m: CastModel, false_casts: int, durations: Array = []) -> void:
	var strokes := (false_casts + 1) * 2
	for i in strokes:
		var back := i % 2 == 0
		var d: float = durations[i] if i < durations.size() else IDEAL
		# One frame alone on the new bumper enters the stroke, then hold the rest.
		_hold(m, DT, back, not back)
		var target := m.phase_ideal if d == IDEAL else d
		_hold(m, target - (_t - m.phase_start), back, not back)
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
