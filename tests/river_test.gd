extends SceneTree
## Headless tests for the river field: the current follows the hydraulic rules
## in the river design doc. Everything is in metres and m/s (REQ-0001); the
## test reach is one screen, 40 m long with about 11 m of water.
##   godot --headless --path . --script res://tests/river_test.gd

const TOP := 7.25
const BOTTOM := 18.5
const WIDTH := 40.0
const THALWEG := 13.75
const RIFFLE_X := 5.0
const POOL_X := 35.0
const ROCK := Vector3(20, 12.5, 0.625)
const STRETCH := "res://data/stretches/demo_freestone.tres"

var _failures := 0


func _initialize() -> void:
	_test_thalweg_is_fastest()
	_test_riffle_faster_than_pool()
	_test_flow_is_conserved()
	_test_bank_and_rock_are_dry()
	_test_boulder_cushion_pocket_and_seams()
	_test_trout_hold_behind_the_boulder()
	_test_test_stream_uses_the_field()
	_test_one_water_speed()
	# The demo stretch (REQ-0002): a winding 16 m river.
	var st: Stretch = load(STRETCH)
	var f := RiverField.new()
	f.build_stretch(st)
	_test_stretch_shape(f, st)
	_test_bend_puts_deep_water_outside(f)
	_test_stretch_boulders(f, st)
	_test_eddy_circulates(f, st)
	_test_trout_spread_over_the_stretch(f, st)
	_test_field_matches_fixture(f)
	_test_a_new_feature_is_one_entry(st)
	if _failures == 0:
		print("River tests passed.")
		quit(0)
	else:
		printerr("%d river test(s) failed." % _failures)
		quit(1)


func _thalweg_y(_x: float) -> float:
	return THALWEG


## Shallow riffle on the left, deep pool on the right.
func _thalweg_depth(x: float) -> float:
	return lerpf(0.35, 1.0, smoothstep(12.5, 22.5, x))


func _field(rocks: Array[Vector3] = []) -> RiverField:
	var r := RiverField.new()
	r.build(TOP, BOTTOM, WIDTH, _thalweg_y, _thalweg_depth, rocks)
	return r


func _test_thalweg_is_fastest() -> void:
	var r := _field()
	var x := RIFFLE_X
	var on_line := r.flow_at(Vector2(x, THALWEG)).length()
	var fastest := 0.0
	var fastest_y := 0.0
	var y := TOP
	while y <= BOTTOM:
		var s := r.flow_at(Vector2(x, y)).length()
		if s > fastest:
			fastest = s
			fastest_y = y
		y += 0.125
	_check(absf(fastest_y - THALWEG) <= 0.25, "fastest water sits on the thalweg (y %.2f m)" % fastest_y)
	var far_edge := r.flow_at(Vector2(x, TOP + 0.375)).length()
	var near_edge := r.flow_at(Vector2(x, BOTTOM - 0.375)).length()
	_check(far_edge < on_line * 0.4 and near_edge < on_line * 0.4,
		"banks are slow (edges %.1f, %.1f vs %.1f m/s)" % [far_edge, near_edge, on_line])
	_check(absf(r.flow_at(Vector2(x, THALWEG)).y) < 0.01, "a straight reach flows straight downstream")
	_check(is_equal_approx(on_line, RiverField.WATER_SPEED), "the riffle thalweg runs at WATER_SPEED (%.2f m/s)" % on_line)


func _test_riffle_faster_than_pool() -> void:
	var r := _field()
	var riffle := r.flow_at(Vector2(RIFFLE_X, THALWEG)).length()
	var pool := r.flow_at(Vector2(POOL_X, THALWEG)).length()
	_check(riffle > pool * 2.0, "shallow riffle runs much faster than the deep pool (%.1f vs %.1f m/s)" % [riffle, pool])


func _test_flow_is_conserved() -> void:
	var r := _field()
	var riffle := _discharge(r, RIFFLE_X)
	var pool := _discharge(r, POOL_X)
	_check(absf(riffle - pool) / riffle < 0.03, "the same water passes the riffle and the pool (%.1f vs %.1f)" % [riffle, pool])


func _discharge(r: RiverField, x: float) -> float:
	var q := 0.0
	var y := TOP
	while y <= BOTTOM:
		q += r.flow_at(Vector2(x, y)).x * r.depth_at(Vector2(x, y))
		y += 0.0625
	return q


