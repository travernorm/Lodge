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
	_test_walk_sheet()
	_test_walking()
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


func _test_walk_sheet() -> void:
	var view := AnglerView.new()
	_check(view.walk_sheet != null, "the angler has a walk sheet")
	if view.walk_sheet != null:
		_check(AnglerView.walk_frames(view.walk_sheet) == 8, "the walk has 8 frames")
		_check(view.walk_sheet.get_height() == view.sheet.get_height() * FlyView.VIEWS, "one row of walk frames per view, the idle's cell size")
		_check(AnglerView.walk_rect(view.walk_sheet, FlyView.Facing.EAST, 3) == Rect2(144, 96, 48, 48), "east is the third row, frame 3 the fourth cell")
	view.free()


## He walks the way his feet move, the frames stepping with distance, and
## stands facing the water when he stops.
func _test_walking() -> void:
	var view := AnglerView.new()
	var hand := Vector2(3, -9)
	var tip := Vector2(3, -35)
	view.show_angler(Vector2(100, 100), Vector2.UP, Vector2(100, 100) + hand, Vector2(100, 100) + tip)
	_check(not view.is_walking() and view.walk_frame() == -1, "standing still on the first frame shown")
	var p := Vector2(100, 100)
	var frames_seen := {}
	for i in 32:  # 32 px east, one walk cycle
		p.x += 1.0
		view.show_angler(p, Vector2.UP, p + hand, p + tip)
		frames_seen[view.walk_frame()] = true
	_check(view.is_walking(), "moving makes him walk")
	_check(view.facing() == FlyView.Facing.EAST, "he faces the way he walks, not the water")
	_check(frames_seen.size() == 8, "one cycle of walking shows all 8 frames (saw %d)" % frames_seen.size())
	view.show_angler(p, Vector2.UP, p + hand, p + tip)
	_check(not view.is_walking(), "stopping stands him still")
	_check(view.facing() == FlyView.Facing.NORTH, "stopped, he turns back to the water")
	p.x -= 1.0
	view.show_angler(p, Vector2.UP, p + hand, p + tip)
	_check(view.walk_frame() == 0 and view.facing() == FlyView.Facing.WEST, "walking again starts the cycle from its first frame")
	view.free()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: " + what)
