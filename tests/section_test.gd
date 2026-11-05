extends SceneTree
## Headless tests for a river built in chunks (REQ-0014, SectionField): the
## chunks match a whole build of the same stretch, seams included; they build
## a little per step without long pauses; far chunks can be dropped and come
## back the same; lies are picked across chunk edges; and the Upper Fall scene
## streams its chunks around the walking angler.
##   godot --headless --path . --script res://tests/section_test.gd

const STRETCH := "res://data/stretches/demo_freestone.tres"
const UPPER_FALL := "res://data/stretches/fall_river_upper_fall.tres"
const SCENE := "res://scenes/upper_fall.tscn"
## How close a chunk's water must be to the whole build's. Features far from a
## chunk are left out of it (RiverFeature.reach()), which moves the current by
## well under 2%.
const SPEED_TOLERANCE := 0.02 * RiverField.WATER_SPEED
const LAYER_TOLERANCE := 0.02
## The longest one step (a row of one stage) may take (ms). Headless CI is
## slower than the Deck; the scene runs as many steps as fit in its budget.
const STEP_MS := 8.0

var _failures := 0


func _initialize() -> void:
	var st: Stretch = load(STRETCH)
	var whole := RiverField.new()
	whole.build_stretch(st)
	var sec := SectionField.new()
	sec.setup(st)
	_test_chunks_match_whole(whole, sec)
	_test_seams_match(whole, sec)
	_test_building_in_steps(st)
	_test_drop_and_rebuild(sec)
	_test_lies_across_chunks(sec)
	_test_long_section(load(UPPER_FALL))
	_test_falls_and_bridge(load(UPPER_FALL))
	_test_scene_streams.call_deferred()


func _finish() -> void:
	if _failures == 0:
		print("Section tests passed.")
		quit(0)
	else:
		printerr("%d section test(s) failed." % _failures)
		quit(1)


## Every 0.75 m over the stretch: water, speed, depth, seams and lies agree.
func _test_chunks_match_whole(whole: RiverField, sec: SectionField) -> void:
	var worst := _compare(whole, sec, Rect2(Vector2.ZERO, sec.bounds().size), 0.75)
	_check(worst[0] == 0, "chunks are wet exactly where the whole build is (%d cells differ)" % worst[0])
	_check(worst[1] <= SPEED_TOLERANCE, "chunk current matches the whole build (worst %.3f m/s)" % worst[1])
	_check(worst[2] <= LAYER_TOLERANCE, "chunk depth, seams and lies match (worst %.3f)" % worst[2])


## Along every chunk edge, on the whole 0.25 m grid and just either side.
func _test_seams_match(whole: RiverField, sec: SectionField) -> void:
	var n := sec.key_count()
	var worst := [0, 0.0, 0.0]
	for x in range(1, n.x):
		var edge := x * SectionField.CHUNK.x
		var w := _compare(whole, sec, Rect2(edge - 0.5, 0.0, 1.0, sec.bounds().size.y), RiverField.CELL)
		worst = [worst[0] + w[0], maxf(worst[1], w[1]), maxf(worst[2], w[2])]
	for y in range(1, n.y):
		var edge := y * SectionField.CHUNK.y
		var w := _compare(whole, sec, Rect2(0.0, edge - 0.5, sec.bounds().size.x, 1.0), RiverField.CELL)
		worst = [worst[0] + w[0], maxf(worst[1], w[1]), maxf(worst[2], w[2])]
	_check(worst[0] == 0, "no wet/dry step at the seams (%d cells differ)" % worst[0])
	_check(worst[1] <= SPEED_TOLERANCE, "the current matches across seams (worst %.3f m/s)" % worst[1])
	_check(worst[2] <= LAYER_TOLERANCE, "depth, seams and lies match across seams (worst %.3f)" % worst[2])
	# Sampling at the very edge reads the same from either side.
	var p := Vector2(SectionField.CHUNK.x, 0.0)
	var a := sec.chunk(sec.key_of(p - Vector2(0.01, 0))) as RiverField
	var b := sec.chunk(sec.key_of(p + Vector2(0.01, 0))) as RiverField
	var gap := 0.0
	for y in range(0, int(sec.bounds().size.y), 1):
		var q := Vector2(p.x, y + 0.5)
		gap = maxf(gap, (a.flow_at(q) - b.flow_at(q)).length())
	_check(gap <= SPEED_TOLERANCE, "the chunks either side of a seam agree on it (worst %.3f m/s)" % gap)


