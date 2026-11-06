class_name LineView
extends Node2D
## How the fly line is drawn (architecture step A): the curved line, the wake
## a dragging fly cuts, and the line's colour under tension in a fight. A view
## helper: each function draws onto the canvas item it is given, in world
## pixels, so the fishing controller keeps one _draw(). Never instanced.

const COL_LINE := Color("d8cfa6")
const COL_LINE_TIGHT := Color("f2a65a")
const COL_LINE_DANGER := Color("e8553a")
const COL_WAKE := Color(1, 1, 1, 0.6)


## A line from a through b to c (b is where the curve bends, not a control point).
static func curve(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, color := COL_LINE) -> void:
	var control := 2.0 * b - (a + c) * 0.5
	var points := PackedVector2Array()
	for i in 15:
		var t := float(i) / 14.0
		var p := a.lerp(control, t).lerp(control.lerp(c, t), t)
		points.append(p.floor() + Vector2(0.5, 0.5))
	ci.draw_polyline(points, color, 1.0)


## The V of wake behind a fly (px) that drags, stronger as `drag` grows.
static func wake(ci: CanvasItem, fly: Vector2, drag: float) -> void:
	if drag <= 0.3:
		return
	var back := fly.floor()
	var col := Color(COL_WAKE, minf(1.0, drag) * COL_WAKE.a)
	ci.draw_line(back + Vector2(-1, -1), back + Vector2(-4, -3), col, 1.0)
	ci.draw_line(back + Vector2(-1, 2), back + Vector2(-4, 4), col, 1.0)


## The line's colour in a fight: it warms as the tension nears breaking.
static func tension_colour(tension: float) -> Color:
	if tension > 0.85:
		return COL_LINE_DANGER
	return COL_LINE_TIGHT if tension > 0.6 else COL_LINE
