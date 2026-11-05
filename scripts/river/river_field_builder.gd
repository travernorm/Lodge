class_name RiverFieldBuilder
extends RefCounted
## Fills a RiverField's layers (velocity, depth, seams, lies, and for a stretch
## the wet, shore and bend masks). Split from RiverField so the field holds only
## its layers and the read-only queries everyone uses, and this file holds the
## hydraulic rules that make them. The rules are listed at the top of
## river_field.gd; the constants live there too, so tuning stays in one place.
##
## A straight reach is built at once with straight(). A winding field is a job
## (REQ-0014): new() it with the field and its RiverChannel, then call step()
## until it returns true, so a chunk of a section can be built a little each
## frame without a hitch (the scene keeps the clock; models don't, R1). run()
## does it all at once.
##
## Only RiverField and SectionField make builders. Everything is in metres.

## How far (m) past a field's edge a feature can still change its water: the
## builder skips features whose reach() misses the field by more.
const FEATURE_MARGIN := 1.0

var _fld: RiverField
var _ch: RiverChannel
## Stages in order: [Callable(int), units]. Each call does one unit (a
## centreline segment or a row of cells).
var _stages: Array = []
var _stage := 0
var _at := 0
## The features that reach this field, and what each prepare() returned.
var _feats: Array[RiverFeature] = []
var _states := PackedFloat32Array()
## Per-build scratch.
var _segments := PackedInt32Array()
var _boxes: Array[Rect2i] = []
var _best := PackedFloat32Array()
var _near_t := PackedFloat32Array()
var _sp := PackedFloat32Array()
var _row_max := PackedFloat32Array()


## A winding field: `fld` has its stretch, channel and bounds set.
func _init(fld: RiverField, channel: RiverChannel) -> void:
	_fld = fld
	_ch = channel
	if channel == null:
		return  # a straight reach: straight() runs the row stages itself
	_allocate(fld)
	var n := fld.cols * fld.rows
	fld.wet.resize(n)
	fld.wet.fill(0)
	fld.shore.resize(n)
	fld.bend.resize(n)
	fld._near_k.resize(n)
	fld._near_k.fill(-1)
	fld._near_n.resize(n)
	_best.resize(n)
	_best.fill(INF)
	_near_t.resize(n)
	# Each segment's reach, as a box of cells (inclusive), for the segments
	# that reach this field at all.
	var reach := _ch.half_width + 3.0
	for k in _ch.points.size() - 1:
		var a := _ch.points[k]
		var b := a + (_ch.points[k + 1] - a)  # as the whole build rounds it
		var i0 := maxi(0, floori((minf(a.x, b.x) - reach - fld.left) / RiverField.CELL))
		var i1 := mini(fld.cols - 1, ceili((maxf(a.x, b.x) + reach - fld.left) / RiverField.CELL))
		var j0 := maxi(0, floori((minf(a.y, b.y) - reach - fld.top) / RiverField.CELL))
		var j1 := mini(fld.rows - 1, ceili((maxf(a.y, b.y) + reach - fld.top) / RiverField.CELL))
		if i0 <= i1 and j0 <= j1:
			_segments.append(k)
			_boxes.append(Rect2i(i0, j0, i1 - i0, j1 - j0))
	if _segments.is_empty():
		# No river within reach: dry land, nothing to lay.
		fld.shore.fill(INF)
		fld.velocity.fill(Vector2.ZERO)
		fld.depth.fill(0.0)
		fld.seam.fill(0.0)
		fld.lie.fill(0.0)
		fld.bend.fill(0.0)
		_stages = [[_finish, 1]]
		return
	_stages = [
		[_nearest_row, fld.rows],
		[_fill_row, fld.rows],
		[_prepare, 1],
		[_features_row, fld.rows],
		[_seam_row, fld.rows],
		[_row_max_row, fld.rows],
		[_lie_row, fld.rows],
		[_finish, 1],
	]


## A straight reach between two banks, with the field's inputs already set.
static func straight(fld: RiverField) -> void:
	_allocate(fld)
	_prepare_features(fld)
	_build_flow(fld)
	var b := RiverFieldBuilder.new(fld, null)
	b._sp = _speeds(fld)
	for j in fld.rows:
		b._seam_row(j)
	for j in fld.rows:
		b._row_max_row(j)
	for j in fld.rows:
		b._lie_row(j)


