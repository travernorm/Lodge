extends SceneTree
## Headless tests for the tall grass model (REQ-0012): where it grows on the
## demo stretch, and how each variant reacts to the angler walking through.
##   godot --headless --path . --script res://tests/grass_test.gd

const DT := 1.0 / 60.0

var _failures := 0
var _stretch: Stretch = load("res://data/stretches/demo_freestone.tres")
var _look: GrassLook = load("res://data/grass_looks/spring.tres")
var _river := RiverField.new()


func _initialize() -> void:
	_river.build_stretch(_stretch)
	_test_grows_on_land()
	_test_seeded()
	_test_lean()
	_test_trail()
	_test_rustle()
	_test_long_frames()
	_test_wind_on_top()
	if _failures == 0:
		print("Grass tests passed.")
		quit(0)
	else:
		printerr("%d grass test(s) failed." % _failures)
		quit(1)


func _grow(s := 7) -> GrassField:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return GrassField.grow(_river, _look, rng, 3)


## Acceptance: grass appears only inside GrassPatch areas, on land.
func _test_grows_on_land() -> void:
	var f := _grow()
	var patches: Array[GrassPatch] = []
	for feat in _stretch.features:
		if feat is GrassPatch:
			patches.append(feat)
	_check(patches.size() > 0 and f.size() > 100, "grow: the demo stretch has %d patches and %d clumps" % [patches.size(), f.size()])
	var world := Rect2(0.0, _river.top, _river.cols * RiverField.CELL, _river.rows * RiverField.CELL)
	var dist := GrassField.WaterDistance.new(_river, world)
	var in_patch := true
	var dry := true
	var sorted := true
	var kinds := true
	for i in f.size():
		var p := f.pos[i]
		var d := dist.at(p)
		in_patch = in_patch and patches.any(func(g: GrassPatch) -> bool: return g.grows_at(p, d))
		dry = dry and GrassField.is_land(_river, p) and not _river.is_water(p)
		sorted = sorted and (i == 0 or f.pos[i - 1].y <= p.y)
		kinds = kinds and f.kind[i] < 3
	_check(in_patch, "grow: every clump is inside a grass patch")
	_check(dry, "grow: no clump is on or within %.1f m of the water" % GrassField.SHORE_GAP_M)
	_check(sorted, "grow: clumps are in drawing order, top of the screen first")
	_check(kinds, "grow: each clump picks one of the sprites")
	for g in patches:
		if g is GrassBank:
			continue
		var n := 0
		for i in f.size():
			n += 1 if g.contains(f.pos[i]) else 0
		var expected := PI * g.radii.x * g.radii.y * g.density * _look.density
		_check(n > 10 and n < expected * 1.15, "grow: the patch at %s has grass, not doubled where the bank overlaps it (%d clumps, about %d by area)" % [g.centre, n, expected])
	var bank: GrassBank = null
	for g in patches:
		if g is GrassBank:
			bank = g
	_check(bank != null, "bank: the demo stretch has grass along its banks")
	if bank != null:
		var within := true
		var both_sides := {}
		for i in f.size():
			if patches.any(func(g: GrassPatch) -> bool: return not g is GrassBank and g.contains(f.pos[i])):
				continue
			within = within and dist.at(f.pos[i]) <= bank.width_m + 0.01
			var k := _river.nearest_centre(f.pos[i])
			if k >= 0 and k < _river.centre_dir.size():
				both_sides[signf(_river.centre_dir[k].cross(f.pos[i] - _river.centre[k]))] = true
		_check(within, "bank: bank grass stays within %.0f m of the water" % bank.width_m)
		_check(both_sides.size() == 2, "bank: it grows on both banks")
		var land := 0
		var grassy := 0
		for y in range(1, int(_stretch.size_m.y), 2):
			for x in range(1, int(_stretch.size_m.x), 2):
				var p := Vector2(x, y)
				if GrassField.is_land(_river, p) and dist.at(p) <= bank.width_m - 1.0:
					land += 1
					grassy += 1 if _clump_near(f, p, 1.2) else 0
		_check(land > 0 and grassy > land * 0.9, "bank: the bank is mostly grass (%d of %d sample points)" % [grassy, land])


func _clump_near(f: GrassField, p: Vector2, r: float) -> bool:
	for i in range(f.first_at(p.y - r), f.first_at(p.y + r)):
		if f.pos[i].distance_to(p) <= r:
			return true
	return false


func _test_seeded() -> void:
	var a := _grow(7)
	var b := _grow(7)
	var c := _grow(8)
	_check(a.pos == b.pos and a.phase == b.phase, "seed: the same seed grows the same grass")
	_check(a.pos != c.pos, "seed: another seed grows it differently")


## A field of three clumps in a row: left of the angler, right of him, far off.
func _three() -> GrassField:
	var f := GrassField.new()
	f.add(Vector2(9.6, 5), 0, 1.0)
	f.add(Vector2(10.4, 5), 0, 2.0)
	f.add(Vector2(20, 5), 0, 3.0)
	return f


