class_name RiverFieldBuilder
extends RefCounted
## Fills a RiverField's layers (velocity, depth, seams, lies, and for a stretch
## the wet, shore and bend masks). Split from RiverField so the field holds only
## its layers and the read-only queries everyone uses, and this file holds the
## hydraulic rules that make them. The rules are listed at the top of
## river_field.gd; the constants live there too, so tuning stays in one place.
##
## Only RiverField.build() and build_stretch() call it. Everything is in metres.


## A straight reach between two banks, with the field's inputs already set.
static func straight(fld: RiverField) -> void:
	_allocate(fld)
	_prepare_features(fld)
	_build_flow(fld)
	_build_seams(fld)
	_build_lies(fld)


## A winding stretch (fld.stretch already set).
static func winding(fld: RiverField) -> void:
	_allocate(fld)
	_build_channel(fld)
	_build_seams(fld)
	_build_lies(fld)


static func _allocate(fld: RiverField) -> void:
	fld.cols = int(ceilf(fld.width / RiverField.CELL - 0.001)) + 1
	fld.rows = int(ceilf((fld.bottom - fld.top) / RiverField.CELL - 0.001)) + 1
	var n := fld.cols * fld.rows
	fld.velocity.resize(n)
	fld.depth.resize(n)
	fld.seam.resize(n)
	fld.lie.resize(n)


static func _build_flow(fld: RiverField) -> void:
	# Total flow is set by the first column: WATER_SPEED over the thalweg.
	var k0 := RiverField.WATER_SPEED / pow(fld._thalweg_depth.call(0.0), RiverField.DEPTH_SPEED_EXP)
	var q := k0 * _section_sum(fld, 0.0)
	for i in fld.cols:
		var x := i * RiverField.CELL
		# Same flow through every section: v = k * d^(2/3), q = sum(v * d) = k * sum(d^(5/3)).
		var k := q / _section_sum(fld, x)
		for j in fld.rows:
			var p := fld.cell_pos(i, j)
			var d := _bed_depth(fld, p)
			var idx := j * fld.cols + i
			fld.depth[idx] = d
			fld.velocity[idx] = _apply_features(fld, p, Vector2(k * pow(d, RiverField.DEPTH_SPEED_EXP), 0.0))


## Depth of the bed at p: deepest on the thalweg, shelving to the banks.
static func _bed_depth(fld: RiverField, p: Vector2) -> float:
	var ty: float = fld._thalweg_y.call(p.x)
	var td: float = fld._thalweg_depth.call(p.x)
	var reach := (ty - fld.top) if p.y < ty else (fld.bottom - ty)
	var n := clampf(absf(p.y - ty) / maxf(reach, RiverField.CELL * 0.5), 0.0, 1.0)
	return td * maxf(RiverField.EDGE_DEPTH, 1.0 - n * n)


static func _section_sum(fld: RiverField, x: float) -> float:
	var s := 0.0
	for j in fld.rows:
		s += pow(_bed_depth(fld, Vector2(x, fld.top + j * RiverField.CELL)), 1.0 + RiverField.DEPTH_SPEED_EXP)
	return s


## Runs every feature over the current v at p: obstacles bend it, then it is
## calmed and the swirls are added (see RiverFeature).
static func _apply_features(fld: RiverField, p: Vector2, v: Vector2) -> Vector2:
	for f in fld.features:
		v = f.shape_flow(p, v)
	var keep := 1.0
	for f in fld.features:
		keep *= f.calm(p)
	return v * keep + fld.eddy_swirl(p)


static func _prepare_features(fld: RiverField) -> void:
	fld._feature_state.resize(fld.features.size())
	for n in fld.features.size():
		fld._feature_state[n] = fld.features[n].prepare(fld)