## Does up to `units` pieces of work (a row of cells each, about a
## millisecond). True when the field is finished.
func step(units: int) -> bool:
	while _stage < _stages.size() and units > 0:
		var stage: Array = _stages[_stage]
		if _at < stage[1]:
			(stage[0] as Callable).call(_at)
			_at += 1
			units -= 1
		if _at >= stage[1]:
			_stage += 1
			_at = 0
	return done()


func done() -> bool:
	return _stage >= _stages.size()


## Builds the whole field now.
func run() -> void:
	step(1 << 30)


static func _allocate(fld: RiverField) -> void:
	fld.cols = int(ceilf(fld.width / RiverField.CELL - 0.001)) + 1
	fld.rows = int(ceilf((fld.bottom - fld.top) / RiverField.CELL - 0.001)) + 1
	var n := fld.cols * fld.rows
	fld.velocity.resize(n)
	fld.depth.resize(n)
	fld.seam.resize(n)
	fld.lie.resize(n)


# --- Straight reach -----------------------------------------------------------

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
			fld.velocity[idx] = _apply_features(p, Vector2(k * pow(d, RiverField.DEPTH_SPEED_EXP), 0.0),
				fld.features, fld._feature_state)


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


static func _prepare_features(fld: RiverField) -> void:
	fld._feature_state.resize(fld.features.size())
	for n in fld.features.size():
		fld._feature_state[n] = fld.features[n].prepare(fld)


## Runs the features over the current v at p: obstacles bend it, then it is
## calmed and the swirls are added (see RiverFeature).
static func _apply_features(p: Vector2, v: Vector2, feats: Array[RiverFeature],
		states: PackedFloat32Array) -> Vector2:
	for f in feats:
		v = f.shape_flow(p, v)
	var keep := 1.0
	var swirl := Vector2.ZERO
	for n in feats.size():
		keep *= feats[n].calm(p)
		swirl += feats[n].swirl(p, states[n] if n < states.size() else 1.0)
	return v * keep + swirl


# --- Winding field, in stages -------------------------------------------------
# Every cell finds its nearest point on the centreline: how far along the river
# it is and how far across. Across the channel the bed is parabolic around the
# thalweg, which bends push toward the outside bank. The current runs along the
# centreline, with the same flow through every cross-section.

## Nearest centreline segment for every cell within reach of the river, one
## row at a time. Segments are tried in order, so ties go the same way however
## the field is cut into chunks.
func _nearest_row(j: int) -> void:
	var fld := _fld
	var py := fld.top + j * RiverField.CELL
	for s in _segments.size():
		var box := _boxes[s]
		if j < box.position.y or j > box.end.y:
			continue
		var k := _segments[s]
		var a := _ch.points[k]
		var d := _ch.points[k + 1] - a
		var l2 := maxf(d.length_squared(), 0.000001)
		for i in range(box.position.x, box.end.x + 1):
			var ap := Vector2(fld.left + i * RiverField.CELL, py) - a
			var t := clampf(ap.dot(d) / l2, 0.0, 1.0)
			var dist2 := (ap - d * t).length_squared()
			var idx := j * fld.cols + i
			if dist2 < _best[idx]:
				_best[idx] = dist2
				fld._near_k[idx] = k
				_near_t[idx] = t
				fld._near_n[idx] = sqrt(dist2) * (1.0 if d.cross(ap) >= 0.0 else -1.0)


func _fill_row(j: int) -> void:
	var fld := _fld
	var w := _ch.half_width
	for i in fld.cols:
		var idx := j * fld.cols + i
		var k := fld._near_k[idx]
		fld.velocity[idx] = Vector2.ZERO
		fld.depth[idx] = 0.0
		if k < 0:
			fld.shore[idx] = INF
			fld.bend[idx] = 0.0
			continue
		var t := _near_t[idx]
		var across := fld._near_n[idx]
		var off := lerpf(_ch.offs[k], _ch.offs[k + 1], t)
		fld.shore[idx] = absf(across) - w
		fld.bend[idx] = clampf(off / (RiverField.MAX_THALWEG_SHIFT * w), -1.0, 1.0) * signf(across)
		if absf(across) > w:
			continue
		var d := RiverChannel.profile(across, w, off, lerpf(_ch.tds[k], _ch.tds[k + 1], t))
		var dir := _ch.tang[k].lerp(_ch.tang[k + 1], t).normalized()
		fld.wet[idx] = 1
		fld.depth[idx] = d
		fld.velocity[idx] = dir * lerpf(_ch.ks[k], _ch.ks[k + 1], t) * pow(d, RiverField.DEPTH_SPEED_EXP)


