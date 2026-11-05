class_name RiverField
extends RefCounted
## The current, depth, seams and trout lies for a reach of river, stored on a
## grid and read back with bilinear sampling.
##
## Two ways to build it: build() for a straight reach between two banks (the
## original test screen), and build_stretch() for a Stretch whose river winds in
## any direction, with bends, cut banks, logs and eddies. The hydraulic rules
## that fill the layers live in RiverFieldBuilder (river_field_builder.gd); this
## file keeps the layers and the read-only queries.
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
## - Features on the bed (RiverFeature: boulders, logs, eddies ...) shape the
##   current. The field runs them in order and knows none of them by name
##   (REQ-0004 C3); each kind's rules live in scripts/river/features/.
## - Trout hold in slow, deep-enough water with fast water close by.

## Units: metres and metres per second throughout (REQ-0001). Views convert to
## pixels with WorldScale. Depth is relative (1 = deepest water in the reach).

## Grid spacing in metres. 0.25 m keeps one screen to a few thousand cells.
const CELL := 0.25

## The one water-speed number: the speed (m/s) over the thalweg at the head of
## the stream, which sets the total flow. Every other speed below is a fraction
## of it, so slowing the water toward a real creek (about 1.2 m/s on a riffle)
## is a one-number change. Today's 6.875 m/s is the speed the prototype was tuned at.
const WATER_SPEED := 6.875
## Exponent in v ~ depth^k.
const DEPTH_SPEED_EXP := 2.0 / 3.0
## Shallowest water at the very edge, as a fraction of the thalweg depth.
const EDGE_DEPTH := 0.04

## Lie scoring. Speeds are fractions of WATER_SPEED; depth is relative.
const HOLD_SPEED := Vector2(8.0, 20.0) / 55.0  # comfortable below x, too fast above y
const FOOD_SPEED := Vector2(14.0, 32.0) / 55.0  # nearby water this fast brings food
const FOOD_REACH := 1.25  # m: how far a trout will dart for food
const DEPTH_NEEDED := Vector2(0.12, 0.35)
## A strong seam: speed changing by this fraction of WATER_SPEED per metre across the flow.
const SEAM_FULL := 24.0 / 55.0
const SEAM_DEPTH := Vector2(0.08, 0.2)  # ignore seams in ankle-deep edge water

## Winding channels: centreline sample spacing (m) and how far (m) the
## curvature is smoothed along the river.
const CHANNEL_STEP := 1.0
const CURVE_SMOOTH := 6.0
## The thalweg never moves more than this fraction of the half-width off centre.
const MAX_THALWEG_SHIFT := 0.45

var top := 0.0  # far bank, y (m); 0 for a stretch
var bottom := 0.0  # near bank, y (m); the stretch's height for a stretch
var width := 0.0  # reach length, x (m)
var cols := 0
var rows := 0

var velocity := PackedVector2Array()
var depth := PackedFloat32Array()  # 0..1, 1 = deepest water in the reach
var seam := PackedFloat32Array()  # 0..1
var lie := PackedFloat32Array()  # 0..1
## What's on the bed, in order: the stretch's features, or the boulders of a
## straight reach.
var features: Array[RiverFeature] = []
## The stretch this was built from, or null for a straight reach.
var stretch: Stretch

## Stretch only, per cell: 1 = water. Empty for a straight reach.
var wet := PackedByteArray()
## Stretch only, per cell: metres beyond the nearest bank (negative in the
## water, INF far from the river).
var shore := PackedFloat32Array()
## Stretch only, per cell: -1..1, + on the outside of a bend (cut bank side),
## - on the inside (point bar side).
var bend := PackedFloat32Array()
## The deepest line, as points (m), for drawing.
var thalweg := PackedVector2Array()
## Stretch only: the river's centreline every CHANNEL_STEP m, and which way the
## river runs there (unit vectors), upstream first.
var centre := PackedVector2Array()
var centre_dir := PackedVector2Array()

## Inputs and per-build state, written only by RiverFieldBuilder.
var _thalweg_y: Callable
var _thalweg_depth: Callable
## Per feature: the number its prepare() returned this build.
var _feature_state := PackedFloat32Array()
## Stretch only, per cell: the nearest centreline segment, and which side of
## the flow the cell is on (+ = right).
var _near_k := PackedInt32Array()
var _near_n := PackedFloat32Array()


