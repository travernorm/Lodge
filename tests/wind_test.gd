extends SceneTree
## Headless tests for the wind over the land (REQ-0012): stronger weather blows
## harder, the wind eases in instead of snapping, gusts roll across, and the
## same seed gives the same wind.
##   godot --headless --path . --script res://tests/wind_test.gd

const TABLE := [0.12, 0.22, 0.45, 0.3, 1.0]

var _failures := 0
var _table := PackedFloat32Array(TABLE)


func _initialize() -> void:
	_test_strength_by_weather()
	_test_eases_in()
	_test_gusts_roll()
	_test_seeded()
	_test_calm_and_storm_leans()
	if _failures == 0:
		print("Wind tests passed.")
		quit(0)
	else:
		printerr("%d wind test(s) failed." % _failures)
		quit(1)


func _day(w: Calendar.Weather, intensity: float) -> Conditions:
	var c := Conditions.new()
	c.weather = w
	c.intensity = intensity
	return c


## Acceptance: Sunny is near calm, Storm at intensity 1 is the strongest, Rain in between.
func _test_strength_by_weather() -> void:
	var sunny := Wind.strength_for(_day(Calendar.Weather.SUNNY, 0.5), _table)
	var rain := Wind.strength_for(_day(Calendar.Weather.RAIN, 0.5), _table)
	var storm := Wind.strength_for(_day(Calendar.Weather.STORM, 0.5), _table)
	_check(sunny < 0.15, "strength: a sunny day is near calm (%.2f)" % sunny)
	_check(sunny < rain and rain < storm, "strength: sunny < rain < storm (%.2f %.2f %.2f)" % [sunny, rain, storm])
	var most := 0.0
	for w in Calendar.Weather.size():
		for k in 5:
			most = maxf(most, Wind.strength_for(_day(w as Calendar.Weather, k / 4.0), _table))
	_check(is_equal_approx(Wind.strength_for(_day(Calendar.Weather.STORM, 1.0), _table), most),
		"strength: a full storm is the strongest wind")
	_check(Wind.strength_for(_day(Calendar.Weather.RAIN, 0.0), _table) < rain,
		"strength: a drizzle blows less than a downpour")
	_check(Wind.strength_for(null, _table) == 0.0, "strength: no day, no wind")


func _test_eases_in() -> void:
	var w := Wind.new()
	w.ease_seconds = 3.0
	w.blow_for(_day(Calendar.Weather.STORM, 1.0), _table)
	w.step(1.0)
	_check(w.strength > 0.2 and w.strength < 0.5, "ease: a storm builds over seconds (%.2f after 1 s)" % w.strength)
	w.step(3.0)
	_check(is_equal_approx(w.strength, w.target), "ease: it reaches full strength")
	w.blow_for(_day(Calendar.Weather.SUNNY, 0.0), _table)
	w.step(0.5)
	_check(w.strength > w.target, "ease: and dies away, not all at once")


func _test_gusts_roll() -> void:
	var w := _storm(Wind.new(_rng(3)))
	var p := Vector2(20, 10)
	var low := INF
	var high := -INF
	for i in 120:
		w.step(1.0 / 30.0)
		var l := w.lean_at(p)
		low = minf(low, l)
		high = maxf(high, l)
	_check(high - low > 0.3, "gusts: the lean rises and falls as gusts pass (%.2f to %.2f)" % [low, high])
	var a := w.lean_at(Vector2.ZERO)
	var b := w.lean_at(w.direction * w.gust_size_m * 0.5)
	_check(not is_equal_approx(a, b), "gusts: places half a gust apart lean differently")


func _test_seeded() -> void:
	var a := _storm(Wind.new(_rng(11)))
	var b := _storm(Wind.new(_rng(11)))
	var c := _storm(Wind.new(_rng(12)))
	a.step(2.0)
	b.step(2.0)
	c.step(2.0)
	var p := Vector2(13, 7)
	_check(a.direction == b.direction and is_equal_approx(a.lean_at(p), b.lean_at(p)), "seed: the same seed gives the same wind")
	_check(a.direction != c.direction or not is_equal_approx(a.lean_at(p), c.lean_at(p)), "seed: another seed gives another wind")
	_check(absf(a.direction.x) > 0.9, "seed: the wind blows mostly across the screen")


func _test_calm_and_storm_leans() -> void:
	var calm := Wind.new(_rng(5))
	calm.blow_for(_day(Calendar.Weather.SUNNY, 0.5), _table)
	calm.strength = calm.target
	var storm := _storm(Wind.new(_rng(5)))
	var calm_most := 0.0
	var storm_sum := 0.0
	var moved := false
	var first := calm.lean_at(Vector2(4, 4))
	for i in 300:
		calm.step(1.0 / 30.0)
		storm.step(1.0 / 30.0)
		var p := Vector2(i * 0.3, 4)
		calm_most = maxf(calm_most, absf(calm.lean_at(p)))
		storm_sum += storm.lean_at(p)
		moved = moved or not is_equal_approx(calm.lean_at(Vector2(4, 4)), first)
	_check(calm_most < 0.25, "lean: a sunny day only breathes (most %.2f)" % calm_most)
	_check(moved, "lean: but it isn't perfectly still")
	_check(storm_sum / 300.0 > 0.5, "lean: a storm bends the grass well over (mean %.2f)" % (storm_sum / 300.0))


func _storm(w: Wind) -> Wind:
	w.blow_for(_day(Calendar.Weather.STORM, 1.0), _table)
	w.strength = w.target
	return w


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
