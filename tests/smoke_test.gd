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
	print("Smoke test passed: %d frames, %d input actions." % [FRAMES, REQUIRED_ACTIONS.size()])
	quit(0)


func _fail(message: String) -> void:
	printerr("SMOKE TEST FAILED: ", message)
	quit(1)
