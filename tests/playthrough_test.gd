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
##   * the weather debug key (R2 / F2) during a drift: every weather comes round,
##     the fish stay, the drift carries on, and with a debug view open it steps
##     the light round the day (REQ-0009, REQ-0015)
##   * the tall grass (REQ-0012): walking through bends it, and in the debug
##     overlay's Grass view R2 / F2 steps the grass variants, not the weather
##   * the cast look versions (Square / M in practice with the line in): every
##     look comes round, each one casts and lands, and B shows the cutout arm
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

	# Same day, fish and rolls every run (REQ-0007), and a trout that always
	# bites a fly put on its nose.
	_fishing.stock(null, int(OS.get_environment("LODGE_SEED")) if OS.has_environment("LODGE_SEED") else 7)
	_trout = _fishing.fish[0]
	_trout.species = _trout.species.duplicate()
	_trout.species.bite_chance = 1.0
	_trout.species.selectivity = 0.0  # whatever species it is, it takes the tied-on fly
	_trout.resting = false  # and isn't slow to come up for a dry (REQ-0011)
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

	# 2a'. Every mend in a drift feeds out line.
	if not await _mend_feed_pass():
		return

	# 2b. The fly box: Y / F cycles every fly while reeled in and comes back
	# round, and the fly tied on reaches the bite rules (a catch on the Caddis).
	if not await _fly_box_pass():
		return
	catches += 1

	# 2c. Rods: L2 / R cycles every rod, a catch on the second rod, and a rod
	# with no fly to throw won't cast while fishing but casts in practice.
	if not await _rod_pass():
		return
	catches += 1

	# 2d. Weather: R2 / F2 during a drift (REQ-0009).
	if not await _weather_pass():
		return

	# 2e. Tall grass (REQ-0012).
	if not await _grass_pass():
		return

	# 3. Practice mode under every rule set: no bites, every landing is scored.
	await _tap(&"practice_mode")
	if not _practice.active or _fishing.enabled:
		_fail("Practice didn't turn on")
		return
	if not await _cast_look_pass():
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


## Each mend in a drift feeds out line.
func _mend_feed_pass() -> bool:
	var chance: float = _trout.species.bite_chance
	_trout.species.bite_chance = 0.0
	await _cast_once(0)
	var ok := true
	if _fishing.phase != 1:
		_fail("Cast for the mend feed pass didn't start a drift")
		ok = false
	else:
		for i in 2:
			var before: float = _fishing.drift.line_length
			await _tap(&"mend")
			if _fishing.drift.line_length < before + DriftModel.MEND_FEED_MIN - 0.001:
				_fail("Mend %d didn't feed line (%.2f m -> %.2f m)" % [i + 1, before, _fishing.drift.line_length])
				ok = false
				break
	await _tap(&"back")
	_trout.species.bite_chance = chance
	if ok:
		print("  ok    every mend feeds out line")
	return ok


func _fly_box_pass() -> bool:
	var count: int = _fishing.tackle.usable_flies().size()
	if count < 2:
		_fail("The fly box has %d fly; expected the whole box" % count)
		return false
	var seen := {}
	for i in count:
		seen[_fishing.current_fly().id] = true
		await _tap(&"change_fly")
	if _fishing.tackle.fly_index != 0 or seen.size() != count:
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
	if _fishing.tackle.fly_index != 0:
		_fail("Couldn't tie the first fly back on")
		return false
	print("  ok    fly box: Y cycles %d flies; caught a %s on the %s" % [count, _trout.species.display_name, fly.display_name])
	return true


