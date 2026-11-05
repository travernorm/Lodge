extends SceneTree
## River sheets (tools/import_river.gd, REQ-0014 step 1): the sheets in
## content/ agree with the stretches they generate, bends turn the right way,
## markers land on the right bank, and every kind of bad row is caught.
## Plans only, so data/ is never touched.
##   godot --headless --path . --script res://tests/river_import_test.gd

const Rivers := preload("res://tools/river_sheets.gd")
const TMP := "user://river_import_test"
const HEADER_R := "id,name,width_m,start_heading_deg,fish_per_100m,spring_fed,spawn,hatches_like,grass_bank_m,notes"
const HEADER_M := "river,at_m,length_m,kind,side,offset_m,size_m,value,note"
const RIVER_ROW := "test_creek,Test Creek,10,0,2,no,redband:1,,0,"

var _failures := 0


func _initialize() -> void:
	_test_sheets_match_data()
	_test_bends_turn()
	_test_banks()
	_test_planned_kinds()
	_test_bad_rows()
	_clean()
	if _failures == 0:
		print("River import tests passed.")
		quit(0)
	else:
		printerr("%d river import test(s) failed." % _failures)
		quit(1)


## Every section in the sheets has a stretch, and the stretch is what the
## sheet builds today (so a sheet edit without an import fails here).
func _test_sheets_match_data() -> void:
	var p := Rivers.plan()
	_check(p.errors.is_empty(), "the river sheets in content/ have no problems %s" % [p.errors])
	_check(not p.sections.is_empty(), "the river sheets build at least one section")
	var fix := "Run tools/import_river.gd after editing a river sheet"
	for s in p.sections:
		_check(ResourceLoader.exists(s.path), "%s exists. %s" % [s.path, fix])
		if not ResourceLoader.exists(s.path):
			continue
		var saved: Stretch = load(s.path)
		var built: Stretch = s.stretch
		var same := saved.size_m == built.size_m and saved.half_width == built.half_width \
			and _close(saved.centreline, built.centreline) and _close(saved.depth_keys, built.depth_keys) \
			and saved.features.size() == built.features.size() and saved.angler_start.is_equal_approx(built.angler_start) \
			and saved.spawn.size() == built.spawn.size() and saved.hatches.size() == built.hatches.size()
		_check(same, "%s matches its sheet. %s" % [s.path, fix])


## Flowing right (east), a right turn of 90 degrees ends flowing down (south).
func _test_bends_turn() -> void:
	var p := _plan([RIVER_ROW], ["test_creek,0,,section,,,,Test,", "test_creek,20,50,bend,,,,right 90,",
		"test_creek,120,,end,,,,,"])
	_check(p.errors.is_empty(), "a simple river plans %s" % [p.errors])
	if p.rivers.is_empty():
		return
	var r = p.rivers[0]
	_check(r.dir_at(0.0).is_equal_approx(Vector2.RIGHT), "the river starts flowing east")
	_check(r.dir_at(110.0).distance_to(Vector2.DOWN) < 0.05, "after a right 90 it flows south (%s)" % r.dir_at(110.0))
	_check(r.left_at(0.0).is_equal_approx(Vector2.UP), "flowing east, river left is north")
	_check(p.sections.size() == 1 and p.sections[0].path.ends_with("test_creek_test.tres"), "one section, named after the river and section")


## River left is north when flowing east; a boulder offset 2 m from the left
## bank of a 10 m river sits 3 m north of the centreline, in the water.
func _test_banks() -> void:
	var p := _plan([RIVER_ROW], ["test_creek,0,,section,,,,Test,", "test_creek,30,,boulder,left,2,0.5,,",
		"test_creek,40,,boulder,right,2,0.5,,", "test_creek,80,,end,,,,,"])
	if p.sections.is_empty():
		_check(false, "the bank test plans %s" % [p.errors])
		return
	var st: Stretch = p.sections[0].stretch
	var centre_y: float = st.size_m.y * 0.5
	var left: Boulder = st.features[0]
	var right: Boulder = st.features[1]
	_check(is_equal_approx(left.centre.y, centre_y - 3.0), "the left boulder is 3 m north (%s, centre %s)" % [left.centre, centre_y])
	_check(is_equal_approx(right.centre.y, centre_y + 3.0), "the right boulder is 3 m south (%s)" % right.centre)
	var f := RiverField.new()
	f.build_stretch(st)
	_check(f.is_water(left.centre + Vector2(0, -0.6)) and f.is_water(right.centre + Vector2(0, 0.6)), "both boulders are in the water")
	_check(not f.is_water(st.angler_start), "the angler starts on dry land")