## Lays the river along the stretch's centreline. Every cell finds its nearest
## point on the centreline: how far along the river it is and how far across.
## Across the channel the bed is parabolic around the thalweg, which bends
## push toward the outside bank. The current runs along the centreline, with
## the same flow through every cross-section.
static func _build_channel(fld: RiverField) -> void:
	var c := _resample(_catmull_rom(fld.stretch.centreline, 24), RiverField.CHANNEL_STEP)
	var n := c.size()
	var w := fld.stretch.half_width
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
	curv = _box_smooth(curv, roundi(RiverField.CURVE_SMOOTH / RiverField.CHANNEL_STEP))

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
		offs[k] = clampf(-curv[k] * w * w * fld.stretch.bend_shift * 0.9, -RiverField.MAX_THALWEG_SHIFT * w, RiverField.MAX_THALWEG_SHIFT * w)
		tds[k] = fld.stretch.depth_at_fraction(cum[k] / cum[n - 1])
		var sum := 0.0
		var across := -w
		while across <= w:
			sum += pow(_profile(across, w, offs[k], tds[k]), 1.0 + RiverField.DEPTH_SPEED_EXP)
			across += RiverField.CELL
		if k == 0:
			q = RiverField.WATER_SPEED / pow(tds[0], RiverField.DEPTH_SPEED_EXP) * sum
		ks[k] = q / sum

	# Nearest centreline segment for every cell within reach of the river.
	var total := fld.cols * fld.rows
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
		var i0 := maxi(0, floori((minf(a.x, a.x + d.x) - reach) / RiverField.CELL))
		var i1 := mini(fld.cols - 1, ceili((maxf(a.x, a.x + d.x) + reach) / RiverField.CELL))
		var j0 := maxi(0, floori((minf(a.y, a.y + d.y) - reach - fld.top) / RiverField.CELL))
		var j1 := mini(fld.rows - 1, ceili((maxf(a.y, a.y + d.y) + reach - fld.top) / RiverField.CELL))
		for j in range(j0, j1 + 1):
			var py := fld.top + j * RiverField.CELL
			for i in range(i0, i1 + 1):
				var ap := Vector2(i * RiverField.CELL, py) - a
				var t := clampf(ap.dot(d) / l2, 0.0, 1.0)
				var dist2 := (ap - d * t).length_squared()
				var idx := j * fld.cols + i
				if dist2 < best[idx]:
					best[idx] = dist2
					near_k[idx] = k
					near_t[idx] = t
					near_n[idx] = sqrt(dist2) * (1.0 if d.cross(ap) >= 0.0 else -1.0)

	fld.wet.resize(total)
	fld.shore.resize(total)
	fld.bend.resize(total)
	for idx in total:
		var k := near_k[idx]
		fld.velocity[idx] = Vector2.ZERO
		fld.depth[idx] = 0.0
		fld.wet[idx] = 0
		if k < 0:
			fld.shore[idx] = INF
			fld.bend[idx] = 0.0
			continue
		var t := near_t[idx]
		var across := near_n[idx]
		var off := lerpf(offs[k], offs[k + 1], t)
		fld.shore[idx] = absf(across) - w
		fld.bend[idx] = clampf(off / (RiverField.MAX_THALWEG_SHIFT * w), -1.0, 1.0) * signf(across)
		if absf(across) > w:
			continue
		var d := _profile(across, w, off, lerpf(tds[k], tds[k + 1], t))
		var dir := tang[k].lerp(tang[k + 1], t).normalized()
		fld.wet[idx] = 1
		fld.depth[idx] = d
		fld.velocity[idx] = dir * lerpf(ks[k], ks[k + 1], t) * pow(d, RiverField.DEPTH_SPEED_EXP)

	fld.centre = c
	fld.centre_dir = tang
	fld._near_k = near_k
	fld._near_n = near_n
	_prepare_features(fld)
	for j in fld.rows:
		for i in fld.cols:
			var idx := j * fld.cols + i
			if fld.wet[idx] == 0:
				continue
			fld.velocity[idx] = _apply_features(fld, fld.cell_pos(i, j), fld.velocity[idx])

	fld.thalweg = PackedVector2Array()
	for k in n:
		var tp := c[k] + Vector2(-tang[k].y, tang[k].x) * offs[k]
		if tp.x >= 0.0 and tp.y >= fld.top and tp.x <= fld.width and tp.y <= fld.bottom:
			fld.thalweg.append(tp)


