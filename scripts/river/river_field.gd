class_name RiverField
extends RefCounted
## The current, depth, seams and trout lies for one screen of river, stored on a
## grid and read back with bilinear sampling.
##
## This is the stand-in for a baked river. It builds the grid from simple
## hydraulic rules instead of a solver, but it stores and serves the same layers
## a bake will (velocity, depth, seam strength, lie score), so the drift, the
## water drawing and later the fish can switch to baked data without changing.
##
## Rules it follows (see the river design doc):
## - Water is conserved: every cross-section carries the same flow, so shallow
##   riffles run fast and deep pools run slow.
## - Speed follows depth (roughly v ~ depth^(2/3), as in Manning's formula), so
##   the fastest water is over the thalweg, the deepest line, and the banks are
##   slow.
## - A boulder makes a slow cushion in front, a slack pocket behind (with a
##   little back-flow right behind it) and a seam off each side.
## - Trout hold in slow, deep-enough water with fast water close by.

## Grid spacing in px. 2 px keeps one screen to a few thousand cells.
const CELL := 2.0

## Speed (px/s) over the thalweg at the head of the stream; sets the total flow.
const RIFFLE_THALWEG_SPEED := 55.0
## Exponent in v ~ depth^k.
const DEPTH_SPEED_EXP := 2.0 / 3.0
## Shallowest water at the very edge, as a fraction of the thalweg depth.
const EDGE_DEPTH := 0.04

## Boulder wake: how long the slack pocket runs, in rock radii.
const WAKE_LENGTH := 6.0
## How fast the wake spreads sideways with distance downstream.
const WAKE_SPREAD := 0.12
## 1 = dead slack right behind the rock; a bit more gives a little back-flow.
const WAKE_STRENGTH := 1.12

## Lie scoring, in px/s and relative depth.
const HOLD_SPEED := Vector2(8.0, 20.0)  # comfortable below x, too fast above y
const FOOD_SPEED := Vector2(14.0, 32.0)  # nearby water this fast brings food
const FOOD_REACH := 5  # cells: how far a trout will dart for food (10 px)
const DEPTH_NEEDED := Vector2(0.12, 0.35)
const SEAM_FULL := 3.0  # speed change (px/s per px) that counts as a strong seam
const SEAM_DEPTH := Vector2(0.08, 0.2)  # ignore seams in ankle-deep edge water

var top := 0.0  # far bank, y
var bottom := 0.0  # near bank, y
var width := 0.0  # screen width, x
var cols := 0
var rows := 0

var velocity := PackedVector2Array()
var depth := PackedFloat32Array()  # 0..1, 1 = deepest water in the reach
var seam := PackedFloat32Array()  # 0..1
var lie := PackedFloat32Array()  # 0..1
## Boulders: x, y = centre, z = radius.
var rocks: Array[Vector3] = []

var _thalweg_y: Callable
var _thalweg_depth: Callable


## Builds the field.
##   p_top, p_bottom: banks (y). p_width: reach length (x).
##   thalweg_y(x): where the deepest line runs. thalweg_depth(x): how deep it is (0..1).
##   p_rocks: boulders as Vector3(x, y, radius).
func build(p_top: float, p_bottom: float, p_width: float, thalweg_y: Callable,
		thalweg_depth: Callable, p_rocks: Array[Vector3] = []) -> void:
	top = p_top
	bottom = p_bottom
	width = p_width
	_thalweg_y = thalweg_y
	_thalweg_depth = thalweg_depth
	rocks = p_rocks
	cols = int(ceilf(width / CELL)) + 1
	rows = int(ceilf((bottom - top) / CELL)) + 1
	var n := cols * rows
	velocity.resize(n)
	depth.resize(n)
	seam.resize(n)
	lie.resize(n)
	_build_flow()
	_build_seams()
	_build_lies()


# --- Reading the field ------------------------------------------------------

func is_water(p: Vector2) -> bool:
	return p.y >= top and p.y <= bottom and not is_rock(p)


func is_rock(p: Vector2) -> bool:
	for r in rocks:
		if p.distance_squared_to(Vector2(r.x, r.y)) < r.z * r.z:
			return true
	return false


## Current (px/s) at a point. Zero on the bank and inside rocks.
func flow_at(p: Vector2) -> Vector2:
	if not is_water(p):
		return Vector2.ZERO
	return _sample_v(p)


func depth_at(p: Vector2) -> float:
	return _sample_f(depth, p) if is_water(p) else 0.0


func seam_at(p: Vector2) -> float:
	return _sample_f(seam, p) if is_water(p) else 0.0


func lie_at(p: Vector2) -> float:
	return _sample_f(lie, p) if is_water(p) else 0.0


func thalweg_y(x: float) -> float:
	return _thalweg_y.call(x)


## The best lie score in the reach and where it is, optionally only inside `area`.
func best_lie(area := Rect2()) -> Vector3:
	var best := Vector3(0, 0, -1.0)
	for j in rows:
		for i in cols:
			var p := cell_pos(i, j)
			if area.has_area() and not area.has_point(p):
				continue
			var s := lie[j * cols + i]
			if s > best.z:
				best = Vector3(p.x, p.y, s)
	return best


func cell_pos(i: int, j: int) -> Vector2:
	return Vector2(i * CELL, top + j * CELL)


# --- Building ---------------------------------------------------------------