## REQ-0005: L2 / R cycles every rod and comes back round, each rod reaching
## the cast; the trout is caught on the second rod; a rod that throws no fly in
## the box won't start a cast while fishing, but casts in practice.
func _rod_pass() -> bool:
	var tackle: Tackle = _fishing.tackle
	var count := tackle.rods.size()
	if count < 2:
		_fail("The rod rack has %d rod; expected every rod in the catalog" % count)
		return false
	for i in count:
		await _tap(&"change_rod")
		if _cast.model.rod != tackle.rod():
			_fail("The %s didn't reach the cast" % tackle.rod().display_name)
			return false
	if tackle.rod_index != 0:
		_fail("L2 didn't cycle every rod and come back round")
		return false
	await _tap(&"change_rod")
	var rod: FlyRod = tackle.rod()
	if tackle.fly() == null or not await _catch_one(1, false):
		_fail_context("rod %s" % rod.display_name)
		return false
	var bare := ""
	for i in count:
		if tackle.fly() == null:
			bare = tackle.rod().display_name
			break
		await _tap(&"change_rod")
	if bare != "":
		Input.action_press(&"cast_back")
		await _wait(0.2)
		Input.action_release(&"cast_back")
		await _wait(0.1)
		if _cast.model.state != CastModel.State.IDLE:
			_fail("The %s cast with no fly it can throw" % bare)
			return false
		await _tap(&"practice_mode")
		var scored := _practice_attempts()
		await _cast_once(1)
		if _practice_attempts() != scored + 1:
			_fail("The %s didn't cast in practice" % bare)
			return false
		await _wait_for(func(): return _cast.model.state == CastModel.State.IDLE, 3.0)
		await _tap(&"practice_mode")
	while tackle.rod_index != 0:
		await _tap(&"change_rod")
	print("  ok    rods: L2 cycles %d rods; caught a %s on the %s%s" % [count, _trout.species.display_name, rod.display_name,
		"; the %s won't cast with no fly, but casts in practice" % bare if bare != "" else ""])
	return true


## R2 / F2 steps the day's weather round during a drift without touching the
## fish or the drift; with a debug view open it steps the light round the day.
func _weather_pass() -> bool:
	var view: Node = _main.get_node_or_null(^"Weather/WeatherView")
	if view == null or not view.has_method(&"show_conditions"):
		_fail("main.tscn has no Weather/WeatherView, or its script didn't load")
		return false
	var start: Conditions = _fishing.conditions
	var fish_before: Array = _fishing.fish.duplicate()
	_trout.species.bite_chance = 0.0  # keep the fly free while the weather turns
	await _cast_once(0)
	if not await _wait_for(func(): return _fishing.phase == 1, 3.0):
		_fail("No drift to turn the weather in")
		return false
	var seen := {}
	for i in WeatherMix.DEBUG_STEPS.size():
		await _press_event(Controls.DEBUG_WEATHER)
		var c: Conditions = _fishing.conditions
		seen[c.weather] = true
		if view.conditions != c or c.season != start.season or c.day != start.day or c.slot != start.slot:
			_fail("R2 / F2 didn't hand the weather view the same day with a new weather")
			return false
	if seen.size() != Calendar.Weather.size() or WeatherMix.debug_step(_fishing.conditions) != WeatherMix.debug_step(start):
		_fail("R2 / F2 didn't step through every weather and come back round (saw %d)" % seen.size())
		return false
	var same_fish: bool = _fishing.fish.size() == fish_before.size()
	for i in fish_before.size():
		same_fish = same_fish and _fishing.fish[i] == fish_before[i]
	if not same_fish or _fishing.phase != 1:
		_fail("Turning the weather restocked the fish or ended the drift")
		return false
	await _press_event(&"toggle_debug")
	var weather: Calendar.Weather = _fishing.conditions.weather
	var time_before: float = view.sky.day_time
	var scrubs := int(Calendar.Slot.size() / WeatherMix.SCRUB_SLOTS)
	for i in scrubs:
		await _press_event(Controls.DEBUG_WEATHER)
	await _cycle_debug_views_closed()
	if absf(view.sky.day_time - time_before) > 0.1 or _fishing.conditions.weather != weather:
		_fail("With a debug view open, R2 / F2 didn't step the light round the day (%.2f to %.2f)" % [time_before, view.sky.day_time])
		return false
	await _tap(&"back")
	await _wait_for(func(): return _cast.model.state == CastModel.State.IDLE, 3.0)
	_trout.species.bite_chance = 1.0
	print("  ok    weather: R2 / F2 stepped %d days through every weather in a drift, fish kept; %d steps of light round the day" % [
		WeatherMix.DEBUG_STEPS.size(), scrubs])
	return true


