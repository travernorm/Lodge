extends SceneTree
## Headless contract tests across file sets: data files, the scene that wires
## them up, and the input map. These catch a change in one place (a renamed fly,
## a new rule set, a new action) that something elsewhere still depends on.
##   godot --headless --path . --script res://tests/data_test.gd
##
## Every file in data/flies, data/fish and data/cast_rules is checked, so new
## data is covered without touching this file.

const VIEW := Rect2(0, 0, 320, 200)

var _failures := 0
var _main: Node


func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var flies := _load_dir("res://data/flies", "FlyPattern")
	var fish := _load_dir("res://data/fish", "FishSpecies")
	var rules := _load_dir("res://data/cast_rules", "CastRules")
	_test_flies(flies)
	_test_fish(fish, flies)
	_test_cast_rules(rules)
	_test_scene_wiring(flies, fish, rules)
	_test_input_parity()
	_main.free()
	if _failures == 0:
		print("Data tests passed.")
		quit(0)
	else:
		printerr("%d data test(s) failed." % _failures)
		quit(1)


## Loads every .tres in a folder and checks it is the expected class.
## Returns {path: resource}.
func _load_dir(dir: String, class_label: String) -> Dictionary:
	var out := {}
	var files := DirAccess.get_files_at(dir)
	_check(files.size() > 0, "%s has data files" % dir)
	for file in files:
		if not file.ends_with(".tres"):
			continue
		var path := dir.path_join(file)
		var res := load(path)
		var ok: bool = res != null and _inherits(res.get_script(), class_label)
		_check(ok, "%s loads as a %s" % [path.trim_prefix("res://"), class_label])
		if ok:
			out[path] = res
	return out


func _inherits(script: Script, class_label: String) -> bool:
	while script != null:
		if script.get_global_name() == class_label:
			return true
		script = script.get_base_script()
	return false


func _test_flies(flies: Dictionary) -> void:
	var ids := {}
	for path in flies:
		var fly: FlyPattern = flies[path]
		var stem: String = path.get_file().get_basename()
		_check(String(fly.id) == stem, "fly %s: id matches its file name (%s)" % [stem, fly.id])
		_check(fly.display_name != "", "fly %s: has a display name" % stem)
		_check(not ids.has(fly.id), "fly %s: id is unique" % stem)
		ids[fly.id] = true


func _test_fish(fish: Dictionary, flies: Dictionary) -> void:
	var fly_ids := {}
	for path in flies:
		fly_ids[String(flies[path].id)] = true
	var river: RiverField = _main.river
	var ids := {}
	for path in fish:
		var sp: FishSpecies = fish[path]
		var stem: String = path.get_file().get_basename()
		_check(String(sp.id) == stem, "fish %s: id matches its file name (%s)" % [stem, sp.id])
		_check(sp.display_name != "", "fish %s: has a display name" % stem)
		_check(not ids.has(sp.id), "fish %s: id is unique" % stem)
		ids[sp.id] = true
		_check(sp.bite_chance > 0.0 and sp.bite_chance <= 1.0, "fish %s: bite_chance is in (0, 1]" % stem)
		_check(sp.bite_range_m > Fish.CLOSE_RANGE, "fish %s: bite_range_m is past CLOSE_RANGE" % stem)
		_check(sp.set_min < sp.set_max, "fish %s: hook-set window is valid" % stem)
		_check(sp.min_length_in <= sp.max_length_in, "fish %s: length range is valid" % stem)
		_check(Rect2(Vector2.ZERO, WorldScale.vec_to_m(VIEW.size)).encloses(sp.lie_area_m), "fish %s: lie_area_m is on screen" % stem)
		_check(_water_cells(river, sp.lie_area_m) >= 4, "fish %s: lie_area_m covers water in the stream" % stem)
		for fly_id in sp.preferred_flies:
			_check(fly_ids.has(fly_id), "fish %s: preferred fly '%s' exists in data/flies" % [stem, fly_id])


