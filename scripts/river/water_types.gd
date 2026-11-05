class_name WaterTypes
extends RefCounted
## Every wet cell of a river field sorted into one water type (REQ-0010), from
## the layers the field already has: speed, depth, seam strength, solid cells
## and which way the river runs. It names no feature kind, so any feature
## gives typed water for free. Built once per field; never written after.
##   var types := WaterTypes.classify(field, rules)
##   types.type_at(p)   # a WaterTypeRules.WaterType, or NONE on the bank

## No water here.
const NONE := -1

var cols := 0
var rows := 0
var left := 0.0
var top := 0.0
## Per cell: a WaterTypeRules.WaterType, or 255 for no water.
var cells := PackedByteArray()


static func classify(field: RiverField, rules: WaterTypeRules) -> WaterTypes:
	var out := WaterTypes.new()
	out.cols = field.cols
	out.rows = field.rows
	out.left = field.left
	out.top = field.top
	out.cells.resize(field.cols * field.rows)
	out.cells.fill(255)
	for j in field.rows:
		for i in field.cols:
			var p := field.cell_pos(i, j)
			if field.is_water(p):
				out.cells[j * field.cols + i] = _type_of(field, rules, p, j * field.cols + i)
	return out


## The type of one point (m) without sorting the whole field: what the fish
## generator asks for each lie. NONE off the water.
static func at(field: RiverField, rules: WaterTypeRules, p: Vector2) -> int:
	if not field.is_water(p):
		return NONE
	var i := clampi(roundi((p.x - field.left) / RiverField.CELL), 0, field.cols - 1)
	var j := clampi(roundi((p.y - field.top) / RiverField.CELL), 0, field.rows - 1)
	return _type_of(field, rules, p, j * field.cols + i)


## The type at `p` (m): the nearest cell's, or NONE off the water.
func type_at(p: Vector2) -> int:
	var i := roundi((p.x - left) / RiverField.CELL)
	var j := roundi((p.y - top) / RiverField.CELL)
	if i < 0 or j < 0 or i >= cols or j >= rows:
		return NONE
	var t := cells[j * cols + i]
	return NONE if t == 255 else t


## How many cells of each type, indexed by WaterTypeRules.WaterType.
func counts() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(WaterTypeRules.WaterType.size())
	for t in cells:
		if t != 255:
			out[t] += 1
	return out


static func _type_of(field: RiverField, r: WaterTypeRules, p: Vector2, idx: int) -> int:
	var full := RiverField.WATER_SPEED
	var v := field.velocity[idx]
	var dir: Vector2 = field.flow_frame(p)[0]
	var speed := v.length() / full
	var d := field.depth[idx]
	if v.dot(dir) < -r.eddy_back_speed * full:
		return WaterTypeRules.WaterType.EDDY
	if speed < r.pocket_speed and _solid_upstream(field, p, dir, r.pocket_reach):
		return WaterTypeRules.WaterType.POCKET
	if field.seam[idx] >= r.seam_min:
		return WaterTypeRules.WaterType.SEAM
	if d >= r.pool_depth and speed <= r.pool_speed:
		return WaterTypeRules.WaterType.POOL
	if d >= r.tail_min_depth and d < r.pool_depth \
			and field.depth_at(p + dir * r.tail_look) < d - r.tail_drop \
			and _pool_upstream(field, p, dir, r):
		return WaterTypeRules.WaterType.TAIL_OUT
	if d <= r.riffle_depth and speed >= r.riffle_speed:
		return WaterTypeRules.WaterType.RIFFLE
	return WaterTypeRules.WaterType.RUN


static func _solid_upstream(field: RiverField, p: Vector2, dir: Vector2, reach: float) -> bool:
	var s := RiverField.CELL
	while s <= reach + 0.001:
		if field.is_solid(p - dir * s):
			return true
		s += RiverField.CELL
	return false


static func _pool_upstream(field: RiverField, p: Vector2, dir: Vector2, r: WaterTypeRules) -> bool:
	var s := 1.0
	while s <= r.tail_reach:
		if field.depth_at(p - dir * s) >= r.pool_depth:
			return true
		s += 1.0
	return false