func _run(f: GrassField, seconds: float, angler: Vector2, push: GrassField.Push, look := _look) -> void:
	for i in roundi(seconds / DT):
		f.step(DT, angler, push, look)


## Acceptance: clumps near the angler lean away, far ones don't, and they
## return upright once he leaves, overshooting a little on the way.
func _test_lean() -> void:
	var f := _three()
	_run(f, 0.4, Vector2(10, 5), GrassField.Push.LEAN)
	_check(f.bend[0] < -0.2 and f.bend[1] > 0.2, "lean: clumps either side lean away from the angler (%.2f, %.2f)" % [f.bend[0], f.bend[1]])
	_check(f.bend[2] == 0.0, "lean: a clump 10 m off doesn't move")
	var crossed := false
	for i in roundi(_look.spring_seconds * 2.0 / DT):
		f.step(DT, Vector2(30, 5), GrassField.Push.LEAN, _look)
		crossed = crossed or f.bend[1] < -0.01
	_check(crossed, "lean: it swings back past upright (a little overshoot)")
	_run(f, 3.0, Vector2(30, 5), GrassField.Push.LEAN)
	_check(f.is_still(), "lean: three seconds after he leaves, the grass is still")
	var big := _grow()
	var t0 := Time.get_ticks_usec()
	_run(big, 1.0, big.pos[big.size() / 2], GrassField.Push.LEAN)
	var per_step := (Time.get_ticks_usec() - t0) / 60.0
	_check(not big.is_still(), "lean: on the full stretch, the clumps by the angler move")
	_run(big, 4.0, Vector2(-50, -50), GrassField.Push.LEAN)
	_check(big.is_still(), "lean: and settle once he leaves")
	print("  info  a step over %d clumps takes %.0f us here (only the ones near him are visited)" % [big.size(), per_step])


## B: walked-over clumps lie flat for trail_seconds, then stand back up.
func _test_trail() -> void:
	var f := _three()
	for i in 60:  # walk left to right through both clumps at 1.5 m/s
		f.step(DT, Vector2(8.5 + i * DT * 1.5 * 2.0, 5), GrassField.Push.TRAIL, _look)
	_run(f, 0.1, Vector2(30, 5), GrassField.Push.TRAIL)
	_check(f.flat[0] > 0.5 * _look.flatten and f.flat[1] > 0.5 * _look.flatten, "trail: walked-over clumps lie flat (%.2f, %.2f)" % [f.flat[0], f.flat[1]])
	_check(f.flat[2] == 0.0, "trail: grass he didn't reach stands")
	_run(f, _look.trail_seconds * 0.5, Vector2(30, 5), GrassField.Push.TRAIL)
	_check(f.flat[0] > 0.5 * _look.flatten, "trail: the trail is still there a moment later")
	_run(f, _look.trail_seconds + _look.spring_seconds + 3.0, Vector2(30, 5), GrassField.Push.TRAIL)
	_check(f.flat[0] == 0.0 and f.is_still(), "trail: then it stands back up")
	var lean := _three()
	_run(lean, 0.3, Vector2(10, 5), GrassField.Push.LEAN)
	_run(lean, 0.1, Vector2(30, 5), GrassField.Push.LEAN)
	_check(lean.flat[0] == 0.0, "trail: variant A never flattens")


## C: brushing past shivers the grass more than standing still beside it.
func _test_rustle() -> void:
	var still := _three()
	var walk := _three()
	var still_most := 0.0
	var walk_most := 0.0
	for i in 60:
		still.step(DT, Vector2(10, 5.3), GrassField.Push.RUSTLE, _look)
		walk.step(DT, Vector2(10 + 0.3 * sin(i * 0.4), 5.3), GrassField.Push.RUSTLE, _look)
		still_most = maxf(still_most, absf(still.vel[0]))
		walk_most = maxf(walk_most, absf(walk.vel[0]))
	_check(walk_most > still_most * 2.0, "rustle: walking past shakes it more than standing (%.2f vs %.2f)" % [walk_most, still_most])
	var lean := _three()
	_run(lean, 0.4, Vector2(10, 5), GrassField.Push.LEAN)
	_check(absf(still.bend[0]) < absf(lean.bend[0]), "rustle: it leans less than variant A")


func _test_long_frames() -> void:
	var f := _three()
	f.step(1.0, Vector2(10, 5), GrassField.Push.LEAN, _look)
	f.step(2.5, Vector2(30, 5), GrassField.Push.RUSTLE, _look)
	var ok := true
	for i in f.size():
		ok = ok and is_finite(f.bend[i]) and absf(f.bend[i]) < 2.0
	_check(ok, "frames: a long frame is split into steps and stays stable")


func _test_wind_on_top() -> void:
	var f := _three()
	var c := Conditions.new()
	c.weather = Calendar.Weather.STORM
	c.intensity = 1.0
	var w := Wind.new()
	w.blow_for(c, _look.wind_by_weather)
	w.strength = w.target
	_check(f.sway(2, w, _look) > 0.2, "wind: a storm leans the grass with no one near (%.2f)" % f.sway(2, w, _look))
	_check(f.sway(2, null, _look) == 0.0, "wind: no wind, no lean")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