## [cells whose wetness differs, worst speed gap, worst other-layer gap].
func _compare(whole: RiverField, sec: SectionField, area: Rect2, step: float) -> Array:
	var wet_diff := 0
	var speed := 0.0
	var layer := 0.0
	var y := area.position.y
	while y <= area.end.y:
		var x := area.position.x
		while x <= area.end.x:
			var p := Vector2(x, y)
			if sec.bounds().has_point(p):
				if whole.is_water(p) != sec.is_water(p):
					wet_diff += 1
				speed = maxf(speed, (whole.flow_at(p) - sec.flow_at(p)).length())
				layer = maxf(layer, absf(whole.depth_at(p) - sec.depth_at(p)))
				layer = maxf(layer, absf(whole.seam_at(p) - sec.seam_at(p)))
				layer = maxf(layer, absf(whole.lie_at(p) - sec.lie_at(p)))
			x += step
		y += step
	return [wet_diff, speed, layer]


## Chunks wanted around a view come out a little per step, nearest first, and
## no step runs far past its budget.
func _test_building_in_steps(st: Stretch) -> void:
	var sec := SectionField.new()
	sec.setup(st)
	var view := Rect2(Vector2(40, 25), Vector2(40, 25))
	sec.want(view.grow(10.0))
	var first := SectionField.NONE
	var worst_ms := 0.0
	var steps := 0
	while sec.busy() and steps < 100000:
		var t := Time.get_ticks_usec()
		var done := sec.step()
		worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - t) / 1000.0)
		if first == SectionField.NONE:
			first = done
		steps += 1
	_check(not sec.busy(), "every wanted chunk gets built")
	_check(first == sec.key_of(view.get_center()), "the chunk under the view is built first (%s)" % first)
	_check(steps > 100, "building is spread over many steps (%d)" % steps)
	_check(worst_ms <= STEP_MS, "no step runs long (worst %.1f ms)" % worst_ms)
	_check(sec.built_keys().size() == 9, "a view plus a margin wants the 9 chunks around it (%d)" % sec.built_keys().size())


func _test_drop_and_rebuild(sec: SectionField) -> void:
	var p := Vector2(100, 60)
	var before := sec.flow_at(p)
	var gone := sec.drop_outside(Rect2(0, 0, 40, 25))
	_check(not gone.is_empty() and not sec.is_built(sec.key_of(p)), "far chunks are dropped")
	_check(sec.is_built(Vector2i.ZERO), "chunks inside the kept area stay")
	_check(sec.flow_at(p) == before, "a dropped chunk comes back the same")


## pick_lie() over an area that spans chunks finds lies on both sides.
func _test_lies_across_chunks(sec: SectionField) -> void:
	var area := Rect2(Vector2.ZERO, sec.bounds().size)
	var keys := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for n in 60:
		var p := sec.pick_lie(area, rng, 0.3)
		if p != Vector2.INF:
			keys[sec.key_of(p)] = true
			if sec.lie_at(p) < 0.25:
				_check(false, "picked lie at %s scores %.2f" % [p, sec.lie_at(p)])
				return
	_check(keys.size() >= 3, "lies are picked from several chunks (%d)" % keys.size())
	var best := sec.best_lie()
	_check(best.z > 0.5, "the best lie across the built chunks is a good one (%.2f)" % best.z)


## The Upper Fall (about 500 m) streams in chunks: a chunk takes a fraction of
## the whole build, and the river is wet where its centreline runs.
func _test_long_section(st: Stretch) -> void:
	var sec := SectionField.new()
	sec.setup(st)
	var t := Time.get_ticks_msec()
	var mid := sec.centre[sec.centre.size() / 2]
	_check(sec.is_water(mid), "the Upper Fall's middle is water")
	var ms := Time.get_ticks_msec() - t
	_check(sec.built_keys().size() == 1, "asking about one point builds one chunk")
	var n := sec.key_count()
	_check(n.x * n.y >= 40, "the Upper Fall is many chunks (%d)" % (n.x * n.y))
	print("  one Upper Fall chunk built in %d ms" % ms)
	var dry := 0
	for k in range(0, sec.centre.size(), 25):
		if sec.bounds().has_point(sec.centre[k]) and not sec.is_solid(sec.centre[k]) and not sec.is_water(sec.centre[k]):
			dry += 1
	_check(dry == 0, "the river is wet along its whole centreline, boulders aside (%d dry points)" % dry)