func _water_cells(river: RiverField, area: Rect2) -> int:
	var n := 0
	var y := area.position.y
	while y <= area.end.y:
		var x := area.position.x
		while x <= area.end.x:
			if river.is_water(Vector2(x, y)):
				n += 1
			x += 0.5
		y += 0.5
	return n


func _test_cast_rules(rules: Dictionary) -> void:
	var names := {}
	for path in rules:
		var r: CastRules = rules[path]
		var stem: String = path.get_file().get_basename()
		_check(r.display_name != "", "rules %s: has a display name" % stem)
		_check(r.description != "", "rules %s: has a description for practice mode" % stem)
		_check(not names.has(r.display_name), "rules %s: display name is unique" % stem)
		names[r.display_name] = true
	_check(load("res://data/cast_tuning.tres") is CastTuning, "data/cast_tuning.tres loads as CastTuning")


## The scene's lists point at data that exists, and every rule set file can be
## reached in game.
func _test_scene_wiring(flies: Dictionary, fish: Dictionary, rules: Dictionary) -> void:
	var fishing := _main.get_node_or_null(^"Fishing")
	var practice := _main.get_node_or_null(^"Practice")
	var cast := _main.get_node_or_null(^"Cast")
	_check(fishing != null and practice != null and cast != null, "scene: Cast, Fishing and Practice nodes exist")
	if fishing == null or practice == null or cast == null:
		return
	_check(fishing.flies.size() > 0, "scene: the fly box isn't empty")
	for fly in fishing.flies:
		_check(fly != null and flies.has(fly.resource_path), "scene: fly box entry %s is a data/flies file" % _path(fly))
	_check(fishing.stocking.size() > 0, "scene: the stream is stocked")
	for sp in fishing.stocking:
		_check(sp != null and fish.has(sp.resource_path), "scene: stocking entry %s is a data/fish file" % _path(sp))
	var in_chassis := {}
	for r in practice.chassis:
		_check(r != null and rules.has(r.resource_path), "scene: chassis entry %s is a data/cast_rules file" % _path(r))
		if r != null:
			in_chassis[r.resource_path] = true
	for path in rules:
		_check(in_chassis.has(path), "scene: %s is in the Practice chassis (or players can't pick it)" % path.trim_prefix("res://"))
	_check(cast.rules != null and in_chassis.has(cast.rules.resource_path), "scene: the default rule set is in the chassis")


## Every action works on both a controller and a keyboard, every action the code
## names exists, and nothing else claims the same button or key.
func _test_input_parity() -> void:
	var actions := []
	for prop in ProjectSettings.get_property_list():
		var name: String = prop.name
		if name.begins_with("input/") and not name.begins_with("input/ui_"):
			actions.append(name.trim_prefix("input/"))
	_check(actions.size() > 0, "input: project.godot defines actions")
	var keys := {}
	var buttons := {}
	for action in actions:
		var has_key := false
		var has_pad := false
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				has_key = true
				var k: String = OS.get_keycode_string(e.physical_keycode)
				_check(not keys.has(k), "input: key %s is bound once (%s, %s)" % [k, keys.get(k, "-"), action])
				keys[k] = action
			elif e is InputEventJoypadButton:
				has_pad = true
				var b := "button %d" % e.button_index
				_check(not buttons.has(b), "input: pad %s is bound once (%s, %s)" % [b, buttons.get(b, "-"), action])
				buttons[b] = action
			elif e is InputEventJoypadMotion:
				has_pad = true
				var a := "axis %d %s" % [e.axis, "+" if e.axis_value > 0 else "-"]
				_check(not buttons.has(a), "input: pad %s is bound once (%s, %s)" % [a, buttons.get(a, "-"), action])
				buttons[a] = action
		_check(has_key, "input: %s has a keyboard key" % action)
		_check(has_pad, "input: %s has a controller binding" % action)
	var controls: Dictionary = (load("res://scripts/controls.gd") as Script).get_script_constant_map()
	for c in controls:
		if controls[c] is StringName:
			_check(InputMap.has_action(controls[c]), "input: Controls.%s (%s) is in the input map" % [c, controls[c]])


func _path(res: Resource) -> String:
	return res.resource_path.trim_prefix("res://") if res != null else "<null>"


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
