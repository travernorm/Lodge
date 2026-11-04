extends SceneTree
## Headless smoke test: every input action exists and the main scene runs.
##   godot --headless --path . --script res://tests/smoke_test.gd

const FRAMES := 30
const REQUIRED_ACTIONS := [
	"move_left", "move_right", "move_up", "move_down",
	"rod_left", "rod_right", "rod_up", "rod_down",
	"cast_back", "cast_forward", "mend", "interact", "change_fly", "back", "pause", "toggle_debug", "practice_mode", "cycle_rules",
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
	# The demo stretch (REQ-0002): the head riffle runs faster than the first pool.
	var river: RiverField = main.river
	if main.get(&"stretch") == null or river.stretch == null:
		_fail("main.tscn should load the demo stretch")
		return
	var flow_riffle := river.flow_at(Vector2(12.9, 18.4)).length()
	var flow_pool := river.flow_at(Vector2(57.8, 43.1)).length()
	if not (flow_riffle > flow_pool and flow_pool > 0.0):
		_fail("Riffle should run faster than the pool (riffle %.2f, pool %.2f m/s)" % [flow_riffle, flow_pool])
		return
	if river.flow_at(Vector2(60, 5)) != Vector2.ZERO:
		_fail("Bank should have no current")
		return

	# Every node script compiled (a parse error leaves the node without its methods).
	var cast := main.get_node_or_null(^"Cast")
	if cast == null or not cast.has_method(&"rod_pose"):
		_fail("Cast controller script did not load")
		return

	# Make the stream's trout certain to bite and put it where the cast will land.
	var fishing := main.get_node_or_null(^"Fishing")
	if fishing == null or not fishing.has_method(&"current_fly"):
		_fail("Fishing controller script did not load")
		return
	fishing.stock(null, 7)  # the same day and fish every run (REQ-0007)
	if fishing.fish.size() != 5:
		_fail("Expected five trout in the stretch, found %d" % fishing.fish.size())
		return
	var trout: Fish = fishing.fish[0]
	trout.species = trout.species.duplicate()
	trout.species.bite_chance = 1.0
	trout.species.selectivity = 0.0  # whatever species it is, it takes the tied-on fly
	# Move it under wherever the cast is headed, as the fly leaves the rod.
	cast.model.delivered.connect(func(offset: Vector2, _q: float):
		trout.lie = WorldScale.vec_to_m(main.rod_tip()) + offset
		trout.pos = trout.lie)

	# Play one real cast through the input system: R back cast, overlap into L,
	# hold L, let go, and check the fly lands on the water.
	await _cast_once(cast)
	if cast.model.state != CastModel.State.LANDED:
		_fail("Scripted cast did not land (state %s)" % CastModel.State.keys()[cast.model.state])
		return
	if not main.is_water(cast.fly_pos):
		_fail("Scripted cast landed out of the water at %s" % cast.fly_pos)
		return
	var landing: Vector2 = cast.fly_pos

	# The fly is drifting over the trout. Wait for the bite, set, and fight it
	# through the input system.
	if fishing.phase != 1:  # Phase.DRIFT
		_fail("Fly landed but no drift started")
		return
	if not await _wait_for(cast, func(): return trout.state == Fish.State.TAKEN, 4.0):
		_fail("The trout never took the fly (state %s)" % Fish.State.keys()[trout.state])
		return
	await _wait(cast, trout.species.set_min + 0.05)
	Input.action_press(&"interact")  # Space / A sets the hook
	await _wait(cast, 0.05)
	Input.action_release(&"interact")
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

	# Cast again while the trout is away and strike at nothing: the rod snaps up
	# and the line reels itself in.
	await _wait(cast, 0.3)
	await _cast_once(cast)
	if fishing.phase != 1:
		_fail("Second cast didn't start a drift")
		return
	Input.action_press(&"interact")
	await process_frame
	Input.action_release(&"interact")
	await process_frame
	if fishing.hook_set_pose() == Vector2.ZERO:
		_fail("Setting the hook didn't play the rod animation")
		return
	if not await _wait_for(cast, func(): return cast.model.state == CastModel.State.IDLE and fishing.phase == 0, 2.0):
		_fail("Striking at nothing didn't reel the line in (cast %s, phase %d)" % [
			CastModel.State.keys()[cast.model.state], fishing.phase])
		return

	# Practice mode: T toggles it, fish stop biting, Tab cycles the rule sets.
	var practice := main.get_node_or_null(^"Practice")
	if practice == null or not practice.has_method(&"select_rules"):
		_fail("Practice script did not load")
		return
	await _tap(cast, &"practice_mode")
	if not practice.active or fishing.enabled:
		_fail("Practice toggle didn't turn practice on and fishing off")
		return
	var first_rules: CastRules = cast.model.rules
	await _tap(cast, &"cycle_rules")
	if cast.model.rules == first_rules or cast.model.state != CastModel.State.IDLE:
		_fail("Tab didn't switch the casting rules")
		return
	await _tap(cast, &"practice_mode")
	if practice.active or not fishing.enabled:
		_fail("Practice toggle didn't turn back off")
		return

	print("Smoke test passed: %d input actions, scripted cast landed %s (%s), %s rose, was hooked and landed; an empty strike reeled in." % [
		REQUIRED_ACTIONS.size(), landing.round(), cast.model.presentation, trout.species.display_name])
	print("  practice mode toggles, rules cycle to %s" % cast.model.rules.display_name)
	quit(0)


## One clean cast through the input system: R back cast, overlap into L, let go.
func _cast_once(cast: Node) -> void:
	var ideal: float = cast.model.ideal_stroke_time()
	Input.action_press(&"cast_back")
	await _wait(cast, ideal)
	Input.action_press(&"cast_forward")
	await _wait(cast, 0.08)
	Input.action_release(&"cast_back")
	await _wait(cast, ideal)
	Input.action_release(&"cast_forward")
	await _wait(cast, cast.model.tuning.flight_time + 0.1)


## Wait for the given game time to pass, as measured by the cast controller.
func _wait(cast: Node, seconds: float) -> void:
	var until: float = cast._time + seconds
	while cast._time < until:
		await process_frame


## Presses and releases an action across a couple of frames.
func _tap(cast: Node, action: StringName) -> void:
	Input.action_press(action)
	await _wait(cast, 0.05)
	Input.action_release(action)
	await _wait(cast, 0.05)


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
