class_name RestingLies
extends RefCounted
## Where a trout rests (REQ-0011): deep, slow water with cover, like the
## undercut bank on the outside of a bend. The river field's own lie score
## (RiverField.lie) is a feeding score: slow water with fast water close by.
## Together they say where a fish could hold.
##
## It reads the field's layers once and never changes the field. Scores run
## 0 to 1, one per field cell.

## Depth (0..1 of the reach's deepest) where resting water starts and where it's
## as good as it gets.
const DEPTH := Vector2(0.4, 0.75)
## Cover: a cell gets COVER_BASE, plus the rest as it nears the outside of a
## bend (the cut bank).
const COVER_BASE := 0.6

var field: RiverField
## Resting score per field cell, 0 to 1.
var rest := PackedFloat32Array()


func _init(p_field: RiverField) -> void:
	field = p_field
	if field == null:
		return
	var hold := RiverField.HOLD_SPEED * RiverField.WATER_SPEED
	var has_bend := field.bend.size() == field.cols * field.rows
	rest.resize(field.cols * field.rows)
	for j in field.rows:
		for i in field.cols:
			var idx := j * field.cols + i
			var p := field.cell_pos(i, j)
			if not field.is_water(p) or field.is_solid(p):
				rest[idx] = 0.0
				continue
			var deep := smoothstep(DEPTH.x, DEPTH.y, field.depth[idx])
			var slow := 1.0 - smoothstep(hold.x, hold.y, field.velocity[idx].length())
			var outside := maxf(field.bend[idx], 0.0) if has_bend else 0.0
			rest[idx] = clampf(deep * slow * (COVER_BASE + (1.0 - COVER_BASE) * outside), 0.0, 1.0)


## Resting score at p (m), 0 on land.
func rest_at(p: Vector2) -> float:
	return _cell(rest, p)


## The better of the feeding and resting scores at p (m).
func score_at(p: Vector2) -> float:
	return maxf(field.lie_at(p), rest_at(p)) if field != null else 0.0


## True when the resting score beats the feeding score at p (m).
func is_resting(p: Vector2) -> bool:
	return field != null and rest_at(p) > field.lie_at(p)


func _cell(layer: PackedFloat32Array, p: Vector2) -> float:
	if field == null or layer.is_empty() or not field.is_water(p):
		return 0.0
	var i := clampi(roundi((p.x - field.left) / RiverField.CELL), 0, field.cols - 1)
	var j := clampi(roundi((p.y - field.top) / RiverField.CELL), 0, field.rows - 1)
	return layer[j * field.cols + i]
