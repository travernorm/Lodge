extends SceneTree
## WaterView (REQ-0006): the field texture carries the river's real current,
## depth and wet cells, and the stream scene hands the water over to the view.

var _failures := 0


func _initialize() -> void:
	var stretch: Stretch = load("res://data/stretches/demo_freestone.tres")
	var river := RiverField.new()
	river.build_stretch(stretch)
	_test_field_image(river)
	_finish.call_deferred()


func _finish() -> void:
	await _test_scene()
	if _failures == 0:
		print("Water view tests passed.")
		quit(0)
	else:
		printerr("%d water view test(s) failed." % _failures)
		quit(1)


## Decode texels back to metres per second and depth, and compare with the
## river at those cells.
func _test_field_image(river: RiverField) -> void:
	var img := WaterView.field_image(river)
	_check(img.get_width() == river.cols and img.get_height() == river.rows, "field image is one texel per cell")
	var range := WaterView.flow_range()
	var worst_v := 0.0
	var worst_d := 0.0
	var wet_ok := true
	for j in range(0, river.rows, 7):
		for i in range(0, river.cols, 7):
			var idx := j * river.cols + i
			var c := img.get_pixel(i, j)
			var v := Vector2(c.r - 0.5, c.g - 0.5) * 2.0 * range
			worst_v = maxf(worst_v, v.distance_to(river.velocity[idx]))
			worst_d = maxf(worst_d, absf(c.b - river.depth[idx]))
			wet_ok = wet_ok and ((c.a > 0.5) == (river.wet[idx] == 1))
	_check(worst_v <= range / 255.0 * 1.5, "field current matches the river (worst %.3f m/s)" % worst_v)
	_check(worst_d <= 1.0 / 255.0, "field depth matches the river (worst %.4f)" % worst_d)
	_check(wet_ok, "field wet cells match the river")
	var fastest := 0.0
	for v in river.velocity:
		fastest = maxf(fastest, v.length())
	_check(fastest <= range, "the fastest current (%.2f m/s) fits the encoded range" % fastest)


## With a look set, the stream scene leaves its water pixels clear for the view;
## without one, it paints the old bands.
func _test_scene() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var water := main.get_node(^"Water") as WaterView
	_check(water.is_active(), "the scene's water view is active")
	var view: RiverView = null
	for child in main.get_children():
		if child is RiverView:
			view = child
	_check(view != null, "the stream scene has a RiverView (step A2)")
	if view == null:
		main.free()
		return
	var tex: Texture2D = view.ground_texture()
	var img := tex.get_image()
	# REQ-0013: the BankView paints the land now, so with both views active the
	# stream scene's picture is clear everywhere, deep water included.
	_check(img.is_invisible(), "stream scene leaves the water and the land clear for the views")
	_check(main.get_node(^"Bank").is_active(), "the scene's bank view paints the land instead")
	main.free()


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1
