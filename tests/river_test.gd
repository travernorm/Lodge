extends SceneTree
## Headless tests for the river field: the current follows the hydraulic rules
## in the river design doc.
##   godot --headless --path . --script res://tests/river_test.gd

const TOP := 58.0
const BOTTOM := 148.0
const WIDTH := 320.0
const ROCK := Vector3(160, 100, 5)

var _failures := 0


func _initialize() -> void:
	_test_thalweg_is_fastest()
	_test_riffle_faster_than_pool()
	_test_flow_is_conserved()
	_test_bank_and_rock_are_dry()
	_test_boulder_cushion_pocket_and_seams()
	_test_trout_hold_behind_the_boulder()
	_test_test_stream_uses_the_field()
	if _failures == 0:
		print("River tests passed.")
		quit(0)
	else:
		printerr("%d river test(s) failed." % _failures)
		quit(1)


func _thalweg_y(_x: float) -> float:
	return 110.0


## Shallow riffle on the left, deep pool on the right.
func _thalweg_depth(x: float) -> float:
	return lerpf(0.35, 1.0, smoothstep(100.0, 180.0, x))


func _field(rocks: Array[Vector3] = []) -> RiverField:
	var r := RiverField.new()
	r.build(TOP, BOTTOM, WIDTH, _thalweg_y, _thalweg_depth, rocks)
	return r


func _test_thalweg_is_fastest() -> void:
	var r := _field()
	var x := 40.0
	var on_line := r.flow_at(Vector2(x, 110)).length()
	var fastest := 0.0
	var fastest_y := 0.0
	for y in range(int(TOP), int(BOTTOM) + 1):
		var s := r.flow_at(Vector2(x, y)).length()
		if s > fastest:
			fastest = s
			fastest_y = y
	_check(absf(fastest_y - 110.0) <= 2.0, "fastest water sits on the thalweg (y %d)" % fastest_y)
	var far_edge := r.flow_at(Vector2(x, TOP + 3)).length()
	var near_edge := r.flow_at(Vector2(x, BOTTOM - 3)).length()
	_check(far_edge < on_line * 0.4 and near_edge < on_line * 0.4,
		"banks are slow (edges %.0f, %.0f vs %.0f px/s)" % [far_edge, near_edge, on_line])
	_check(absf(r.flow_at(Vector2(x, 110)).y) < 0.01, "a straight reach flows straight downstream")


func _test_riffle_faster_than_pool() -> void:
	var r := _field()
	var riffle := r.flow_at(Vector2(40, 110)).length()
	var pool := r.flow_at(Vector2(280, 110)).length()
	_check(riffle > pool * 2.0, "shallow riffle runs much faster than the deep pool (%.0f vs %.0f px/s)" % [riffle, pool])


func _test_flow_is_conserved() -> void:
	var r := _field()
	var riffle := _discharge(r, 40.0)
	var pool := _discharge(r, 280.0)
	_check(absf(riffle - pool) / riffle < 0.03, "the same water passes the riffle and the pool (%.0f vs %.0f)" % [riffle, pool])


func _discharge(r: RiverField, x: float) -> float:
	var q := 0.0
	var y := TOP
	while y <= BOTTOM:
		q += r.flow_at(Vector2(x, y)).x * r.depth_at(Vector2(x, y))
		y += 0.5
	return q


func _test_bank_and_rock_are_dry() -> void:
	var r := _field([ROCK])
	_check(r.flow_at(Vector2(100, TOP - 5)) == Vector2.ZERO, "no current on the far bank")
	_check(r.flow_at(Vector2(100, BOTTOM + 5)) == Vector2.ZERO, "no current on the near bank")
	_check(not r.is_water(Vector2(ROCK.x, ROCK.y)), "the boulder is not water")
	_check(r.flow_at(Vector2(ROCK.x + 1, ROCK.y)) == Vector2.ZERO, "no current inside the boulder")


func _test_boulder_cushion_pocket_and_seams() -> void:
	var open := _field()
	var r := _field([ROCK])
	var c := Vector2(ROCK.x, ROCK.y)
	var rad := ROCK.z
	var free := open.flow_at(c).length()
	var cushion := r.flow_at(c + Vector2(-rad - 2, 0)).length()
	var pocket := r.flow_at(c + Vector2(rad + 4, 0)).length()
	var beside := r.flow_at(c + Vector2(0, rad + 2)).length()
	_check(cushion < free * 0.6, "a slow cushion in front of the boulder (%.0f vs %.0f px/s)" % [cushion, free])
	_check(pocket < free * 0.3, "a slack pocket behind the boulder (%.0f vs %.0f px/s)" % [pocket, free])
	_check(beside > free, "water speeds up around the boulder's sides (%.0f vs %.0f px/s)" % [beside, free])
	var curl := r.flow_at(c + Vector2(rad + 1, 0)).x
	_check(curl < 0.5, "a little back-flow right behind the boulder (%.1f px/s)" % curl)
	var seam_side := r.seam_at(c + Vector2(rad * 2.0, rad + 1))
	var seam_open := r.seam_at(c + Vector2(rad * 2.0, -30))
	_check(seam_side > 0.5 and seam_side > seam_open * 3.0,
		"seams trail off the boulder's sides (%.2f vs %.2f in open water)" % [seam_side, seam_open])


func _test_trout_hold_behind_the_boulder() -> void:
	var r := _field([ROCK])
	var c := Vector2(ROCK.x, ROCK.y)
	var pocket := r.lie_at(c + Vector2(ROCK.z + 4, 0))
	var thalweg := r.lie_at(Vector2(40, 110))
	var mid_pool := r.lie_at(Vector2(280, 110))
	_check(pocket > 0.6, "the boulder pocket is a prime lie (%.2f)" % pocket)
	_check(thalweg < 0.05, "nothing holds in the fast riffle thalweg (%.2f)" % thalweg)
	_check(pocket > mid_pool * 2.0, "the pocket beats the open pool (%.2f vs %.2f)" % [pocket, mid_pool])
	var best := r.best_lie()
	_check(Vector2(best.x, best.y).distance_to(c) < ROCK.z * 4.0,
		"the best lie in the reach is by the boulder (%s)" % Vector2(best.x, best.y))


func _test_test_stream_uses_the_field() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var river: RiverField = main.river
	var p := Vector2(60, 100)
	_check(main.flow_at(p) == river.flow_at(p), "the test stream's current comes from its river field")
	for rock in main.ROCKS:
		_check(not main.is_water(Vector2(rock.x, rock.y)), "the test stream's boulder is not water")
	main.free()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
