extends SceneTree
## Headless smoke test: every input action exists and the main scene runs.
##   godot --headless --path . --script res://tests/smoke_test.gd

const FRAMES := 30
const REQUIRED_ACTIONS := [
	"move_left", "move_right", "move_up", "move_down",
	"rod_left", "rod_right", "rod_up", "rod_down",
	"cast_back", "cast_forward", "interact", "back", "pause", "toggle_debug",
]


func _initialize() -> void:
	var missing: Array[String] = []
	for action in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			missing.append(action)
	if not missing.is_empty():
		_fail("Missing input actions: %s. Run tools/setup_input_map.gd." % ", ".join(missing))
		return

	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		_fail("Could not load res://scenes/main.tscn")
		return
	var main := scene.instantiate()
	root.add_child(main)
	_run.call_deferred(main)


func _run(main: Node) -> void:
	for i in FRAMES:
		await process_frame
	var flow_riffle: Vector2 = main.flow_at(Vector2(40, 103))
	var flow_pool: Vector2 = main.flow_at(Vector2(280, 103))
	if not (flow_riffle.x > flow_pool.x and flow_pool.x > 0.0):
		_fail("Riffle should run faster than the pool (riffle %s, pool %s)" % [flow_riffle, flow_pool])
		return
	if main.flow_at(Vector2(160, 20)) != Vector2.ZERO:
		_fail("Bank should have no current")
		return

	# Every node script compiled (a parse error leaves the node without its methods).
	var cast := main.get_node_or_null(^"Cast")
	if cast == null or not cast.has_method(&"rod_pose"):
		_fail("Cast controller script did not load")
		return

	# Play one real cast through the input system: R back cast, overlap into L,
	# hold L, let go, and check the fly lands on the water.
	var ideal: float = cast.model.tuning.base_stroke_time + cast.model.tuning.line_start * cast.model.tuning.stroke_time_per_px
	Input.action_press(&"cast_back")
	await _wait(cast, ideal)
	Input.action_press(&"cast_forward")
	await _wait(cast, 0.08)
	Input.action_release(&"cast_back")
	await _wait(cast, ideal)
	Input.action_release(&"cast_forward")
	await _wait(cast, cast.model.tuning.flight_time + 0.1)
	if cast.model.state != CastModel.State.LANDED:
		_fail("Scripted cast did not land (state %s)" % CastModel.State.keys()[cast.model.state])
		return
	if not main.is_water(cast.fly_pos):
		_fail("Scripted cast landed out of the water at %s" % cast.fly_pos)
		return

	print("Smoke test passed: %d input actions, scene runs, scripted cast landed %s (%s)." % [
		REQUIRED_ACTIONS.size(), cast.fly_pos.round(), cast.model.presentation])
	quit(0)


## Wait for the given game time to pass, as measured by the cast controller.
func _wait(cast: Node, seconds: float) -> void:
	var until: float = cast._time + seconds
	while cast._time < until:
		await process_frame


func _fail(message: String) -> void:
	printerr("SMOKE TEST FAILED: ", message)
	quit(1)
