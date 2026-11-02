class_name RiverField
extends RefCounted
## The current, depth, seams and trout lies for a reach of river, stored on a
## grid and read back with bilinear sampling.
##
## Two ways to build it: build() for a straight reach between two banks (the
## original test screen), and build_stretch() for a Stretch whose river winds in
## any direction, with bends, cut banks, logs and eddies.
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

## Boulder wake: how long the slack pocket runs, in rock radii.
const WAKE_LENGTH := 6.0
## How fast the wake spreads sideways with distance downstream.
const WAKE_SPREAD := 0.12
## 1 = dead slack right behind the rock; a bit more gives a little back-flow.
const WAKE_STRENGTH := 1.12

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
## Fallen logs: how far (m) their slack water reaches, and how much they slow it.
const LOG_REACH := 1.0
const LOG_SLOW := 0.9
## Inside an eddy the main current is calmed by this much at the centre, so the
## swirl takes over.
const EDDY_CALM := 0.7

var top := 0.0  # far bank, y (m); 0 for a stretch
var bottom := 0.0  # near bank, y (m); the stretch's height for a stretch
var width := 0.0  # reach length, x (m)
var cols := 0
var rows := 0

var velocity := PackedVector2Array()
var depth := PackedFloat32Array()  # 0..1, 1 = deepest water in the reach
var seam := PackedFloat32Array()  # 0..1
var lie := PackedFloat32Array()  # 0..1
## Boulders: x, y = centre, z = radius (m).
var rocks: Array[Vector3] = []
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

var _thalweg_y: Callable
## Stretch only: +1 or -1 per eddy, the way it turns.
var _eddy_spin := PackedFloat32Array()
var _thalweg_depth: Callable


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
	rocks = p_rocks
	stretch = null
	centre = PackedVector2Array()
	centre_dir = PackedVector2Array()
	wet = PackedByteArray()
	shore = PackedFloat32Array()
	bend = PackedFloat32Array()
	_allocate()
	_build_flow()
	_build_seams()
	_build_lies()
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
	rocks = stretch.rocks
	_allocate()
	_build_channel()
	_build_seams()
	_build_lies()


func _allocate() -> void:
	cols = int(ceilf(width / CELL - 0.001)) + 1
	rows = int(ceilf((bottom - top) / CELL - 0.001)) + 1
	var n := cols * rows
	velocity.resize(n)
	depth.resize(n)
	seam.resize(n)
	lie.resize(n)


# --- Reading the field ------------------------------------------------------

func is_water(p: Vector2) -> bool:
	if wet.is_empty():
		return p.y >= top and p.y <= bottom and not is_rock(p)
	var i := roundi(p.x / CELL)
	var j := roundi((p.y - top) / CELL)
	if i < 0 or j < 0 or i >= cols or j >= rows:
		return false
	return wet[j * cols + i] == 1 and not is_rock(p)


func is_rock(p: Vector2) -> bool:
	for r in rocks:
		if p.distance_squared_to(Vector2(r.x, r.y)) < r.z * r.z:
			return true
	return false


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


# --- Building ---------------------------------------------------------------

func _build_flow() -> void:
	# Total flow is set by the first column: WATER_SPEED over the thalweg.
	var k0 := WATER_SPEED / pow(_thalweg_depth.call(0.0), DEPTH_SPEED_EXP)
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
	var n := clampf(absf(p.y - ty) / maxf(reach, CELL * 0.5), 0.0, 1.0)
	return td * maxf(EDGE_DEPTH, 1.0 - n * n)


func _section_sum(x: float) -> float:
	var s := 0.0
	for j in rows:
		s += pow(_bed_depth(Vector2(x, top + j * CELL)), 1.0 + DEPTH_SPEED_EXP)
	return s


## Bends the current around each boulder (ideal flow past a cylinder) and cuts
## the slack pocket behind it. Works in the current's own frame, so it suits a
## river running in any direction.
func _around_rocks(p: Vector2, base: Vector2) -> Vector2:
	var v := base
	for r in rocks:
		var rel := p - Vector2(r.x, r.y)
		var rad := r.z
		var d2 := rel.length_squared()
		if d2 < rad * rad:
			return Vector2.ZERO
		var speed := v.length()
		var angle := v.angle() if speed > 0.0 else 0.0
		if angle != 0.0:
			rel = rel.rotated(-angle)
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
		v = shaped.rotated(angle) if angle != 0.0 else shaped
	return v


