extends SceneTree
## Fly art (FlyView): which of the 8 views shows for a facing, and where that
## view sits in the sheet. On the water a fly faces the rod tip, so a fly
## straight out from the angler shows its head-on view.
##   godot --headless --path . --script res://tests/fly_view_test.gd

var _failures := 0


func _initialize() -> void:
	_test_facings()
	_test_frames()
	_test_show_and_clear()
	if _failures == 0:
		print("Fly view tests passed.")
		quit(0)
	else:
		printerr("%d fly view test(s) failed." % _failures)
		quit(1)


func _test_facings() -> void:
	var cases := [
		[Vector2.DOWN, FlyView.Facing.SOUTH],
		[Vector2(1, 1), FlyView.Facing.SOUTH_EAST],
		[Vector2.RIGHT, FlyView.Facing.EAST],
		[Vector2(1, -1), FlyView.Facing.NORTH_EAST],
		[Vector2.UP, FlyView.Facing.NORTH],
		[Vector2(-1, -1), FlyView.Facing.NORTH_WEST],
		[Vector2.LEFT, FlyView.Facing.WEST],
		[Vector2(-1, 1), FlyView.Facing.SOUTH_WEST],
		[Vector2(0.2, 1), FlyView.Facing.SOUTH],  # snaps to the nearest view
		[Vector2.ZERO, FlyView.Facing.SOUTH],
	]
	for c in cases:
		_check(FlyView.facing_for(c[0]) == c[1], "a head pointing %s shows view %d" % [c[0], c[1]])
	# The fly is out on the water above the angler, so the rod tip is below it.
	var fly_at := Vector2(160, 60)
	var tip := Vector2(160, 180)
	_check(FlyView.facing_for(tip - fly_at) == FlyView.Facing.SOUTH, "a fly straight out faces the angler head on")


func _test_frames() -> void:
	var sheet := ImageTexture.create_from_image(Image.create(48 * 8, 48, false, Image.FORMAT_RGBA8))
	_check(FlyView.frame_rect(sheet, FlyView.Facing.SOUTH) == Rect2(0, 0, 48, 48), "the first view is the left cell")
	_check(FlyView.frame_rect(sheet, FlyView.Facing.WEST) == Rect2(288, 0, 48, 48), "west is the seventh cell")


func _test_show_and_clear() -> void:
	var view := FlyView.new()
	var fly: FlyPattern = load("res://data/tackle/flies/parachute_adams.tres")
	_check(fly.sprite_sheet != null, "the Parachute Adams has art")
	view.show_fly(fly, Vector2(10.6, 20.2), Vector2.LEFT)
	_check(view.visible and view.position == Vector2(10, 20), "show_fly puts the fly on a whole pixel")
	view.clear()
	_check(not view.visible, "clear hides it")
	view.show_fly(null, Vector2.ZERO)
	_check(not view.visible, "no fly tied on shows nothing")
	view.free()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: " + what)