## REQ-0012: the stretch grows grass, walking through it bends the clumps, and
## in the debug overlay's Grass view R2 / F2 steps the grass variants round
## while the weather and its look version stay put.
func _grass_pass() -> bool:
	var grass: Node = _main.get_node_or_null(^"Grass")
	if grass == null or not grass.has_method(&"angler_at"):
		_fail("main.tscn has no Grass node, or its script didn't load")
		return false
	if _overlay.View.GRASS != GrassView.DEBUG_VIEW or _overlay.View.GRASS != WeatherView.GRASS_DEBUG_VIEW:
		_fail("GrassView.DEBUG_VIEW and WeatherView.GRASS_DEBUG_VIEW must match the overlay's Grass view")
		return false
	var field: GrassField = grass.field
	if field.size() == 0:
		_fail("The demo stretch grew no grass")
		return false
	var home: Vector2 = _main.angler_pos
	var start := WorldScale.vec_to_m(home)
	var nearest := 0
	for i in field.size():
		if field.pos[i].distance_to(start) < field.pos[nearest].distance_to(start):
			nearest = i
	_main.angler_pos = WorldScale.vec_to_px(field.pos[nearest] + Vector2(-1.0, 0.0))
	await _walk(16.0)
	if _failed or field.is_still():
		_fail("Walking through the grass didn't bend it")
		return false
	_main.angler_pos = home
	var weather: Calendar.Weather = _fishing.conditions.weather
	var light: float = _main.get_node(^"Weather/WeatherView").sky.day_time
	var first: GrassField.Push = grass.push
	while _overlay.view != _overlay.View.GRASS:
		await _press_event(&"toggle_debug")
	var seen := {}
	for i in GrassField.Push.size():
		await _press_event(Controls.DEBUG_WEATHER)
		seen[grass.push] = true
	await _cycle_debug_views_closed()
	if seen.size() != GrassField.Push.size() or grass.push != first:
		_fail("In the Grass view, R2 / F2 didn't step the grass variants round (saw %d)" % seen.size())
		return false
	if _fishing.conditions.weather != weather or absf(_main.get_node(^"Weather/WeatherView").sky.day_time - light) > 0.1:
		_fail("In the Grass view, R2 / F2 also changed the weather or the light")
		return false
	print("  ok    grass: %d clumps, walking bends them, R2 / F2 steps %d variants in the Grass view" % [
		field.size(), GrassField.Push.size()])
	return true


## Presses and releases an action as input events, for nodes that listen in
## _unhandled_input.
func _press_event(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await _wait(0.1)
	var up := InputEventAction.new()
	up.action = action
	Input.parse_input_event(up)
	await _wait(0.05)


## Steps the debug overlay on until it's hidden again.
func _cycle_debug_views_closed() -> void:
	while _overlay.view != 0:
		await _press_event(&"toggle_debug")


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
	# A landed trout is out of the water for the rest of the session.
	if _trout.state != Fish.State.CAUGHT or _trout.is_present():
		printerr("  the landed trout is still in the water (%s)" % Fish.State.keys()[_trout.state])
		return false
	await _wait(Fish.GONE_TIME + 0.5)
	if _trout.state != Fish.State.CAUGHT:
		printerr("  the landed trout came back (%s)" % Fish.State.keys()[_trout.state])
		return false
	if not await _wait_for(func(): return _cast.model.state == CastModel.State.IDLE, 10.0):
		printerr("  line not reeled in (%s)" % CastModel.State.keys()[_cast.model.state])
		return false
	# The stretch holds only a few trout and this run lands more than that, so
	# the test puts its tame trout back for the next catch.
	_trout.respawn()
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


## In practice with the line in, Square / M steps through every cast look and
## back round. Each look casts and lands; during B's cast the angler shows the
## cutout forearm and the rod tip sits on one of B's fixed angles.
func _cast_look_pass() -> bool:
	var start: int = _cast.look_style
	var angler: AnglerView = _main._angler
	for k in CastLook.Style.size():
		var scored := _practice_attempts()
		var saw_arm := [false]
		var watch := func():
			if angler.shows_arm():
				saw_arm[0] = true
		process_frame.connect(watch)
		await _cast_once(0)
		process_frame.disconnect(watch)
		if _practice_attempts() != scored + 1:
			_fail("Cast look %s: the cast didn't land" % CastLook.style_name(_cast.look_style))
			return false
		if saw_arm[0] != (_cast.look_style == CastLook.Style.CUTOUT):
			_fail("Cast look %s: the cutout arm showed %s" % [CastLook.style_name(_cast.look_style), saw_arm[0]])
			return false
		if not await _wait_for(func(): return _cast.model.state == CastModel.State.IDLE, 3.0):
			_fail("Practice didn't reel the line back in")
			return false
		var before: int = _cast.look_style
		await _tap(&"mend")
		if _cast.look_style != (before + 1) % CastLook.Style.size():
			_fail("Square / M in practice didn't step the cast look (still %d)" % _cast.look_style)
			return false
	if _cast.look_style != start:
		_fail("The cast looks didn't come back round")
		return false
	print("  ok    cast looks: %d versions stepped with Square / M, each cast and landed" % CastLook.Style.size())
	return true


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