# --- Winding channel (Stretch) ----------------------------------------------

## Lays the river along the stretch's centreline. Every cell finds its nearest
## point on the centreline: how far along the river it is and how far across.
## Across the channel the bed is parabolic around the thalweg, which bends
## push toward the outside bank. The current runs along the centreline, with
## the same flow through every cross-section.
func _build_channel() -> void:
	var c := _resample(_catmull_rom(stretch.centreline, 24), CHANNEL_STEP)
	var n := c.size()
	var w := stretch.half_width
	var tang := PackedVector2Array()
	var curv := PackedFloat32Array()
	var cum := PackedFloat32Array()
	tang.resize(n)
	curv.resize(n)
	cum.resize(n)
	for k in n:
		tang[k] = (c[mini(k + 1, n - 1)] - c[maxi(k - 1, 0)]).normalized()
		cum[k] = 0.0 if k == 0 else cum[k - 1] + c[k].distance_to(c[k - 1])
	for k in n:
		var a := tang[maxi(k - 1, 0)]
		var b := tang[mini(k + 1, n - 1)]
		var ds := c[maxi(k - 1, 0)].distance_to(c[mini(k + 1, n - 1)])
		curv[k] = a.angle_to(b) / maxf(ds, 0.001)  # + = turning clockwise on screen
	curv = _box_smooth(curv, roundi(CURVE_SMOOTH / CHANNEL_STEP))

	# Per centreline point: thalweg offset (+ = right of the flow), depth and
	# the speed factor that keeps the flow the same through every section.
	var offs := PackedFloat32Array()
	var tds := PackedFloat32Array()
	var ks := PackedFloat32Array()
	offs.resize(n)
	tds.resize(n)
	ks.resize(n)
	var q := 0.0
	for k in n:
		offs[k] = clampf(-curv[k] * w * w * stretch.bend_shift * 0.9, -MAX_THALWEG_SHIFT * w, MAX_THALWEG_SHIFT * w)
		tds[k] = stretch.depth_at_fraction(cum[k] / cum[n - 1])
		var sum := 0.0
		var across := -w
		while across <= w:
			sum += pow(_profile(across, w, offs[k], tds[k]), 1.0 + DEPTH_SPEED_EXP)
			across += CELL
		if k == 0:
			q = WATER_SPEED / pow(tds[0], DEPTH_SPEED_EXP) * sum
		ks[k] = q / sum

	# Nearest centreline segment for every cell within reach of the river.
	var total := cols * rows
	var best := PackedFloat32Array()
	var near_k := PackedInt32Array()
	var near_t := PackedFloat32Array()
	var near_n := PackedFloat32Array()
	best.resize(total)
	best.fill(INF)
	near_k.resize(total)
	near_k.fill(-1)
	near_t.resize(total)
	near_n.resize(total)
	var reach := w + 3.0
	for k in n - 1:
		var a := c[k]
		var d := c[k + 1] - a
		var l2 := maxf(d.length_squared(), 0.000001)
		var i0 := maxi(0, floori((minf(a.x, a.x + d.x) - reach) / CELL))
		var i1 := mini(cols - 1, ceili((maxf(a.x, a.x + d.x) + reach) / CELL))
		var j0 := maxi(0, floori((minf(a.y, a.y + d.y) - reach - top) / CELL))
		var j1 := mini(rows - 1, ceili((maxf(a.y, a.y + d.y) + reach - top) / CELL))
		for j in range(j0, j1 + 1):
			var py := top + j * CELL
			for i in range(i0, i1 + 1):
				var ap := Vector2(i * CELL, py) - a
				var t := clampf(ap.dot(d) / l2, 0.0, 1.0)
				var dist2 := (ap - d * t).length_squared()
				var idx := j * cols + i
				if dist2 < best[idx]:
					best[idx] = dist2
					near_k[idx] = k
					near_t[idx] = t
					near_n[idx] = sqrt(dist2) * (1.0 if d.cross(ap) >= 0.0 else -1.0)

	wet.resize(total)
	shore.resize(total)
	bend.resize(total)
	for idx in total:
		var k := near_k[idx]
		velocity[idx] = Vector2.ZERO
		depth[idx] = 0.0
		wet[idx] = 0
		if k < 0:
			shore[idx] = INF
			bend[idx] = 0.0
			continue
		var t := near_t[idx]
		var across := near_n[idx]
		var off := lerpf(offs[k], offs[k + 1], t)
		shore[idx] = absf(across) - w
		bend[idx] = clampf(off / (MAX_THALWEG_SHIFT * w), -1.0, 1.0) * signf(across)
		if absf(across) > w:
			continue
		var d := _profile(across, w, off, lerpf(tds[k], tds[k + 1], t))
		var dir := tang[k].lerp(tang[k + 1], t).normalized()
		wet[idx] = 1
		depth[idx] = d
		velocity[idx] = dir * lerpf(ks[k], ks[k + 1], t) * pow(d, DEPTH_SPEED_EXP)

	# Which way each eddy turns: back upstream along its nearer bank.
	_eddy_spin.clear()
	for e in stretch.eddies:
		var i := clampi(roundi(e.x / CELL), 0, cols - 1)
		var j := clampi(roundi((e.y - top) / CELL), 0, rows - 1)
		var k := maxi(near_k[j * cols + i], 0)
		var right := Vector2(-tang[k].y, tang[k].x)
		var bank := right * (1.0 if near_n[j * cols + i] >= 0.0 else -1.0)
		_eddy_spin.append(-signf(Vector2(-bank.y, bank.x).dot(tang[k])))

	for j in rows:
		for i in cols:
			var idx := j * cols + i
			if wet[idx] == 0:
				continue
			var p := cell_pos(i, j)
			var v := _beside_logs(p, velocity[idx])
			v = _around_rocks(p, v)
			velocity[idx] = v * _eddy_calm(p) + eddy_swirl(p)

	centre = c
	centre_dir = tang
	thalweg = PackedVector2Array()
	for k in n:
		var tp := c[k] + Vector2(-tang[k].y, tang[k].x) * offs[k]
		if tp.x >= 0.0 and tp.y >= top and tp.x <= width and tp.y <= bottom:
			thalweg.append(tp)


