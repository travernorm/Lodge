extends SceneTree
## Headless tests for WorldScale, the metres-to-pixels conversion (REQ-0001).
##   godot --headless --path . --script res://tests/units_test.gd

var _failures := 0


func _initialize() -> void:
	_test_scale()
	_test_round_trip()
	_test_screen_size()
	if _failures == 0:
		print("Units tests passed.")
		quit(0)
	else:
		printerr("%d units test(s) failed." % _failures)
		quit(1)


func _test_scale() -> void:
	_check(is_equal_approx(WorldScale.PX_PER_M, 8.0), "8 px per metre, as approved in REQ-0001")
	_check(is_equal_approx(WorldScale.to_px(1.0), 8.0), "1 m is 8 px")
	_check(is_equal_approx(WorldScale.to_m(48.0), 6.0), "48 px (today's Short limit) is 6 m")


func _test_round_trip() -> void:
	for x in [0.0, 0.25, 3.0, 14.75, 118.0, -5.5]:
		_check(is_equal_approx(WorldScale.to_px(WorldScale.to_m(x)), x), "px -> m -> px keeps %s" % x)
		_check(is_equal_approx(WorldScale.to_m(WorldScale.to_px(x)), x), "m -> px -> m keeps %s" % x)
	var v := Vector2(160, 110)
	_check(WorldScale.vec_to_px(WorldScale.vec_to_m(v)).is_equal_approx(v), "vectors round-trip")


func _test_screen_size() -> void:
	var screen := WorldScale.vec_to_m(Vector2(320, 200))
	_check(screen.is_equal_approx(Vector2(40, 25)), "one screen is 40 m by 25 m (got %s)" % screen)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