func _build_flow() -> void:
	# Total flow is set by the first column: RIFFLE_THALWEG_SPEED over the thalweg.
	var k0 := RIFFLE_THALWEG_SPEED / pow(_thalweg_depth.call(0.0), DEPTH_SPEED_EXP)
	var q := k0 * _section_sum(0.0)
	for i in cols:
		var x := i * CELL
		# Same flow through every section: v = k * d^(2/3), q = sum(v * d) = k * sum(d^(5/3)).
		var k := q / _section_sum(x)
		for j in rows:
			var p := cell_pos(i, j)
			var d := _bed_depth(p)
			var idx := j * cols + i
			depth[idx] = d
			velocity[idx] = _around_rocks(p, Vector2(k * pow(d, DEPTH_SPEED_EXP), 0.0))


## Depth of the bed at p: deepest on the thalweg, shelving to the banks.
func _bed_depth(p: Vector2) -> float:
	var ty: float = _thalweg_y.call(p.x)
	var td: float = _thalweg_depth.call(p.x)
	var reach := (ty - top) if p.y < ty else (bottom - ty)
	var n := clampf(absf(p.y - ty) / maxf(reach, 1.0), 0.0, 1.0)
	return td * maxf(EDGE_DEPTH, 1.0 - n * n)


func _section_sum(x: float) -> float:
	var s := 0.0
	for j in rows:
		s += pow(_bed_depth(Vector2(x, top + j * CELL)), 1.0 + DEPTH_SPEED_EXP)
	return s


## Bends the current around each boulder (ideal flow past a cylinder) and cuts
## the slack pocket behind it.
func _around_rocks(p: Vector2, base: Vector2) -> Vector2:
	var v := base
	for r in rocks:
		var rel := p - Vector2(r.x, r.y)
		var rad := r.z
		var d2 := rel.length_squared()
		if d2 < rad * rad:
			return Vector2.ZERO
		var speed := v.length()
		var r2 := rad * rad
		var r4 := d2 * d2
		# Potential flow past a cylinder in a stream along +x, unit speed.
		var u := 1.0 - r2 * (rel.x * rel.x - rel.y * rel.y) / r4
		var w := -2.0 * r2 * rel.x * rel.y / r4
		var shaped := Vector2(u, w) * speed
		if rel.x > 0.0:
			var half := rad * (1.0 + WAKE_SPREAD * rel.x / rad)
			var wake := exp(-pow(rel.y / half, 2.0)) * exp(-(rel.x - rad) / (WAKE_LENGTH * rad))
			shaped.x *= 1.0 - WAKE_STRENGTH * clampf(wake, 0.0, 1.0)
		v = shaped
	return v


func _build_seams() -> void:
	for j in rows:
		for i in cols:
			var sx := (_speed(i + 1, j) - _speed(i - 1, j)) / (2.0 * CELL)
			var sy := (_speed(i, j + 1) - _speed(i, j - 1)) / (2.0 * CELL)
			var idx := j * cols + i
			seam[idx] = clampf(Vector2(sx, sy).length() / SEAM_FULL, 0.0, 1.0) \
				* smoothstep(SEAM_DEPTH.x, SEAM_DEPTH.y, depth[idx])


func _build_lies() -> void:
	# Fastest water within FOOD_REACH, as a separable max filter.
	var row_max := PackedFloat32Array()
	row_max.resize(cols * rows)
	for j in rows:
		for i in cols:
			var m := 0.0
			for o in range(-FOOD_REACH, FOOD_REACH + 1):
				m = maxf(m, _speed(i + o, j))
			row_max[j * cols + i] = m
	for j in rows:
		for i in cols:
			var idx := j * cols + i
			var p := cell_pos(i, j)
			if is_rock(p):
				lie[idx] = 0.0
				continue
			var near := 0.0
			for o in range(-FOOD_REACH, FOOD_REACH + 1):
				var jj := clampi(j + o, 0, rows - 1)
				near = maxf(near, row_max[jj * cols + i])
			var hold := 1.0 - smoothstep(HOLD_SPEED.x, HOLD_SPEED.y, velocity[idx].length())
			var food := smoothstep(FOOD_SPEED.x, FOOD_SPEED.y, near)
			var deep := smoothstep(DEPTH_NEEDED.x, DEPTH_NEEDED.y, depth[idx])
			lie[idx] = hold * food * deep


func _speed(i: int, j: int) -> float:
	i = clampi(i, 0, cols - 1)
	j = clampi(j, 0, rows - 1)
	return velocity[j * cols + i].length()


# --- Sampling ---------------------------------------------------------------

func _grid_coords(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x / CELL, 0.0, cols - 1.001), clampf((p.y - top) / CELL, 0.0, rows - 1.001))


func _sample_v(p: Vector2) -> Vector2:
	var g := _grid_coords(p)
	var i := int(g.x)
	var j := int(g.y)
	var fx := g.x - i
	var fy := g.y - j
	var a := velocity[j * cols + i].lerp(velocity[j * cols + i + 1], fx)
	var b := velocity[(j + 1) * cols + i].lerp(velocity[(j + 1) * cols + i + 1], fx)
	return a.lerp(b, fy)


func _sample_f(layer: PackedFloat32Array, p: Vector2) -> float:
	var g := _grid_coords(p)
	var i := int(g.x)
	var j := int(g.y)
	var fx := g.x - i
	var fy := g.y - j
	var a := lerpf(layer[j * cols + i], layer[j * cols + i + 1], fx)
	var b := lerpf(layer[(j + 1) * cols + i], layer[(j + 1) * cols + i + 1], fx)
	return lerpf(a, b, fy)
