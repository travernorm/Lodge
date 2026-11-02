extends SceneTree
## Headless integration playthrough: plays the real main scene through the input
## system, across systems, the way a player would. Where smoke_test.gd checks
## one catch, this one checks that the systems still work together:
##
##   * a catch under EVERY casting rule set in the Practice chassis, both with no
##     false casts and with one, from different spots on the bank
##   * the debug views (controller, read the water) cycled during a drift and a
##     fight without breaking either
##   * practice mode under every rule set: fish never bite, every landing scores
##   * a catch under the bite rules (DriftPastRules, Drift past is the only set)
##   * the mend button (Square / M) mends a drift, like a stick loop
##   * walking only while reeled in, and B reeling in a drift
##
##   godot --headless --path . --script res://tests/playthrough_test.gd
##
## When you add a system (a new screen, menu, fly box, save), add a pass through
## it here so a change elsewhere can't quietly break it.

const MAX_ATTEMPTS := 4  # casts per catch before giving up on a bite

var _main: Node
var _cast: Node
var _fishing: Node
var _practice: Node
var _overlay: Node
var _trout: Fish
var _failed := false


func _initialize() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		_fail("Could not load res://scenes/main.tscn")
		return
	_main = scene.instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	for i in 10:
		await process_frame
	_cast = _main.get_node_or_null(^"Cast")
	_fishing = _main.get_node_or_null(^"Fishing")
	_practice = _main.get_node_or_null(^"Practice")
	_overlay = _main.get_node_or_null(^"DebugLayer/DebugOverlay")
	for pair in [[_cast, &"rod_pose"], [_fishing, &"current_fly"], [_practice, &"select_rules"], [_overlay, &"_draw_water"]]:
		if pair[0] == null or not pair[0].has_method(pair[1]):
			_fail("A node in main.tscn is missing or its script didn't load (%s)" % pair[1])
			return

	# Same rolls every run, and a trout that always bites a fly put on its nose.
	_fishing._rng.seed = 7
	_trout = _fishing.fish[0]
	_trout.species = _trout.species.duplicate()
	_trout.species.bite_chance = 1.0
	# Put the trout wherever the fly is about to land, whatever the rule set.
	_cast.model.delivered.connect(func(_offset: Vector2, _q: float):
		if _trout.state == Fish.State.HOLDING:
			_trout.lie = WorldScale.vec_to_m(_cast._flight_to)
			_trout.pos = _trout.lie)

	# 1. A catch under every rule set, with 0 and 1 false casts, walking between.
	var rule_count: int = _practice.chassis.size()
	if rule_count == 0:
		_fail("Practice has no rule sets in its chassis")
		return
	var catches := 0
	for i in rule_count:
		if not _practice.select_rules(i):
			_fail("Couldn't select rule set %d while reeled in" % i)
			return
		var rules_name: String = _cast.model.rules.display_name
		for false_casts in [0, 1]:
			await _walk(30.0 if (i + false_casts) % 2 == 0 else -30.0)
			if _failed:
				return
			var debug_views: bool = i == 0 and false_casts == 0
			if not await _catch_one(false_casts, debug_views):
				_fail_context("%s, %d false cast(s)" % [rules_name, false_casts])
				return
			catches += 1
			if _fishing.catches.size() != catches:
				_fail("Catch log has %d entries after %d catches" % [_fishing.catches.size(), catches])
				return
			print("  ok    %s, %d false cast(s): caught a %s" % [rules_name, false_casts, _trout.species.display_name])

	# 1b. A catch under the bite rules (Drift past, the only set).
	if not await _catch_one(0, false):
		_fail_context("bite rules %s" % _fishing.take_rules.display_name)
		return
	catches += 1
	print("  ok    bite rules %s: caught a %s" % [_fishing.take_rules.display_name, _trout.species.display_name])

	# 2. B reels in a drift, and you can't walk with line out.
	await _cast_once(0)
	if _fishing.phase != 1:
		_fail("Cast after the catches didn't start a drift")
		return
	var before: float = _main.angler_pos.x
	Input.action_press(&"move_right")
	await _wait(0.3)
	Input.action_release(&"move_right")
	if not is_equal_approx(_main.angler_pos.x, before):
		_fail("Angler walked with line on the water")
		return
	await _tap(&"back")
	if _cast.model.state != CastModel.State.IDLE or _fishing.phase != 0:
		_fail("B didn't reel in the drift (cast %s, phase %d)" % [CastModel.State.keys()[_cast.model.state], _fishing.phase])
		return
	print("  ok    B reels in a drift, no walking with line out")

	# 2a. The mend button flips the belly upstream during a drift.
	if not await _mend_button_pass():
		return

	# 2b. The fly box: Y / F cycles every fly while reeled in and comes back
	# round, and the fly tied on reaches the bite rules (a catch on the Caddis).
	if not await _fly_box_pass():
		return
	catches += 1

	# 3. Practice mode under every rule set: no bites, every landing is scored.
	await _tap(&"practice_mode")
	if not _practice.active or _fishing.enabled:
		_fail("Practice didn't turn on")
		return
	for i in rule_count:
		if not _practice.select_rules(i):
			_fail("Couldn't select rule set %d in practice" % i)
			return
		var scored := _practice_attempts()
		await _cast_once(0)
		if _fishing.phase != 0 or _trout.state != Fish.State.HOLDING:
			_fail("A fish bit, or a drift started, in practice mode (%s)" % _cast.model.rules.display_name)
			return
		if _practice_attempts() != scored + 1:
			_fail("Practice didn't score the landing (%s)" % _cast.model.rules.display_name)
			return
		if not await _wait_for(func(): return _cast.model.state == CastModel.State.IDLE, 3.0):
			_fail("Practice didn't reel the line back in")
			return
	await _tap(&"practice_mode")
	if _practice.active or not _fishing.enabled:
		_fail("Practice didn't turn off")
		return
	print("  ok    practice mode under %d rule set(s): no bites, every landing scored" % rule_count)

	print("Playthrough passed: %d catches across %d rule set(s) under Drift past, debug views, practice and reel-in." % [catches, rule_count])
	quit(0)


