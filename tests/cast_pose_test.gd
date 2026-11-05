extends SceneTree
## The cast look versions (CastLook, CastPose, AnglerView's rod and arm): the
## rod sweeps from the forward stop to the back stop and back in time with the
## strokes, bends against the way it moves, version B snaps to its fixed angles,
## and the angler draws the cutout forearm on its Bone2D.
##   godot --headless --path . --script res://tests/cast_pose_test.gd

const S := CastModel.State

var _failures := 0
var _look: CastLook = preload("res://data/cast_looks/default.tres")


func _initialize() -> void:
	_test_sweep()
	_test_late_drift_and_follow_through()
	_test_bend()
	_test_snap()
	_test_on_screen()
	_test_arm_rig()
	if _failures == 0:
		print("Cast pose tests passed.")
		quit(0)
	else:
		printerr("%d cast pose test(s) failed." % _failures)
		quit(1)


func _test_sweep() -> void:
	_check(is_equal_approx(CastPose.tilt(_look, S.BACK, 0.0, 0.0), _look.forward_stop_deg), "the back stroke starts at the forward stop")
	_check(is_equal_approx(CastPose.tilt(_look, S.BACK, 1.0, 0.0), _look.back_stop_deg), "the back stroke ends at the back stop")
	_check(is_equal_approx(CastPose.tilt(_look, S.FORWARD, 0.0, 0.0), _look.back_stop_deg), "the forward stroke starts at the back stop")
	_check(is_equal_approx(CastPose.tilt(_look, S.FORWARD, 1.0, 0.0), _look.forward_stop_deg), "the forward stroke ends at the forward stop")
	var prev := INF
	var steady := true
	for i in 11:
		var deg := CastPose.tilt(_look, S.BACK, i / 10.0, 0.0)
		steady = steady and deg <= prev
		prev = deg
	_check(steady, "the back stroke only ever moves back")
	_check(CastPose.tilt(_look, S.IDLE, 0.5, 0.0) == CastPose.NONE, "reeled in, the cast doesn't pose the rod")
	_check(CastPose.tilt(_look, S.LANDED, 0.5, 0.0) == CastPose.NONE, "on the water, the cast doesn't pose the rod")


func _test_late_drift_and_follow_through() -> void:
	_check(CastPose.tilt(_look, S.BACK, 1.5, 0.0) < _look.back_stop_deg, "a back cast held late drifts further back")
	_check(is_equal_approx(CastPose.tilt(_look, S.BACK, 5.0, 0.0), _look.back_stop_deg - _look.late_drift_deg), "the drift stops at late_drift_deg")
	_check(is_equal_approx(CastPose.tilt(_look, S.FLIGHT, 0.0, 1.0), _look.follow_through_deg), "the rod follows through as the fly lands")


func _test_bend() -> void:
	_check(is_zero_approx(CastPose.bend(_look, S.FORWARD, 0.0)), "no bend as the stroke starts")
	_check(is_equal_approx(CastPose.bend(_look, S.FORWARD, 0.5), _look.max_bend_deg), "most bend mid-stroke")
	_check(CastPose.bend(_look, S.BACK, 0.5) < 0.0, "the back stroke bends the other way")
	_check(is_zero_approx(CastPose.bend(_look, S.FLIGHT, 0.5)), "no bend once the fly is out")


func _test_snap() -> void:
	for p in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]:
		var deg := CastPose.snapped(_look, CastPose.tilt(_look, S.FORWARD, p, 0.0))
		_check(deg in _look.snap_angles_deg, "version B sits on a fixed angle (%.1f at %.1f)" % [deg, p])
	_check(CastPose.snapped(_look, CastPose.NONE) == CastPose.NONE, "nothing to snap with no pose")


func _test_on_screen() -> void:
	var up := Vector2.UP
	var right := Vector2.RIGHT
	var fwd := CastPose.on_screen(_look, 90.0, up, right)
	_check(fwd.is_equal_approx(up), "a rod laid flat toward the target points at it, full length")
	var back := CastPose.on_screen(_look, _look.back_stop_deg, up, right)
	_check(back.length() <= 1.0 and back.x > 0.0, "at the back stop it leans out to his rod side")
	var turned := CastPose.on_screen(_look, 30.0, right, Vector2.DOWN)
	_check(turned.x > 0.0, "facing right, a forward rod leans right")


func _test_arm_rig() -> void:
	var view := AnglerView.new()
	var feet := Vector2(100, 100)
	var hand := feet + Vector2(3, -9)
	var butt := Vector2(10, -20)
	view.show_angler(feet, Vector2.UP, hand, hand + butt, butt, true)
	_check(view.shows_arm(), "version B shows the forearm")
	_check(is_equal_approx(view.arm_angle(), butt.angle()), "the forearm lies along the rod's butt")
	_check(view.get_node_or_null(^"ArmRig/Forearm") is Bone2D, "the forearm is a Bone2D in a Skeleton2D")
	view.show_angler(feet, Vector2.UP, hand, hand + butt)
	_check(not view.shows_arm(), "no forearm outside version B")
	view.show_angler(feet, Vector2.UP, hand, hand + butt, Vector2.ZERO, true)
	_check(not view.shows_arm(), "no forearm when the cast isn't posing the rod")
	view.free()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: " + what)