func _test_bank_and_rock_are_dry() -> void:
	var r := _field([ROCK])
	_check(r.flow_at(Vector2(12.5, TOP - 0.625)) == Vector2.ZERO, "no current on the far bank")
	_check(r.flow_at(Vector2(12.5, BOTTOM + 0.625)) == Vector2.ZERO, "no current on the near bank")
	_check(not r.is_water(Vector2(ROCK.x, ROCK.y)), "the boulder is not water")
	_check(r.flow_at(Vector2(ROCK.x + 0.125, ROCK.y)) == Vector2.ZERO, "no current inside the boulder")


func _test_boulder_cushion_pocket_and_seams() -> void:
	var open := _field()
	var r := _field([ROCK])
	var c := Vector2(ROCK.x, ROCK.y)
	var rad := ROCK.z
	var free := open.flow_at(c).length()
	var cushion := r.flow_at(c + Vector2(-rad - 0.25, 0)).length()
	var pocket := r.flow_at(c + Vector2(rad + 0.5, 0)).length()
	var beside := r.flow_at(c + Vector2(0, rad + 0.25)).length()
	_check(cushion < free * 0.6, "a slow cushion in front of the boulder (%.1f vs %.1f m/s)" % [cushion, free])
	_check(pocket < free * 0.3, "a slack pocket behind the boulder (%.1f vs %.1f m/s)" % [pocket, free])
	_check(beside > free, "water speeds up around the boulder's sides (%.1f vs %.1f m/s)" % [beside, free])
	var curl := r.flow_at(c + Vector2(rad + 0.125, 0)).x
	_check(curl < 0.0625, "a little back-flow right behind the boulder (%.2f m/s)" % curl)
	var seam_side := r.seam_at(c + Vector2(rad * 2.0, rad + 0.125))
	var seam_open := r.seam_at(c + Vector2(rad * 2.0, -3.75))
	_check(seam_side > 0.5 and seam_side > seam_open * 3.0,
		"seams trail off the boulder's sides (%.2f vs %.2f in open water)" % [seam_side, seam_open])


func _test_trout_hold_behind_the_boulder() -> void:
	var r := _field([ROCK])
	var c := Vector2(ROCK.x, ROCK.y)
	var pocket := r.lie_at(c + Vector2(ROCK.z + 0.5, 0))
	var thalweg := r.lie_at(Vector2(RIFFLE_X, THALWEG))
	var mid_pool := r.lie_at(Vector2(POOL_X, THALWEG))
	_check(pocket > 0.6, "the boulder pocket is a prime lie (%.2f)" % pocket)
	_check(thalweg < 0.05, "nothing holds in the fast riffle thalweg (%.2f)" % thalweg)
	_check(pocket > mid_pool * 2.0, "the pocket beats the open pool (%.2f vs %.2f)" % [pocket, mid_pool])
	var best := r.best_lie()
	_check(Vector2(best.x, best.y).distance_to(c) < ROCK.z * 4.0,
		"the best lie in the reach is by the boulder (%s)" % Vector2(best.x, best.y))


func _test_test_stream_uses_the_field() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var river: RiverField = main.river
	var p := Vector2(7.5, 12.5)
	var px := WorldScale.vec_to_px(p)
	_check(main.flow_at(px).is_equal_approx(WorldScale.vec_to_px(river.flow_at(p))),
		"the test stream's current comes from its river field")
	for rock in main.ROCKS_M:
		_check(not river.is_water(Vector2(rock.x, rock.y)), "the test stream's boulder is not water")
		_check(not main.is_water(WorldScale.vec_to_px(Vector2(rock.x, rock.y))), "the pixel wrapper agrees about the boulder")
	main.free()


## Lie and seam thresholds are fractions of WATER_SPEED, so slowing the water is
## one number and lies and seams stay where the water's shape puts them.
func _test_one_water_speed() -> void:
	var r := _field([ROCK])
	var lies := 0
	var seams := 0
	for k in r.lie.size():
		if r.lie[k] > 0.3:
			lies += 1
		if r.seam[k] > 0.5:
			seams += 1
	_check(lies > 0 and seams > 0, "the test reach has lies and seams (%d, %d cells)" % [lies, seams])
	_check(RiverField.HOLD_SPEED.y < RiverField.FOOD_SPEED.y, "trout hold in slower water than the food lane")


# --- The demo stretch --------------------------------------------------------