## Cycles the whole fly box with Y / F, then catches the trout on the second
## fly (the Elk Hair Caddis, a partial match for the redband) under the default
## bite rules, and ties the first fly back on.
## Square / M mends a drift: the belly flips upstream by the mend shift, the
## same as a right-stick loop. The trout is kept off the fly so a take can't
## block the mend.
func _mend_button_pass() -> bool:
	var chance: float = _trout.species.bite_chance
	_trout.species.bite_chance = 0.0
	await _cast_once(0)
	var ok := true
	if _fishing.phase != 1:
		_fail("Cast for the mend pass didn't start a drift")
		ok = false
	else:
		var before: float = _fishing.drift.bow()
		await _tap(&"mend")
		var after: float = _fishing.drift.bow()
		if after > before - 0.5:  # the line length caps how far a short cast's belly can flip
			_fail("Square / M didn't mend (bow %.2f m -> %.2f m)" % [before, after])
			ok = false
	await _tap(&"back")
	_trout.species.bite_chance = chance
	if ok:
		print("  ok    Square / M mends a drift")
	return ok


func _fly_box_pass() -> bool:
	var count: int = _fishing.flies.size()
	if count < 2:
		_fail("The fly box has %d fly; expected the whole box" % count)
		return false
	var seen := {}
	for i in count:
		seen[_fishing.current_fly().id] = true
		await _tap(&"change_fly")
	if _fishing.fly_index != 0 or seen.size() != count:
		_fail("Y didn't cycle every fly and come back round (%d of %d seen)" % [seen.size(), count])
		return false
	await _tap(&"change_fly")
	var fly: FlyPattern = _fishing.current_fly()
	if not await _catch_one(0, false):
		_fail_context("fly box, %s" % fly.display_name)
		return false
	if _fishing.catches.back().fly != fly:
		_fail("The catch log didn't record the %s" % fly.display_name)
		return false
	for i in count - 1:
		await _tap(&"change_fly")
	if _fishing.fly_index != 0:
		_fail("Couldn't tie the first fly back on")
		return false
	print("  ok    fly box: Y cycles %d flies; caught a %s on the %s" % [count, _trout.species.display_name, fly.display_name])
	return true