## Builds the field.
##   p_top, p_bottom: banks (y, m). p_width: reach length (x, m).
##   thalweg_y(x): where the deepest line runs (m). thalweg_depth(x): how deep it is (0..1).
##   p_rocks: boulders as Vector3(x, y, radius), in metres.
func build(p_top: float, p_bottom: float, p_width: float, thalweg_y: Callable,
		thalweg_depth: Callable, p_rocks: Array[Vector3] = []) -> void:
	top = p_top
	bottom = p_bottom
	width = p_width
	_thalweg_y = thalweg_y
	_thalweg_depth = thalweg_depth
	features = []
	for r in p_rocks:
		features.append(Boulder.make(Vector2(r.x, r.y), r.z))
	stretch = null
	centre = PackedVector2Array()
	centre_dir = PackedVector2Array()
	wet = PackedByteArray()
	_near_k = PackedInt32Array()
	_near_n = PackedFloat32Array()
	shore = PackedFloat32Array()
	bend = PackedFloat32Array()
	RiverFieldBuilder.straight(self)
	thalweg = PackedVector2Array()
	var x := 0.0
	while x <= width:
		thalweg.append(Vector2(x, thalweg_y(x)))
		x += 0.5


## Builds the field for a winding stretch of river (REQ-0002).
func build_stretch(p_stretch: Stretch) -> void:
	stretch = p_stretch
	top = 0.0
	bottom = stretch.size_m.y
	width = stretch.size_m.x
	features = stretch.features
	RiverFieldBuilder.winding(self)


# --- Reading the field ------------------------------------------------------

func is_water(p: Vector2) -> bool:
	if wet.is_empty():
		return p.y >= top and p.y <= bottom and not is_solid(p)
	var i := roundi(p.x / CELL)
	var j := roundi((p.y - top) / CELL)
	if i < 0 or j < 0 or i >= cols or j >= rows:
		return false
	return wet[j * cols + i] == 1 and not is_solid(p)


## True inside something solid in the water, like a boulder.
func is_solid(p: Vector2) -> bool:
	for f in features:
		if f.blocks(p):
			return true
	return false


## Which way the river runs at p, and which side of the flow p is on:
## [direction (unit), +1 right or -1 left]. A straight reach runs along +x.
func flow_frame(p: Vector2) -> Array:
	if _near_k.is_empty():
		return [Vector2.RIGHT, 1.0 if p.y >= (top + bottom) * 0.5 else -1.0]
	var i := clampi(roundi(p.x / CELL), 0, cols - 1)
	var j := clampi(roundi((p.y - top) / CELL), 0, rows - 1)
	var idx := j * cols + i
	var k := maxi(_near_k[idx], 0)
	return [centre_dir[k], 1.0 if _near_n[idx] >= 0.0 else -1.0]


## Current (m/s) at a point (m). Zero on the bank and inside rocks.
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


## Straight reach only: where the thalweg runs at x (m).
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


## A lie for a trout to hold in: a random cell inside `area` scoring at least
## `min_score`, with better lies more likely (weight = score squared). Cells
## closer than `gap` (m) to any point in `avoid` (other trout) are skipped.
## Returns Vector2.INF when the area has no lie that good.
func pick_lie(area: Rect2, rng: RandomNumberGenerator, min_score := 0.4,
		avoid := PackedVector2Array(), gap := 0.0) -> Vector2:
	var cells: Array[Vector2] = []
	var weights := PackedFloat32Array()
	var total := 0.0
	for j in rows:
		for i in cols:
			var p := cell_pos(i, j)
			var s := lie[j * cols + i]
			if s >= min_score and area.has_point(p) and is_water(p) and _clear_of(p, avoid, gap):
				cells.append(p)
				weights.append(s * s)
				total += s * s
	if cells.is_empty():
		return Vector2.INF
	var roll := rng.randf() * total
	for k in cells.size():
		roll -= weights[k]
		if roll <= 0.0:
			return cells[k]
	return cells[-1]


## Stretch only: the index of the centreline point nearest p (m), or -1.
## Which way the water runs at `p` (m), for the drift's bow and mends: the
## local current, so a fly in an eddy mends against the eddy's reversed
## current, or the centreline where the water is slack. The test screen's
## straight reach runs +x.
func downstream_at(p: Vector2) -> Vector2:
	if stretch == null:
		return Vector2.RIGHT
	var v := flow_at(p)
	if v.length() > 0.05:
		return v.normalized()
	var k := nearest_centre(p)
	return centre_dir[k] if k >= 0 else Vector2.RIGHT


func nearest_centre(p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for k in centre.size():
		var d := p.distance_squared_to(centre[k])
		if d < best_d:
			best_d = d
			best = k
	return best


func cell_pos(i: int, j: int) -> Vector2:
	return Vector2(i * CELL, top + j * CELL)


func _clear_of(p: Vector2, avoid: PackedVector2Array, gap: float) -> bool:
	for a in avoid:
		if p.distance_squared_to(a) < gap * gap:
			return false
	return true


## The swirl the features (eddies) add at p (m/s).
func eddy_swirl(p: Vector2) -> Vector2:
	var v := Vector2.ZERO
	for n in features.size():
		v += features[n].swirl(p, _feature_state[n] if n < _feature_state.size() else 1.0)
	return v


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