func _test_stretch_shape(f: RiverField, st: Stretch) -> void:
	var k := f.centre.size() / 2
	var c := f.centre[k]
	var right := f.centre_dir[k].orthogonal() * -1.0  # right of the flow on screen
	var w := st.half_width
	_check(f.is_water(c + right * (w - 0.5)) and f.is_water(c - right * (w - 0.5)), "the river is 16 m bank to bank")
	_check(not f.is_water(c + right * (w + 0.5)) and not f.is_water(c - right * (w + 0.5)), "the banks are dry")
	var v := f.flow_at(c)
	_check(v.normalized().dot(f.centre_dir[k]) > 0.9, "the current runs along the river's course")
	_check(not f.is_water(st.angler_start), "the angler starts on dry land")


## Finds the sharpest bend and checks both sides of it a few metres off the
## centreline: the outside (cut bank) is deeper and faster, the inside shallow.
func _test_bend_puts_deep_water_outside(f: RiverField) -> void:
	var sharpest := 0
	var turn := 0.0
	for k in range(4, f.centre.size() - 4):
		var a := absf(f.centre_dir[k - 4].angle_to(f.centre_dir[k + 4]))
		if a > turn and _on_map(f, f.centre[k]):
			turn = a
			sharpest = k
	var dir_a := f.centre_dir[sharpest - 4]
	var dir_b := f.centre_dir[sharpest + 4]
	var right := Vector2(-f.centre_dir[sharpest].y, f.centre_dir[sharpest].x)
	var outside := -right if dir_a.angle_to(dir_b) > 0.0 else right  # turning right puts the outside on the left
	var c := f.centre[sharpest]
	var out_p := c + outside * 5.0
	var in_p := c - outside * 5.0
	_check(f.depth_at(out_p) > f.depth_at(in_p) * 1.5,
		"in the hard bend the outside runs deeper (%.2f vs %.2f)" % [f.depth_at(out_p), f.depth_at(in_p)])
	_check(f.flow_at(out_p).length() > f.flow_at(in_p).length() * 1.5,
		"in the hard bend the outside runs faster (%.2f vs %.2f m/s)" % [f.flow_at(out_p).length(), f.flow_at(in_p).length()])


func _on_map(f: RiverField, p: Vector2) -> bool:
	return p.x > 0.0 and p.y > 0.0 and p.x < f.width and p.y < f.bottom


## Every boulder: a slower pocket behind it and a seam off each side.
func _test_stretch_boulders(f: RiverField, st: Stretch) -> void:
	for r in st.features.filter(func(x): return x is Boulder):
		var c: Vector2 = r.centre
		var k := f.nearest_centre(c)
		var down := f.centre_dir[k]
		var side := down.orthogonal()
		var pocket := f.flow_at(c + down * r.radius * 2.0).length()
		var open := f.flow_at(c - down * r.radius * 4.0).length()
		_check(pocket < open * 0.5, "boulder at %s has a slow pocket behind it (%.2f vs %.2f m/s)" % [c, pocket, open])
		var seam_a := 0.0
		var seam_b := 0.0
		for t in [1.0, 2.0, 3.0]:
			seam_a = maxf(seam_a, f.seam_at(c + down * r.radius * t + side * r.radius * 1.3))
			seam_b = maxf(seam_b, f.seam_at(c + down * r.radius * t - side * r.radius * 1.3))
		_check(seam_a > 0.4 and seam_b > 0.4, "boulder at %s has a seam off each side (%.2f, %.2f)" % [c, seam_a, seam_b])


