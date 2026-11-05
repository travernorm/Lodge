extends SceneTree
## Headless tests for the shoreline (REQ-0013): where BankZones puts the wet
## line, gravel, sand and the cut bank face on the demo stretch, and that the
## baked texture BankView draws from keeps the bank off the water.
##   godot --headless --path . --script res://tests/bank_test.gd

var _failures := 0
var _stretch: Stretch = load("res://data/stretches/demo_freestone.tres")
var _look: BankLook = load("res://data/bank_looks/spring.tres")
var _river := RiverField.new()


func _initialize() -> void:
	_river.build_stretch(_stretch)
	_test_off_the_water()
	_test_face_on_outside_bends()
	_test_wet_line()
	_test_point_bars()
	_test_gravel_bars()
	_test_no_strip_no_face()
	if _failures == 0:
		print("Bank tests passed.")
		quit(0)
	else:
		printerr("%d bank test(s) failed." % _failures)
		quit(1)


## The zone of a land cell, from the field the way BankView bakes it.
func _zone(idx: int, look := _look) -> BankZones.Zone:
	var shore := _river.shore[idx]
	var b := _river.bend[idx]
	return BankZones.zone(shore, BankZones.face_m(b, look), BankZones.gravel_m(b, look), look)


## Acceptance: no BankView pixel lies on water. The shader draws only where the
## baked wet channel is low, so every water cell must bake wet and every land
## cell dry, and the distances must match the field.
func _test_off_the_water() -> void:
	var img := BankView.data_image(_river, _look)
	_check(img.get_width() == _river.cols and img.get_height() == _river.rows, "bake: one texel per field cell")
	var wet_ok := true
	var shore_ok := true
	var data := img.get_data()
	for idx in _river.cols * _river.rows:
		var wet := data[idx * 4 + 3] == 255
		wet_ok = wet_ok and wet == (_river.wet[idx] == 1)
		var want := clampf(_river.shore[idx], 0.0, BankView.SHORE_RANGE)
		shore_ok = shore_ok and absf(data[idx * 4] / 255.0 * BankView.SHORE_RANGE - want) < 0.05
	_check(wet_ok, "bake: water cells are wet and land cells dry, so the bank never covers the water")
	_check(shore_ok, "bake: distance from the water matches the field")


## Acceptance: the cut bank only appears on the outside of a bend.
func _test_face_on_outside_bends() -> void:
	var faces := 0
	var outside := true
	for idx in _river.shore.size():
		if _river.wet[idx] == 1 or _zone(idx) != BankZones.Zone.FACE:
			continue
		faces += 1
		outside = outside and _river.bend[idx] > _look.cut_bend_start
	_check(faces > 50, "face: the demo's outside bends have a cut bank (%d cells)" % faces)
	_check(outside, "face: only where the bank is on the outside of a bend")


## Acceptance: the wet line sits against the water wherever there's no face.
func _test_wet_line() -> void:
	var wet := 0
	var ok := true
	for idx in _river.shore.size():
		var s := _river.shore[idx]
		if _river.wet[idx] == 1 or s < 0.0 or s >= _look.wet_width_m:
			continue
		var z := _zone(idx)
		ok = ok and (z == BankZones.Zone.WET or z == BankZones.Zone.FACE)
		wet += 1 if z == BankZones.Zone.WET else 0
	_check(ok and wet > 50, "wet: land within %.2f m of the water is the wet line or the face (%d wet cells)" % [_look.wet_width_m, wet])
	_check(BankZones.zone(_look.wet_width_m + 0.05, 0.0, BankZones.gravel_m(0.0, _look), _look) == BankZones.Zone.GRAVEL,
		"wet: just past the wet line is dry gravel")
	_check(BankZones.zone(BankZones.gravel_m(0.0, _look) + 0.1, 0.0, BankZones.gravel_m(0.0, _look), _look) == BankZones.Zone.GROUND,
		"wet: past the gravel is plain ground")


## The inside of a bend widens into a point bar, with a sand fringe at its edge.
func _test_point_bars() -> void:
	var straight := BankZones.gravel_m(0.0, _look)
	var tight := BankZones.gravel_m(-1.0, _look)
	_check(tight > straight + 1.0, "point bar: gravel reaches %.2f m on a tight inside bend, %.2f m on a straight" % [tight, straight])
	_check(BankZones.gravel_m(1.0, _look) == straight, "point bar: none on the outside of a bend")
	_check(BankZones.zone(tight - _look.sand_width_m * 0.5, 0.0, tight, _look) == BankZones.Zone.SAND,
		"point bar: sand at its outer edge")


## A GravelBar feature turns the ground inside it to gravel, wherever it is.
func _test_gravel_bars() -> void:
	var river := RiverField.new()
	river.build_stretch(_stretch)
	var g := GravelBar.new()
	g.centre = river.cell_pos(river.cols / 2, river.rows / 2)
	g.radius = 2.0
	river.features.append(g)
	var inside := BankView._inside_bars(river)
	var at := (river.rows / 2) * river.cols + river.cols / 2
	_check(absf(inside[at] - 2.0) < 0.01, "gravel bar: its centre is a full radius inside it")
	_check(inside[0] == 0.0, "gravel bar: cells far away aren't inside it")
	var gravel := BankZones.with_bar(BankZones.gravel_m(0.0, _look), 5.0, inside[at])
	_check(BankZones.zone(5.0, 0.0, gravel, _look) == BankZones.Zone.GRAVEL,
		"gravel bar: its centre is gravel even 5 m from the water")
	_check(BankZones.with_bar(1.0, 5.0, 0.0) == 1.0, "gravel bar: outside one, the gravel is unchanged")


## With no cut bank strip in the look, there is no face: gravel instead.
func _test_no_strip_no_face() -> void:
	var bare := _look.duplicate() as BankLook
	bare.cut_bank = null
	var any := false
	for idx in _river.shore.size():
		if _river.wet[idx] == 0 and _zone(idx, bare) == BankZones.Zone.FACE:
			any = true
			break
	_check(not any, "no strip: no cut bank face anywhere")


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", what)
