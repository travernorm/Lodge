extends SceneTree
## Angler art (AnglerView): the sheet is Traver's 8 views, the view turns with
## the way the angler faces, and he stands on his feet with the rod in hand.
##   godot --headless --path . --script res://tests/angler_view_test.gd

var _failures := 0


func _initialize() -> void:
	_test_sheet()
	_test_facing()
	_test_placement()
	_test_drawn_first()
	if _failures == 0:
		print("Angler view tests passed.")
		quit(0)
	else:
		printerr("%d angler view test(s) failed." % _failures)
		quit(1)


func _test_sheet() -> void:
	var view := AnglerView.new()
	_check(view.sheet != null, "the angler has a sprite sheet")
	if view.sheet != null:
		_check(view.sheet.get_width() == view.sheet.get_height() * FlyView.VIEWS, "the sheet is 8 square views in a row")
	_check(view.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "the sheet is sampled with mipmaps")
	view.free()


func _test_facing() -> void:
	var view := AnglerView.new()
	var cases := [
		[Vector2.UP, FlyView.Facing.NORTH],  # facing across the test screen: his back
		[Vector2.DOWN, FlyView.Facing.SOUTH],
		[Vector2(1, -1), FlyView.Facing.NORTH_EAST],
		[Vector2.LEFT, FlyView.Facing.WEST],
	]
	for c in cases:
		view.show_angler(Vector2(100, 100), c[0], Vector2(103, 91), Vector2(103, 65))
		_check(view.facing() == c[1], "facing %s shows view %d" % [c[0], c[1]])
	view.free()


func _test_placement() -> void:
	var view := AnglerView.new()
	view.show_angler(Vector2(100.6, 120.4), Vector2.UP, Vector2(103, 111), Vector2(103, 85))
	_check(view.position == Vector2(100, 120), "he stands on whole pixels")
	var body := AnglerView.body_rect()
	_check(is_equal_approx(body.end.y, 0.0), "his feet are at the angler's position")
	_check(is_equal_approx(body.get_center().x, 0.0), "he is centred on it")
	view.free()


## The line and the fly draw over the angler, so he is the owner's first child.
func _test_drawn_first() -> void:
	var owner := Node2D.new()
	owner.add_child(Node2D.new())
	var view := AnglerView.add_to(owner)
	_check(view.get_index() == 0, "the angler draws before the owner's other children")
	owner.free()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: " + what)
