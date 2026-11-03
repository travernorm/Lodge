extends SceneTree
## Writes Lodge's input actions into project.godot.
## Run from the repo root:
##   godot --headless --path . --script res://tools/setup_input_map.gd
##
## Keeping the mapping here (instead of only in the editor's Input Map tab) makes
## it reviewable and easy to regenerate when controls change.

const DEADZONE := 0.2


func _initialize() -> void:
	var actions := {
		"move_left": [_axis(JOY_AXIS_LEFT_X, -1.0), _button(JOY_BUTTON_DPAD_LEFT), _key(KEY_A)],
		"move_right": [_axis(JOY_AXIS_LEFT_X, 1.0), _button(JOY_BUTTON_DPAD_RIGHT), _key(KEY_D)],
		"move_up": [_axis(JOY_AXIS_LEFT_Y, -1.0), _button(JOY_BUTTON_DPAD_UP), _key(KEY_W)],
		"move_down": [_axis(JOY_AXIS_LEFT_Y, 1.0), _button(JOY_BUTTON_DPAD_DOWN), _key(KEY_S)],
		"rod_left": [_axis(JOY_AXIS_RIGHT_X, -1.0), _key(KEY_J)],
		"rod_right": [_axis(JOY_AXIS_RIGHT_X, 1.0), _key(KEY_L)],
		"rod_up": [_axis(JOY_AXIS_RIGHT_Y, -1.0), _key(KEY_I)],
		"rod_down": [_axis(JOY_AXIS_RIGHT_Y, 1.0), _key(KEY_K)],
		"cast_back": [_button(JOY_BUTTON_LEFT_SHOULDER), _key(KEY_Q)],
		"cast_forward": [_button(JOY_BUTTON_RIGHT_SHOULDER), _key(KEY_E)],
		"mend": [_button(JOY_BUTTON_X), _key(KEY_M)],
		"interact": [_button(JOY_BUTTON_A), _key(KEY_SPACE)],
		"change_fly": [_button(JOY_BUTTON_Y), _key(KEY_F)],
		"change_rod": [_axis(JOY_AXIS_TRIGGER_LEFT, 1.0), _key(KEY_R)],
		"back": [_button(JOY_BUTTON_B), _key(KEY_BACKSPACE)],
		"pause": [_button(JOY_BUTTON_START), _key(KEY_ESCAPE)],
		"toggle_debug": [_button(JOY_BUTTON_BACK), _key(KEY_F1)],
		"practice_mode": [_button(JOY_BUTTON_LEFT_STICK), _key(KEY_T)],
		"cycle_rules": [_button(JOY_BUTTON_RIGHT_STICK), _key(KEY_TAB)],
	}
	# Drop actions that are no longer in the list, so removing one here removes it
	# from project.godot too.
	for prop in ProjectSettings.get_property_list():
		var name: String = prop.name
		if name.begins_with("input/") and not actions.has(name.trim_prefix("input/")) and not name.begins_with("input/ui_"):
			ProjectSettings.set_setting(name, null)
	for action_name in actions:
		ProjectSettings.set_setting("input/" + action_name, {
			"deadzone": DEADZONE,
			"events": actions[action_name],
		})
	var err := ProjectSettings.save()
	if err != OK:
		printerr("Could not save project.godot: ", error_string(err))
		quit(1)
		return
	print("Wrote %d input actions to project.godot" % actions.size())
	quit(0)


func _button(index: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = -1
	e.button_index = index
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = -1
	e.axis = axis
	e.axis_value = value
	return e


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.device = -1
	e.physical_keycode = code
	return e