## Depth across the channel: `across` (m, + = right of the flow) from the
## centreline, half-width w, thalweg offset off, thalweg depth td.
static func _profile(across: float, w: float, off: float, td: float) -> float:
	var rel := (across - off) / (w - off if across > off else w + off)
	return td * maxf(RiverField.EDGE_DEPTH, 1.0 - rel * rel)


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


static func _build_seams(fld: RiverField) -> void:
	var sp := _speeds(fld)
	var full := RiverField.SEAM_FULL * RiverField.WATER_SPEED
	for j in fld.rows:
		var jm := maxi(j - 1, 0) * fld.cols
		var jp := mini(j + 1, fld.rows - 1) * fld.cols
		for i in fld.cols:
			var idx := j * fld.cols + i
			if fld.depth[idx] <= RiverField.SEAM_DEPTH.x:
				fld.seam[idx] = 0.0
				continue
			var sx := (sp[j * fld.cols + mini(i + 1, fld.cols - 1)] - sp[j * fld.cols + maxi(i - 1, 0)]) / (2.0 * RiverField.CELL)
			var sy := (sp[jp + i] - sp[jm + i]) / (2.0 * RiverField.CELL)
			fld.seam[idx] = clampf(Vector2(sx, sy).length() / full, 0.0, 1.0) \
				* smoothstep(RiverField.SEAM_DEPTH.x, RiverField.SEAM_DEPTH.y, fld.depth[idx])


static func _build_lies(fld: RiverField) -> void:
	# Fastest water within FOOD_REACH, as a separable max filter.
	var reach := roundi(RiverField.FOOD_REACH / RiverField.CELL)
	var hold_speed := RiverField.HOLD_SPEED * RiverField.WATER_SPEED
	var food_speed := RiverField.FOOD_SPEED * RiverField.WATER_SPEED
	var sp := _speeds(fld)
	var row_max := PackedFloat32Array()
	row_max.resize(fld.cols * fld.rows)
	for j in fld.rows:
		var row := j * fld.cols
		for i in fld.cols:
			var m := 0.0
			for ii in range(maxi(i - reach, 0), mini(i + reach, fld.cols - 1) + 1):
				m = maxf(m, sp[row + ii])
			# Past the edges the nearest cell repeats; it can't raise the max.
			row_max[row + i] = m
	for j in fld.rows:
		for i in fld.cols:
			var idx := j * fld.cols + i
			# Too shallow or too fast to hold in: no lie, whatever the food.
			if fld.depth[idx] <= RiverField.DEPTH_NEEDED.x or sp[idx] >= hold_speed.y \
					or (not fld.wet.is_empty() and fld.wet[idx] == 0) or fld.is_solid(fld.cell_pos(i, j)):
				fld.lie[idx] = 0.0
				continue
			var near := 0.0
			for jj in range(maxi(j - reach, 0), mini(j + reach, fld.rows - 1) + 1):
				near = maxf(near, row_max[jj * fld.cols + i])
			var hold := 1.0 - smoothstep(hold_speed.x, hold_speed.y, sp[idx])
			var food := smoothstep(food_speed.x, food_speed.y, near)
			var deep := smoothstep(RiverField.DEPTH_NEEDED.x, RiverField.DEPTH_NEEDED.y, fld.depth[idx])
			fld.lie[idx] = hold * food * deep


static func _speeds(fld: RiverField) -> PackedFloat32Array:
	var sp := PackedFloat32Array()
	sp.resize(fld.velocity.size())
	for idx in fld.velocity.size():
		sp[idx] = fld.velocity[idx].length()
	return sp
