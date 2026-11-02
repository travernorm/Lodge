extends SceneTree
## Headless smoke test: every input action exists and the main scene runs.
##   godot --headless --path . --script res://tests/smoke_test.gd

const FRAMES := 30
const REQUIRED_ACTIONS := [
	"move_left", "move_right", "move_up", "move_down",
	"rod_left", "rod_right", "rod_up", "rod_down",
	"cast_back", "cast_forward", "interact", "change_fly", "back", "pause", "toggle_debug",
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
	var landing: Vector2 = cast.fly_pos


	# The fly is drifting. Plant a brook trout just downstream of it, tie on the
	# fly it likes, and play the whole catch through the input system.
	var fishing := main.get_node_or_null(^"Fishing")
	if fishing == null or not fishing.has_method(&"current_fly"):
		_fail("Fishing controller script did not load")
		return
	if fishing.phase != 1:  # Phase.DRIFT
		_fail("Fly landed but no drift started")
		return
	var brook: Fish = null
	for f in fishing.fish:
		if f.species.id == &"brook":
			brook = f
	brook.species = brook.species.duplicate()
	brook.species.take_chance = 1.0
	brook.lie = cast.fly_pos + Vector2(14, 0)
	brook.pos = brook.lie
	brook.state = Fish.State.HOLDING
	for i in fishing.flies.size():
		if fishing.flies[i].id == &"royal_wulff":
			fishing.fly_index = i
	if not await _wait_for(cast, func(): return brook.state == Fish.State.TAKEN, 3.0):
		_fail("Brook trout never took the fly (state %s)" % Fish.State.keys()[brook.state])
		return
	await _wait(cast, brook.species.set_min + 0.05)
	_stick(Vector2(0, -1))  # flick up to set
	await _wait(cast, 0.05)
	if fishing.phase != 2:  # Phase.FIGHT
		_fail("Hook set didn't start a fight")
		return

	Engine.time_scale = 4.0
	var landed := await _wait_for(cast, func():
		if fishing.phase != 2:
			return true
		var fm: FightModel = fishing.fight
		_stick(Vector2(-fm.run_dir * 0.4, -0.1) if fm.running else Vector2(0, -0.85))
		return false, 90.0)
	Engine.time_scale = 1.0
	_stick(Vector2.ZERO)
	if not landed or fishing.catches.size() != 1:
		_fail("Fight didn't end in a catch (catches %d)" % fishing.catches.size())
		return

	print("Smoke test passed: %d input actions, scripted cast landed %s (%s), %s rose, was hooked and landed." % [
		REQUIRED_ACTIONS.size(), landing.round(), cast.model.presentation, brook.species.display_name])
	quit(0)


## Wait for the given game time to pass, as measured by the cast controller.
func _wait(cast: Node, seconds: float) -> void:
	var until: float = cast._time + seconds
	while cast._time < until:
		await process_frame


## Waits until condition returns true, or the timeout (game seconds) passes.
func _wait_for(cast: Node, condition: Callable, timeout: float) -> bool:
	var until: float = cast._time + timeout
	while cast._time < until:
		if condition.call():
			return true
		await process_frame
	return false


## Holds the right stick at v, as analog action strengths.
func _stick(v: Vector2) -> void:
	_axis(&"rod_left", &"rod_right", v.x)
	_axis(&"rod_up", &"rod_down", v.y)


func _axis(negative: StringName, positive: StringName, value: float) -> void:
	Input.action_release(negative)
	Input.action_release(positive)
	if value < 0.0:
		Input.action_press(negative, -value)
	elif value > 0.0:
		Input.action_press(positive, value)


func _fail(message: String) -> void:
	printerr("SMOKE TEST FAILED: ", message)
	quit(1)