## Kinds that later steps build are reported and drawn, never turned into
## features; a waterfall and a bridge (REQ-0014 step 3) become features across
## the river.
func _test_planned_kinds() -> void:
	var p := _plan([RIVER_ROW], ["test_creek,0,,section,,,,Test,", "test_creek,10,,cabin,right,15,,,",
		"test_creek,20,,ford,,,,,", "test_creek,60,,end,,,,,"])
	_check(p.errors.is_empty() and p.notes.size() == 2, "planned kinds are notes, not errors %s %s" % [p.errors, p.notes])
	_check(not p.sections.is_empty() and p.sections[0].stretch.features.is_empty(), "planned kinds add no feature yet")
	p = _plan([RIVER_ROW], ["test_creek,0,,section,,,,Test,", "test_creek,10,,bridge,mid,,3,footbridge,",
		"test_creek,0,,waterfall,mid,,10,,", "test_creek,60,,end,,,,,"])
	_check(p.errors.is_empty() and p.notes.is_empty(), "a waterfall and a bridge are built kinds %s %s" % [p.errors, p.notes])
	var feats: Array = p.sections[0].stretch.features if not p.sections.is_empty() else []
	var fall: Waterfall = null
	var bridge: Bridge = null
	for f in feats:
		if f is Waterfall:
			fall = f
		elif f is Bridge:
			bridge = f
	_check(fall != null and is_equal_approx(fall.foam_m, 10.0), "the waterfall becomes a Waterfall with 10 m of white water")
	_check(bridge != null and is_equal_approx(bridge.width_m, 3.0), "the bridge becomes a 3 m wide Bridge")
	if fall != null and bridge != null:
		var width := 10.0  # test_creek is 10 m wide
		_check(fall.a.distance_to(fall.b) > width and bridge.a.distance_to(bridge.b) > width,
			"both reach from bank to bank (%.1f, %.1f m)" % [fall.a.distance_to(fall.b), bridge.a.distance_to(bridge.b)])
		_check(fall.down.dot((bridge.a.lerp(bridge.b, 0.5) - fall.a.lerp(fall.b, 0.5)).normalized()) > 0.9,
			"the falls face downstream, toward the bridge")


func _test_bad_rows() -> void:
	var cases := {
		"unknown kind": [[RIVER_ROW], ["test_creek,10,,volcano,mid,,,,"]],
		"bad side": [[RIVER_ROW], ["test_creek,10,,boulder,middle,,1,,"]],
		"missing side": [[RIVER_ROW], ["test_creek,10,,boulder,,,1,,"]],
		"bad bend": [[RIVER_ROW], ["test_creek,10,20,bend,,,,sideways 40,"]],
		"bend without length": [[RIVER_ROW], ["test_creek,10,,bend,,,,left 40,"]],
		"bad water": [[RIVER_ROW], ["test_creek,10,20,water,,,,lake,"]],
		"unnamed section": [[RIVER_ROW], ["test_creek,0,,section,,,,,"]],
		"no at_m": [[RIVER_ROW], ["test_creek,,,boulder,mid,,1,,"]],
		"not a number": [[RIVER_ROW], ["test_creek,ten,,boulder,mid,,1,,"]],
		"past the end": [[RIVER_ROW], ["test_creek,50,,end,,,,,", "test_creek,60,,boulder,mid,,1,,"]],
		"unknown river": [[RIVER_ROW], ["other_creek,10,,boulder,mid,,1,,"]],
		"unknown fish": [["test_creek,Test,10,0,2,no,goldfish:1,,0,"], []],
		"bad abundance": [["test_creek,Test,10,0,2,no,redband:2,,0,"], []],
		"no spawn": [["test_creek,Test,10,0,2,no,,,0,"], []],
		"unknown hatches_like": [["test_creek,Test,10,0,2,no,redband:1,nowhere,0,"], []],
		"bad id": [["Test Creek,Test,10,0,2,no,redband:1,,0,"], []],
		"river twice": [[RIVER_ROW, RIVER_ROW], []],
	}
	for name in cases:
		var p := _plan(cases[name][0], cases[name][1])
		_check(not p.errors.is_empty(), "%s is caught" % name)


func _close(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_to(b[i]) > 0.001:
			return false
	return true


func _plan(rivers: Array, markers: Array) -> Object:
	DirAccess.make_dir_recursive_absolute(TMP)
	var f := FileAccess.open(TMP.path_join(Rivers.RIVERS), FileAccess.WRITE)
	f.store_string("\n".join([HEADER_R] + rivers) + "\n")
	f.close()
	f = FileAccess.open(TMP.path_join(Rivers.MARKERS), FileAccess.WRITE)
	f.store_string("\n".join([HEADER_M] + markers) + "\n")
	f.close()
	return Rivers.plan(TMP)


func _clean() -> void:
	for file in [Rivers.RIVERS, Rivers.MARKERS]:
		DirAccess.remove_absolute(TMP.path_join(file))
	DirAccess.remove_absolute(TMP)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", what)
