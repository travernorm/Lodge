extends SceneTree
## Headless contract tests across file sets: data files, the scene that wires
## them up, and the input map. These catch a change in one place (a renamed fly,
## a new rule set, a new action) that something elsewhere still depends on.
##   godot --headless --path . --script res://tests/data_test.gd
##
## Every file in data/insects, data/flies, data/fish, data/cast_rules and data/take_rules is checked, so new
## data is covered without touching this file. data/catalog.tres must list
## exactly the fish, fly, insect and stretch files on disk.

const VIEW := Rect2(0, 0, 320, 200)

var _failures := 0
var _main: Node


func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var insects := _load_dir("res://data/insects", "Insect")
	var flies := _load_dir("res://data/flies", "FlyPattern")
	var fish := _load_dir("res://data/fish", "FishSpecies")
	var rules := _load_dir("res://data/cast_rules", "CastRules")
	_test_insects(insects)
	_test_flies(flies)
	_test_fish(fish, flies)
	_test_diets(fish, flies, insects)
	_test_cast_rules(rules)
	_test_scene_wiring(flies, fish, rules)
	_test_input_parity()
	_test_stretches(fish)
	_test_take_rules()
	_test_catalog(flies, fish, insects, _load_dir("res://data/stretches", "Stretch"))
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


func _test_fish(fish: Dictionary, _flies: Dictionary) -> void:
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


func _test_insects(insects: Dictionary) -> void:
	var ids := {}
	for path in insects:
		var bug: Insect = insects[path]
		var stem: String = path.get_file().get_basename()
		_check(String(bug.id) == stem, "insect %s: id matches its file name (%s)" % [stem, bug.id])
		_check(bug.display_name != "" and bug.kind != "", "insect %s: has a display name and a kind" % stem)
		_check(not ids.has(bug.id), "insect %s: id is unique" % stem)
		ids[bug.id] = true


## Flies, diets and insects agree: every fly imitates real bugs, every diet
## names real bugs with weights in [0, 1], and every fish has a fly in
## data/flies that it fully wants, so there's always a right answer.
func _test_diets(fish: Dictionary, flies: Dictionary, insects: Dictionary) -> void:
	var insect_ids := {}
	for path in insects:
		insect_ids[insects[path].id] = true
	for path in flies:
		var fly: FlyPattern = flies[path]
		var stem: String = path.get_file().get_basename()
		_check(fly.imitates.size() > 0, "fly %s: imitates at least one insect" % stem)
		for bug in fly.imitates:
			_check(bug != null and insects.has(bug.resource_path), "fly %s: imitates a data/insects file (%s)" % [stem, _path(bug)])
	for path in fish:
		var sp: FishSpecies = fish[path]
		var stem: String = path.get_file().get_basename()
		_check(sp.selectivity >= 0.0 and sp.selectivity <= 1.0, "fish %s: selectivity is in [0, 1]" % stem)
		_check(sp.diet.size() > 0, "fish %s: eats something" % stem)
		for key in sp.diet:
			_check((key is StringName or key is String) and insect_ids.has(StringName(key)), "fish %s: diet entry '%s' is a data/insects id" % [stem, key])
			var w = sp.diet[key]
			_check((w is float or w is int) and w >= 0.0 and w <= 1.0, "fish %s: diet weight for %s is in [0, 1]" % [stem, key])
		var has_answer := false
		for fpath in flies:
			if sp.fly_match(flies[fpath]) >= 1.0 - 0.0001:
				has_answer = true
		_check(has_answer, "fish %s: some fly in data/flies fully matches its diet" % stem)


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


