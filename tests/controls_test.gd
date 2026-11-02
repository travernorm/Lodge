extends SceneTree
## Headless checks that the casting and mending buttons sit where Traver chose:
## L1 / Q starts the back cast, R1 / E is the forward cast, Square / M mends,
## and the bite-rules switch is gone (Drift past is the only bite rules).
##   godot --headless --path . --script res://tests/controls_test.gd

var _failures := 0


func _initialize() -> void:
	_expect_button(&"cast_back", JOY_BUTTON_LEFT_SHOULDER, KEY_Q)
	_expect_button(&"cast_forward", JOY_BUTTON_RIGHT_SHOULDER, KEY_E)
	_expect_button(&"mend", JOY_BUTTON_X, KEY_M)
	_check(not InputMap.has_action(&"cycle_bite_rules"), "the bite-rules switch is gone")
	_check(Controls.MEND == &"mend", "Controls.MEND names the mend action")
	if _failures == 0:
		print("Controls tests passed.")
		quit(0)
	else:
		printerr("%d controls test(s) failed." % _failures)
		quit(1)


func _expect_button(action: StringName, button: JoyButton, key: Key) -> void:
	var pad := false
	var kb := false
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			pad = e.button_index == button
		elif e is InputEventKey:
			kb = e.physical_keycode == key
	_check(pad, "%s is on pad button %d" % [action, button])
	_check(kb, "%s is on key %s" % [action, OS.get_keycode_string(key)])


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", what)