## Depth across the channel: `across` (m, + = right of the flow) from the
## centreline, half-width w, thalweg offset off, thalweg depth td.
func _profile(across: float, w: float, off: float, td: float) -> float:
	var rel := (across - off) / (w - off if across > off else w + off)
	return td * maxf(EDGE_DEPTH, 1.0 - rel * rel)



## The swirl the eddies add at p (m/s): each is the curl of a Gaussian stream
## function, so it has no sources or sinks and its streamlines close on
## themselves. Peak speed is the eddy's strength at one radius from its centre.
func eddy_swirl(p: Vector2) -> Vector2:
	var v := Vector2.ZERO
	if stretch == null:
		return v
	for e_i in stretch.eddies.size():
		var e := stretch.eddies[e_i]
		var rel := p - Vector2(e.x, e.y)
		var g := exp(-rel.length_squared() / (2.0 * e.z * e.z))
		if g < 0.0005:
			continue
		var spin := _eddy_spin[e_i] if e_i < _eddy_spin.size() else 1.0
		v += Vector2(-rel.y, rel.x) / e.z * g * exp(0.5) * e.w * WATER_SPEED * spin
	return v


## How much of the main current is left at p inside the eddies (0..1).
func _eddy_calm(p: Vector2) -> float:
	var keep := 1.0
	for e in stretch.eddies:
		var g := exp(-(p - Vector2(e.x, e.y)).length_squared() / (2.0 * e.z * e.z))
		keep *= 1.0 - EDDY_CALM * g
	return keep