## The bite rules file loads, has a name and description, valid numbers, and is
## the one the fishing controller uses. Drift past is the only bite rules.
func _test_take_rules() -> void:
	var rules := _load_dir("res://data/take_rules", "DriftPastRules")
	var names := {}
	for path in rules:
		var r: DriftPastRules = rules[path]
		var stem: String = path.get_file().get_basename()
		_check(r.display_name != "" and r.description != "", "bite rules %s: has a name and description" % stem)
		_check(not names.has(r.display_name), "bite rules %s: display name is unique" % stem)
		names[r.display_name] = true
		_check(r.window_m > 0.0 and r.slip_full > r.slip_free, "bite rules %s: window and slip limits are valid" % stem)
		_check(is_equal_approx(r.lane_share + r.delicate_share + r.drift_share, 1.0),
			"bite rules %s: lane, delicate and drift shares add up to 1" % stem)
	var fishing := _main.get_node_or_null(^"Fishing")
	if fishing == null:
		return
	var r: DriftPastRules = fishing.take_rules
	_check(r != null and rules.has(r.resource_path), "scene: the bite rules are a data/take_rules file (%s)" % _path(r))
	_check(rules.size() == 1, "bite rules: Drift past is the only bite rules file (%d found)" % rules.size())


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


## Every stretch: a river that crosses the map, the angler on dry land, rocks,
## logs and eddies in the water, and trout that are real species.
func _test_stretches(fish: Dictionary) -> void:
	var stretches := _load_dir("res://data/stretches", "Stretch")
	_check(not stretches.is_empty(), "there is at least one stretch")
	for path in stretches:
		var st: Stretch = stretches[path]
		var stem: String = path.get_file().get_basename()
		_check(st.centreline.size() >= 4, "stretch %s: centreline has at least 4 points" % stem)
		_check(st.half_width > 1.0, "stretch %s: river is wider than 2 m" % stem)
		_check(st.depth_keys.size() >= 2 and st.depth_keys[0].x <= 0.0 and st.depth_keys[-1].x >= 1.0,
			"stretch %s: depth keys run from 0 to 1" % stem)
		var f := RiverField.new()
		f.build_stretch(st)
		_check(not f.is_water(st.angler_start), "stretch %s: the angler starts on dry land" % stem)
		for r in st.rocks:
			_check(f.depth_at(Vector2(r.x, r.y) + Vector2(r.z + 0.5, 0)) > 0.0, "stretch %s: rock at (%s, %s) is in the river" % [stem, r.x, r.y])
		for e in st.eddies:
			_check(f.is_water(Vector2(e.x, e.y)), "stretch %s: eddy at (%s, %s) is in the river" % [stem, e.x, e.y])
		for l in st.logs:
			_check(f.is_water(Vector2(l.x, l.y)) or f.is_water(Vector2(l.z, l.w)), "stretch %s: log reaches the water" % stem)
		_check(not st.trout.is_empty(), "stretch %s: has trout" % stem)
		for sp in st.trout:
			_check(sp != null and fish.has(sp.resource_path), "stretch %s: trout %s is in data/fish" % [stem, sp.id if sp != null else "?"])


## data/catalog.tres lists every fish, fly, insect and stretch file exactly
## once, and nothing else, so the game sees all the content (REQ-0004 C1).
func _test_catalog(flies: Dictionary, fish: Dictionary, insects: Dictionary, stretches: Dictionary) -> void:
	var cat := load(Catalog.PATH) as Catalog
	_check(cat != null, "catalog: %s loads as a Catalog" % Catalog.PATH)
	if cat == null:
		return
	var fix := "Run tools/build_catalog.gd and commit data/catalog.tres."
	for pair in [["flies", flies], ["fish", fish], ["insects", insects], ["stretches", stretches]]:
		var listed := {}
		for res in cat.get(pair[0]):
			_check(res != null, "catalog: no empty %s entries" % pair[0])
			if res == null:
				continue
			_check(not listed.has(res.resource_path), "catalog: %s is listed once" % _path(res))
			listed[res.resource_path] = true
			_check(pair[1].has(res.resource_path), "catalog: %s is a file in its data folder. %s" % [_path(res), fix])
		for path in pair[1]:
			_check(listed.has(path), "catalog: lists %s. %s" % [path.trim_prefix("res://"), fix])


func _path(res: Resource) -> String:
	return res.resource_path.trim_prefix("res://") if res != null else "<null>"


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