## Works out each feature's state (an eddy's spin) and which features reach
## this field.
func _prepare(_unit: int) -> void:
	var fld := _fld
	_prepare_features(fld)
	var area := fld.bounds().grow(FEATURE_MARGIN)
	for n in fld.features.size():
		var f := fld.features[n]
		var r := f.reach()
		if r.size.x < 0.0 or (r.has_area() and area.intersects(r, true)):
			_feats.append(f)
			_states.append(fld._feature_state[n])


func _features_row(j: int) -> void:
	var fld := _fld
	if _feats.is_empty():
		return
	for i in fld.cols:
		var idx := j * fld.cols + i
		if fld.wet[idx] == 1:
			fld.velocity[idx] = _apply_features(fld.cell_pos(i, j), fld.velocity[idx], _feats, _states)


func _seam_row(j: int) -> void:
	var fld := _fld
	if _sp.is_empty():
		_sp = _speeds(fld)
	var full := RiverField.SEAM_FULL * RiverField.WATER_SPEED
	var jm := maxi(j - 1, 0) * fld.cols
	var jp := mini(j + 1, fld.rows - 1) * fld.cols
	for i in fld.cols:
		var idx := j * fld.cols + i
		if fld.depth[idx] <= RiverField.SEAM_DEPTH.x:
			fld.seam[idx] = 0.0
			continue
		var sx := (_sp[j * fld.cols + mini(i + 1, fld.cols - 1)] - _sp[j * fld.cols + maxi(i - 1, 0)]) / (2.0 * RiverField.CELL)
		var sy := (_sp[jp + i] - _sp[jm + i]) / (2.0 * RiverField.CELL)
		fld.seam[idx] = clampf(Vector2(sx, sy).length() / full, 0.0, 1.0) \
			* smoothstep(RiverField.SEAM_DEPTH.x, RiverField.SEAM_DEPTH.y, fld.depth[idx])


## Lies, part 1: the fastest water within FOOD_REACH along the row (the first
## pass of a separable max filter).
func _row_max_row(j: int) -> void:
	var fld := _fld
	var reach := roundi(RiverField.FOOD_REACH / RiverField.CELL)
	if _row_max.is_empty():
		_row_max.resize(fld.cols * fld.rows)
	var row := j * fld.cols
	for i in fld.cols:
		var m := 0.0
		for ii in range(maxi(i - reach, 0), mini(i + reach, fld.cols - 1) + 1):
			m = maxf(m, _sp[row + ii])
		# Past the edges the nearest cell repeats; it can't raise the max.
		_row_max[row + i] = m


func _lie_row(j: int) -> void:
	var fld := _fld
	var reach := roundi(RiverField.FOOD_REACH / RiverField.CELL)
	var hold_speed := RiverField.HOLD_SPEED * RiverField.WATER_SPEED
	var food_speed := RiverField.FOOD_SPEED * RiverField.WATER_SPEED
	for i in fld.cols:
		var idx := j * fld.cols + i
		# Too shallow or too fast to hold in: no lie, whatever the food.
		if fld.depth[idx] <= RiverField.DEPTH_NEEDED.x or _sp[idx] >= hold_speed.y \
				or (not fld.wet.is_empty() and fld.wet[idx] == 0) or fld.is_solid(fld.cell_pos(i, j)):
			fld.lie[idx] = 0.0
			continue
		var near := 0.0
		for jj in range(maxi(j - reach, 0), mini(j + reach, fld.rows - 1) + 1):
			near = maxf(near, _row_max[jj * fld.cols + i])
		var hold := 1.0 - smoothstep(hold_speed.x, hold_speed.y, _sp[idx])
		var food := smoothstep(food_speed.x, food_speed.y, near)
		var deep := smoothstep(RiverField.DEPTH_NEEDED.x, RiverField.DEPTH_NEEDED.y, fld.depth[idx])
		fld.lie[idx] = hold * food * deep


func _finish(_unit: int) -> void:
	var fld := _fld
	fld.thalweg = PackedVector2Array()
	for tp in _ch.thalweg():
		if tp.x >= fld.left and tp.y >= fld.top and tp.x <= fld.left + fld.width and tp.y <= fld.bottom:
			fld.thalweg.append(tp)
	_best = PackedFloat32Array()
	_near_t = PackedFloat32Array()
	_sp = PackedFloat32Array()
	_row_max = PackedFloat32Array()


static func _speeds(fld: RiverField) -> PackedFloat32Array:
	var sp := PackedFloat32Array()
	sp.resize(fld.velocity.size())
	for idx in fld.velocity.size():
		sp[idx] = fld.velocity[idx].length()
	return sp