## Slack water tucked beside a fallen log.
func _beside_logs(p: Vector2, v: Vector2) -> Vector2:
	for l in stretch.logs:
		var a := Vector2(l.x, l.y)
		var d := Vector2(l.z, l.w) - a
		var t := clampf((p - a).dot(d) / maxf(d.length_squared(), 0.0001), 0.0, 1.0)
		var dist := p.distance_to(a + d * t)
		if dist < LOG_REACH * 2.5:
			v *= 1.0 - LOG_SLOW * exp(-pow(dist / LOG_REACH, 2.0))
	return v


static func _catmull_rom(pts: PackedVector2Array, per_segment: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var m := pts.size()
	if m < 2:
		return pts
	for i in m - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, m - 1)]
		for s_i in per_segment:
			var u := float(s_i) / per_segment
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * u * u * u))
	out.append(pts[m - 1])
	return out


## Evenly spaced points (`step` m apart) along a polyline.
static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	var carry := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var seg := pts[i + 1] - a
		var l := seg.length()
		var along := step - carry
		while along <= l:
			out.append(a + seg * (along / l))
			along += step
		carry = l - (along - step)
	if out[-1].distance_to(pts[-1]) > step * 0.25:
		out.append(pts[-1])
	return out


static func _box_smooth(a: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(a.size())
	for k in a.size():
		var s := 0.0
		var c := 0
		for o in range(-r, r + 1):
			var kk := k + o
			if kk >= 0 and kk < a.size():
				s += a[kk]
				c += 1
		out[k] = s / c
	return out


func _build_seams() -> void:
	var sp := _speeds()
	var full := SEAM_FULL * WATER_SPEED
	for j in rows:
		var jm := maxi(j - 1, 0) * cols
		var jp := mini(j + 1, rows - 1) * cols
		for i in cols:
			var idx := j * cols + i
			if depth[idx] <= SEAM_DEPTH.x:
				seam[idx] = 0.0
				continue
			var sx := (sp[j * cols + mini(i + 1, cols - 1)] - sp[j * cols + maxi(i - 1, 0)]) / (2.0 * CELL)
			var sy := (sp[jp + i] - sp[jm + i]) / (2.0 * CELL)
			seam[idx] = clampf(Vector2(sx, sy).length() / full, 0.0, 1.0) \
				* smoothstep(SEAM_DEPTH.x, SEAM_DEPTH.y, depth[idx])


func _build_lies() -> void:
	# Fastest water within FOOD_REACH, as a separable max filter.
	var reach := roundi(FOOD_REACH / CELL)
	var hold_speed := HOLD_SPEED * WATER_SPEED
	var food_speed := FOOD_SPEED * WATER_SPEED
	var sp := _speeds()
	var row_max := PackedFloat32Array()
	row_max.resize(cols * rows)
	for j in rows:
		var row := j * cols
		for i in cols:
			var m := 0.0
			for ii in range(maxi(i - reach, 0), mini(i + reach, cols - 1) + 1):
				m = maxf(m, sp[row + ii])
			# Past the edges the nearest cell repeats; it can't raise the max.
			row_max[row + i] = m
	for j in rows:
		for i in cols:
			var idx := j * cols + i
			# Too shallow or too fast to hold in: no lie, whatever the food.
			if depth[idx] <= DEPTH_NEEDED.x or sp[idx] >= hold_speed.y \
					or (not wet.is_empty() and wet[idx] == 0) or is_rock(cell_pos(i, j)):
				lie[idx] = 0.0
				continue
			var near := 0.0
			for jj in range(maxi(j - reach, 0), mini(j + reach, rows - 1) + 1):
				near = maxf(near, row_max[jj * cols + i])
			var hold := 1.0 - smoothstep(hold_speed.x, hold_speed.y, sp[idx])
			var food := smoothstep(food_speed.x, food_speed.y, near)
			var deep := smoothstep(DEPTH_NEEDED.x, DEPTH_NEEDED.y, depth[idx])
			lie[idx] = hold * food * deep


func _speeds() -> PackedFloat32Array:
	var sp := PackedFloat32Array()
	sp.resize(velocity.size())
	for idx in velocity.size():
		sp[idx] = velocity[idx].length()
	return sp


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
