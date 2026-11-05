class_name RiverChannel
extends RefCounted
## The river's line through a whole stretch, worked out once (REQ-0014): the
## smoothed centreline every CHANNEL_STEP m, which way it runs, how far bends
## push the thalweg off centre, how deep the thalweg is and the speed factor
## that keeps the same flow through every cross-section.
##
## Everything here is along the river, so it is cheap for a whole section and
## the same for every chunk of it: a field built in chunks (SectionField) lays
## each chunk from this one channel, so the water matches at every seam.
## RiverFieldBuilder reads it; nothing writes it after _init(). Metres.

## The stretch it was laid from.
var stretch: Stretch
## Half the river's width (m).
var half_width := 0.0
## Centreline points, upstream first, and the unit direction downstream at each.
var points := PackedVector2Array()
var tang := PackedVector2Array()
## Per point: thalweg offset from the centreline (m, + = right of the flow),
## thalweg depth (0..1) and speed factor k (v = k * depth^(2/3)).
var offs := PackedFloat32Array()
var tds := PackedFloat32Array()
var ks := PackedFloat32Array()


func _init(p_stretch: Stretch) -> void:
	stretch = p_stretch
	half_width = stretch.half_width
	var c := _resample(_catmull_rom(stretch.centreline, 24), RiverField.CHANNEL_STEP)
	var n := c.size()
	var w := half_width
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

	offs.resize(n)
	tds.resize(n)
	ks.resize(n)
	var q := 0.0
	for k in n:
		offs[k] = clampf(-curv[k] * w * w * stretch.bend_shift * 0.9, -RiverField.MAX_THALWEG_SHIFT * w, RiverField.MAX_THALWEG_SHIFT * w)
		tds[k] = stretch.depth_at_fraction(cum[k] / cum[n - 1])
		var sum := 0.0
		var across := -w
		while across <= w:
			sum += pow(profile(across, w, offs[k], tds[k]), 1.0 + RiverField.DEPTH_SPEED_EXP)
			across += RiverField.CELL
		if k == 0:
			q = RiverField.WATER_SPEED / pow(tds[0], RiverField.DEPTH_SPEED_EXP) * sum
		ks[k] = q / sum
	points = c


## Depth across the channel: `across` (m, + = right of the flow) from the
## centreline, half-width w, thalweg offset off, thalweg depth td.
static func profile(across: float, w: float, off: float, td: float) -> float:
	var rel := (across - off) / (w - off if across > off else w + off)
	return td * maxf(RiverField.EDGE_DEPTH, 1.0 - rel * rel)


## Which way the river runs at p, and which side of the flow p is on:
## [direction (unit), +1 right or -1 left], from the nearest centreline segment.
func frame_at(p: Vector2) -> Array:
	var best := INF
	var out: Array = [Vector2.RIGHT, 1.0]
	for k in points.size() - 1:
		var a := points[k]
		var d := points[k + 1] - a
		var ap := p - a
		var t := clampf(ap.dot(d) / maxf(d.length_squared(), 0.000001), 0.0, 1.0)
		var dist2 := (ap - d * t).length_squared()
		if dist2 < best:
			best = dist2
			out = [tang[k], 1.0 if d.cross(ap) >= 0.0 else -1.0]
	return out


## The thalweg as points (m), for drawing.
func thalweg() -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in points.size():
		out.append(points[k] + Vector2(-tang[k].y, tang[k].x) * offs[k])
	return out


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