## The Upper Fall opens under a waterfall with a footbridge below it: nothing
## above the lip can be walked on, fished or cast to; the deck can be walked
## across from bank to bank over running water.
func _test_falls_and_bridge(st: Stretch) -> void:
	var sec := SectionField.new()
	sec.setup(st)
	var fall: Waterfall = null
	var bridge: Bridge = null
	for f in st.features:
		if f is Waterfall:
			fall = f
		elif f is Bridge:
			bridge = f
	_check(fall != null and bridge != null, "the Upper Fall has a waterfall and a footbridge")
	if fall == null or bridge == null:
		return
	var lip := fall.a.lerp(fall.b, 0.5)
	var blocked := 0
	var tried := 0
	for across in range(-12, 13, 3):
		for up in [2.0, 4.0, 6.0]:
			var p: Vector2 = lip - fall.down * up + Vector2(-fall.down.y, fall.down.x) * across
			if sec.bounds().has_point(p):
				tried += 1
				if not sec.is_water(p) and not Footing.can_stand(sec, p) and sec.lie_at(p) == 0.0:
					blocked += 1
	_check(tried > 0 and blocked == tried, "above the lip is no water, no footing and no lies (%d of %d)" % [blocked, tried])
	var below := lip + fall.down * (Waterfall.FALL_M + 2.0)
	_check(sec.is_water(below), "the plunge pool below the falls is water")
	var mid := bridge.a.lerp(bridge.b, 0.5)
	_check(sec.is_water(mid) and sec.flow_at(mid).length() > 0.1, "the river runs under the bridge")
	_check(Footing.can_stand(sec, mid) and Footing.on_deck(sec, mid), "the angler can stand on the deck over the water")
	_check(not Footing.can_stand(sec, mid + (bridge.b - bridge.a).orthogonal().normalized() * (bridge.width_m + 1.0)),
		"beside the deck is water again")
	# Walk him across, from the left-bank end to the right-bank end.
	var walker := Angler.new()
	var start := WorldScale.vec_to_px(bridge.a + (bridge.b - bridge.a).normalized() * 0.5)
	walker.setup(sec, WorldScale.vec_to_px(st.size_m), true, start)
	var dir := (bridge.b - bridge.a).normalized()
	var wet_steps := 0
	for frame in 60 * 6:
		walker.step(1.0 / 60.0, dir, true)
		var m := WorldScale.vec_to_m(walker.feet)
		if sec.is_water(m) and not Footing.on_deck(sec, m):
			wet_steps += 1
	var end_m := WorldScale.vec_to_m(walker.feet)
	_check(end_m.distance_to(bridge.b) < end_m.distance_to(bridge.a) and not sec.is_water(end_m),
		"he walks across the bridge to the far bank (ends %.1f m from it)" % end_m.distance_to(bridge.b))
	_check(wet_steps == 0, "he never steps into the water on the way")
	walker.free()


## The Upper Fall scene streams: the chunks on screen are painted at load,
## walking down the bank at walking speed shows each new chunk before it is on
## screen, the water and grass views get every chunk, and far chunks go.
func _test_scene_streams() -> void:
	var main: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var river: SectionField = main.river
	var streamer: RiverStreamer = main.get(&"_streamer")
	_check(streamer != null, "a streamed stretch gets a streamer")
	_check(_on_screen_shown(main, river, streamer), "the chunks on screen are painted at load")
	var water: WaterView = main.get_node(^"Water")
	var grass: GrassView = main.get_node(^"Grass")
	var k := float(river.nearest_centre(WorldScale.vec_to_m(main.angler_pos)))
	var start_key := river.key_of(WorldScale.vec_to_m(main.angler_pos))
	var unpainted := 0
	var keys_seen := {}
	for frame in 60 * 12:
		k = minf(k + Angler.SPEED / WorldScale.PX_PER_M / 60.0, river.centre.size() - 1)
		var c := river.centre[int(k)]
		var left := Vector2(river.centre_dir[int(k)].y, -river.centre_dir[int(k)].x)
		main.angler_pos = WorldScale.vec_to_px(c + left * (river.channel.half_width + 2.5))
		await process_frame
		if not _on_screen_shown(main, river, streamer):
			unpainted += 1
		keys_seen[river.key_of(WorldScale.vec_to_m(main.angler_pos))] = true
	_check(keys_seen.size() >= 3, "the walk crosses chunk seams (%d chunks)" % keys_seen.size())
	_check(unpainted == 0, "walking at walking speed, every chunk on screen is painted (%d frames short)" % unpainted)
	var shown := streamer.shown_keys()
	_check(water.get_child_count() >= shown.size(), "the water view paints every chunk on show")
	_check(grass.chunks.size() == shown.size(), "the grass view has every chunk on show (%d of %d)" % [grass.chunks.size(), shown.size()])
	_check(not river.is_built(start_key) or river.chunk_rect(start_key).intersects(
		Rect2(WorldScale.vec_to_m(main.visible_rect().position), WorldScale.vec_to_m(main.visible_rect().size)).grow(RiverStreamer.KEEP_M)),
		"chunks far behind are dropped")
	main.queue_free()
	await process_frame
	_finish()


func _on_screen_shown(main: Node, river: SectionField, streamer: RiverStreamer) -> bool:
	var view: Rect2 = main.visible_rect()
	var m := Rect2(WorldScale.vec_to_m(view.position), WorldScale.vec_to_m(view.size)).intersection(river.bounds())
	var shown := streamer.shown_keys()
	for key in [river.key_of(m.position), river.key_of(m.end - Vector2(0.01, 0.01)),
			river.key_of(Vector2(m.position.x, m.end.y - 0.01)), river.key_of(Vector2(m.end.x - 0.01, m.position.y))]:
		if not key in shown:
			return false
	return true


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		printerr("  FAIL ", what)
