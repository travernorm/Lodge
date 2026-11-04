extends SceneTree
## WaterView's edge texture (bank and rock distance for the foam lines) and the
## palette looks in data/looks.

var _failures := 0


func _initialize() -> void:
	var stretch: Stretch = load("res://data/stretches/demo_freestone.tres")
	var river := RiverField.new()
	river.build_stretch(stretch)
	_test_bank_distance(river)
	_test_rock_distance(river)
	_test_palette_looks()
	if _failures == 0:
		print("Water edges tests passed.")
		quit(0)
	else:
		printerr("%d water edges test(s) failed." % _failures)
		quit(1)


## R holds metres to the bank, 0 on dry land, capped at EDGE_RANGE.
func _test_bank_distance(river: RiverField) -> void:
	var img := WaterView.edge_image(river)
	_check(img.get_width() == river.cols and img.get_height() == river.rows, "edge image is one texel per cell")
	var step := WaterView.EDGE_RANGE / 255.0
	var worst := 0.0
	for j in range(0, river.rows, 5):
		for i in range(0, river.cols, 5):
			var idx := j * river.cols + i
			var want := clampf(-river.shore[idx], 0.0, WaterView.EDGE_RANGE)
			worst = maxf(worst, absf(img.get_pixel(i, j).r * WaterView.EDGE_RANGE - want))
	_check(worst <= step, "edge bank distance matches the river (worst %.3f m)" % worst)


## G is 0 inside every boulder and grows with distance from it.
func _test_rock_distance(river: RiverField) -> void:
	var img := WaterView.edge_image(river)
	var boulders := river.features.filter(func(f: RiverFeature) -> bool: return f is Boulder)
	_check(not boulders.is_empty(), "the demo stretch has boulders to ring with foam")
	for b: Boulder in boulders:
		var i := roundi(b.centre.x / RiverField.CELL)
		var j := roundi((b.centre.y - river.top) / RiverField.CELL)
		_check(img.get_pixel(i, j).g < 0.01, "rock distance is 0 at a boulder's centre")
		var k := ceili((b.radius + 1.0) / RiverField.CELL)
		var away := img.get_pixel(clampi(i + k, 0, river.cols - 1), j).g * WaterView.EDGE_RANGE
		_check(away > 0.5, "rock distance grows away from a boulder (%.2f m)" % away)


## Every look with a palette has at least two colours, and its textures have a
## usable average colour for the shader's pattern.
func _test_palette_looks() -> void:
	var found := 0
	for f in DirAccess.get_files_at("res://data/looks"):
		if not f.ends_with(".tres"):
			continue
		var look: WaterLook = load("res://data/looks/" + f)
		if look.palette == null:
			continue
		found += 1
		_check(look.palette.get_point_count() >= 2, "look %s: the palette has 2+ colours" % f)
		for t in [look.deep, look.mid]:
			var m := WaterView.mean_colour(t)
			_check(m.r > 0.0 and m.g > 0.0 and m.b > 0.0 and m != Color.WHITE,
				"look %s: %s has an average colour" % [f, t.resource_path])
	_check(found > 0, "at least one water look uses a palette")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: " + what)
