extends SceneTree
## Headless tests for the world root (REQ-0014): the game starts in the Upper
## Fall, walking off its downstream end fades into the Lower Fall at its
## arrival point and back again, behind a fade of under a second, and the day,
## tackle and catches come along.
##   godot --headless --path . --script res://tests/world_test.gd

const WORLD := "res://scenes/world.tscn"

var _failures := 0


func _initialize() -> void:
	_test_walk_through.call_deferred()


func _test_walk_through() -> void:
	var world: Node = (load(WORLD) as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var map: WorldMap = world.world
	var upper: Node = world.section
	_check(upper.stretch == map.start, "the game starts in %s" % map.start.display_name)
	_check(upper.angler_pos.distance_to(WorldScale.vec_to_px(map.start.angler_start)) < 1.0, "at its angler start")
	var fishing: Node = upper.fishing()
	var day: int = fishing.day_seed
	fishing.catches.append({"species": load("res://data/fish/redband.tres"), "length_in": 12.0, "fly": null})
	var down: SectionLink = map.links_from(map.start)[0]
	# Close to the end first, as if he'd walked there, so the chunks around
	# him stream in; then the last steps into the exit.
	upper.angler_pos = WorldScale.vec_to_px(down.exit.get_center() - Vector2(0, 4))
	for frame in 90:
		await process_frame
	_check(world.section == upper, "near the end he is still in %s" % map.start.display_name)
	upper.angler_pos = WorldScale.vec_to_px(down.exit.get_center())
	var lower := await _next_section(world, upper)
	_check(lower != null and lower.stretch == down.to, "walking off the end leads to %s" % down.to.display_name)
	if lower == null:
		_finish(world)
		return
	_check(world.FADE_S * 2.0 < 1.0, "the fade out and in takes under a second")
	_check(lower.angler_pos.distance_to(WorldScale.vec_to_px(down.arrive_at)) < 1.0, "he arrives at the link's arrival point")
	_check(lower.fishing().day_seed == day, "the same day carries on")
	_check(lower.fishing().catches.size() == 1, "the catches come along")
	_check(not is_instance_valid(upper) or not upper.is_inside_tree(), "the section left behind is gone")
	var up: SectionLink = map.links_from(down.to)[0]
	lower.angler_pos = WorldScale.vec_to_px(up.exit.get_center())
	var back := await _next_section(world, lower)
	_check(back != null and back.stretch == map.start, "and walking back up leads to %s" % map.start.display_name)
	if back != null:
		_check(back.angler_pos.distance_to(WorldScale.vec_to_px(up.arrive_at)) < 1.0, "arriving near its downstream end")
		_check(back.fishing().day_seed == day, "still the same day")
	_finish(world)


## Waits for the world to swap `from` for another section and finish fading
## in, up to 20 s (the placeholder Lower Fall builds whole, behind the black).
func _next_section(world: Node, from: Node) -> Node:
	var until := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < until:
		await process_frame
		if world.section != from and world.section.is_inside_tree() and not world.get(&"_swapping"):
			return world.section
	return null


func _finish(world: Node) -> void:
	world.queue_free()
	await process_frame
	if _failures == 0:
		print("World tests passed.")
		quit(0)
	else:
		printerr("%d world test(s) failed." % _failures)
		quit(1)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		printerr("  FAIL ", what)