## Casts until the trout takes, then sets the hook and lands it. Optionally
## cycles the debug views during the drift and the fight.
func _catch_one(false_casts: int, debug_views: bool) -> bool:
	for attempt in MAX_ATTEMPTS:
		await _cast_once(false_casts)
		if _cast.model.state != CastModel.State.LANDED:
			printerr("  cast didn't land (state %s)" % CastModel.State.keys()[_cast.model.state])
			return false
		if not _main.is_water(_cast.fly_pos):
			printerr("  cast landed out of the water at %s" % _cast.fly_pos)
			return false
		if _fishing.phase != 1:
			printerr("  fly landed but no drift started")
			return false
		if debug_views:
			await _cycle_debug_views()
			if _fishing.phase != 1:
				printerr("  the debug views broke the drift")
				return false
		if await _wait_for(func(): return _trout.state == Fish.State.TAKEN, 3.0):
			break
		await _tap(&"back")  # no take (a Fair or Splashy landing): reel in, try again
		await _wait_for(func(): return _trout.state == Fish.State.HOLDING, 6.0)
	if _trout.state != Fish.State.TAKEN:
		printerr("  no take in %d casts (trout %s)" % [MAX_ATTEMPTS, Fish.State.keys()[_trout.state]])
		return false

	await _wait(_trout.species.set_min + 0.05)
	await _tap(&"interact")
	if _fishing.phase != 2:
		printerr("  hook set didn't start a fight")
		return false
	if debug_views:
		await _cycle_debug_views()
		if _fishing.phase != 2:
			printerr("  the debug views broke the fight")
			return false

	Engine.time_scale = 4.0
	var done := await _wait_for(func():
		if _fishing.phase != 2:
			return true
		var fm: FightModel = _fishing.fight
		_stick(Vector2(-fm.run_dir * 0.4, -0.1) if fm.running else Vector2(0, -0.85))
		return false, 90.0)
	Engine.time_scale = 1.0
	_stick(Vector2.ZERO)
	if not done:
		printerr("  fight never ended")
		return false
	# The trout swims off and comes back before the next cast.
	if not await _wait_for(func(): return _trout.state == Fish.State.HOLDING and _cast.model.state == CastModel.State.IDLE, 10.0):
		printerr("  trout didn't come back (%s) or line not reeled in (%s)" % [
			Fish.State.keys()[_trout.state], CastModel.State.keys()[_cast.model.state]])
		return false
	return true


## A clean cast through the input system with the given number of false casts:
## hold cast_back (L1), overlap into cast_forward (R1), (hold R1, overlap back
## into L1, hold L1, overlap into R1) per false cast, then let go of R1 to deliver.
func _cast_once(false_casts: int) -> void:
	Input.action_press(&"cast_back")
	await _wait(_cast.model.ideal_stroke_time())
	for k in false_casts + 1:
		Input.action_press(&"cast_forward")
		await _wait(0.08)
		Input.action_release(&"cast_back")
		await _wait(_cast.model.ideal_stroke_time())
		if k == false_casts:
			break
		Input.action_press(&"cast_back")
		await _wait(0.08)
		Input.action_release(&"cast_forward")
		await _wait(_cast.model.ideal_stroke_time())
	Input.action_release(&"cast_forward")
	await _wait(_cast.model.tuning.flight_time + 0.1)


func _practice_attempts() -> int:
	var n := 0
	for target in _practice.tally:
		n += _practice.tally[target][1]
	return n


## Walks the angler along the bank (only allowed while reeled in).
func _walk(dx: float) -> void:
	var action := &"move_right" if dx > 0.0 else &"move_left"
	var start: float = _main.angler_pos.x
	Input.action_press(action)
	await _wait_for(func(): return absf(_main.angler_pos.x - start) >= absf(dx), 3.0)
	Input.action_release(action)
	if is_equal_approx(_main.angler_pos.x, start):
		_fail("Angler didn't walk while reeled in")


## Steps the debug overlay through all its views and back to hidden.
func _cycle_debug_views() -> void:
	var views: int = _overlay.View.size()
	for v in views:
		var e := InputEventAction.new()
		e.action = &"toggle_debug"
		e.pressed = true
		Input.parse_input_event(e)
		await _wait(0.1)
		var up := InputEventAction.new()
		up.action = &"toggle_debug"
		Input.parse_input_event(up)
		await _wait(0.05)
	if _overlay.view != 0:
		_fail("Debug views didn't cycle back to hidden (view %d)" % _overlay.view)


## Waits the given game time, as measured by the cast controller.
func _wait(seconds: float) -> void:
	var until: float = _cast._time + seconds
	while _cast._time < until:
		await process_frame


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _wait(0.05)
	Input.action_release(action)
	await _wait(0.05)


func _wait_for(condition: Callable, timeout: float) -> bool:
	var until: float = _cast._time + timeout
	while _cast._time < until:
		if condition.call():
			return true
		await process_frame
	return false


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


func _fail_context(where: String) -> void:
	_fail("Couldn't land a fish with %s (cast %s, fishing phase %d, trout %s)" % [
		where, CastModel.State.keys()[_cast.model.state], _fishing.phase, Fish.State.keys()[_trout.state]])


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	Engine.time_scale = 1.0
	printerr("PLAYTHROUGH FAILED: ", message)
	quit(1)