## The eddy: water runs back upstream along the bank, a fly dropped in it comes
## back round without leaving downstream, the swirl has no sources or sinks, and
## the eddy line is a strong seam with a lie on it.
func _test_eddy_circulates(f: RiverField, st: Stretch) -> void:
	var eddies := st.features.filter(func(x): return x is Eddy)
	_check(not eddies.is_empty(), "the stretch has an eddy")
	if eddies.is_empty():
		return
	var eddy: Eddy = eddies[0]
	var e := Vector4(eddy.centre.x, eddy.centre.y, eddy.radius, eddy.strength)
	var c := Vector2(e.x, e.y)
	var k := f.nearest_centre(c)
	var down := f.centre_dir[k]
	var to_bank := (c - f.centre[k]).normalized()
	var by_bank := c + to_bank * e.z * 0.5
	_check(f.flow_at(by_bank).dot(down) < -0.5, "water by the bank in the eddy runs back upstream (%.2f m/s)" % f.flow_at(by_bank).dot(down))

	var start := c + to_bank * e.z * 0.8
	var p := start
	var farthest := 0.0
	var left := false
	var closed := false
	for i in 2000:  # 20 s
		p += f.flow_at(p) * 0.01
		farthest = maxf(farthest, p.distance_to(c))
		left = left or p.distance_to(start) > 1.5
		if left and p.distance_to(start) < 0.4:
			closed = true
			break
	_check(closed, "a fly dropped in the eddy comes back round near where it started")
	_check(farthest < e.z * 1.5, "and never drifts out of the eddy (farthest %.1f m)" % farthest)

	var worst := 0.0
	var h := 0.05
	for a in 16:
		var q := c + Vector2.from_angle(a * TAU / 16.0) * e.z * (0.5 + 0.1 * (a % 8))
		var div := (f.eddy_swirl(q + Vector2(h, 0)).x - f.eddy_swirl(q - Vector2(h, 0)).x
			+ f.eddy_swirl(q + Vector2(0, h)).y - f.eddy_swirl(q - Vector2(0, h)).y) / (2.0 * h)
		worst = maxf(worst, absf(div))
	_check(worst < 0.01, "the eddy's swirl has no sources or sinks (max divergence %.4f /s)" % worst)

	var line_seam := 0.0
	for t in [-0.4, -0.2, 0.0, 0.2]:
		line_seam = maxf(line_seam, f.seam_at(c + to_bank * e.z * t))
	_check(line_seam > 0.45, "the eddy line is a strong seam (%.2f)" % line_seam)
	var lie := f.best_lie(Rect2(c - Vector2.ONE * e.z, Vector2.ONE * e.z * 2.0))
	_check(lie.z > 0.6, "trout can hold on the eddy line (%.2f)" % lie.z)


## The demo stretch's water matches the recorded fixture, cell for cell
## (every 6th cell), so a refactor of how the field is built can't quietly
## change the river. Re-record with tools/record_field_fixture.gd only when a
## change to the water is intended, and say so in the PR.
func _test_field_matches_fixture(f: RiverField) -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/demo_field.txt")
	_check(text.length() > 0, "fixture: tests/fixtures/demo_field.txt is readable")
	var worst := 0.0
	var cells := 0
	for line in text.split("\n"):
		if line.is_empty() or line.begins_with("#"):
			continue
		var v := line.split(" ")
		var idx := int(v[1]) * f.cols + int(v[0])
		var got := [f.velocity[idx].x, f.velocity[idx].y, f.depth[idx], f.seam[idx], f.lie[idx]]
		for k in 5:
			worst = maxf(worst, absf(float(v[k + 2]) - float(got[k])))
		cells += 1
	_check(cells > 1000 and worst < 0.001, "fixture: %d cells match the recorded water (worst difference %.6f)" % [cells, worst])


## Adding a feature to a stretch is one more entry in its list: a boulder
## dropped mid-river makes dry rock and a slow pocket behind it, with no other
## change.
func _test_a_new_feature_is_one_entry(st: Stretch) -> void:
	var at := Vector2(10.0, 18.5)  # mid-river near the head
	var plain := RiverField.new()
	plain.build_stretch(st)
	var more := st.duplicate() as Stretch
	more.features = st.features.duplicate()
	more.features.append(Boulder.make(at, 1.0))
	var f := RiverField.new()
	f.build_stretch(more)
	var down: Vector2 = f.flow_frame(at)[0]
	_check(plain.is_water(at) and not f.is_water(at), "feature kit: a new boulder entry makes dry rock")
	_check(f.flow_at(at + down * 2.0).length() < plain.flow_at(at + down * 2.0).length() * 0.5,
		"feature kit: and a slow pocket behind it")


## Five trout on five lies, all in water, at least Fish.LIE_GAP apart.
func _test_trout_spread_over_the_stretch(f: RiverField, st: Stretch) -> void:
	var rng := RandomNumberGenerator.new()
	var area := Rect2(Vector2.ZERO, st.size_m)
	for run in 5:
		rng.seed = run
		var lies := PackedVector2Array()
		var count := st.stocked().size()
		for n in count:
			var l := f.pick_lie(area, rng, Fish.MIN_LIE_SCORE, lies, Fish.LIE_GAP)
			if l == Vector2.INF:
				break
			lies.append(l)
		var ok := lies.size() == count
		for a in lies.size():
			ok = ok and f.is_water(lies[a])
			for b in range(a + 1, lies.size()):
				ok = ok and lies[a].distance_to(lies[b]) >= Fish.LIE_GAP
		_check(ok, "run %d: %d trout get their own lies, in water and %.0f m apart" % [run, count, Fish.LIE_GAP])


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
