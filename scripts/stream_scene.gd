extends Node2D
## Placeholder test stream: one screen, a fast riffle on the left feeding a slow
## pool on the right. Everything is drawn with primitives so casting feel can be
## tuned before any real art exists. Swap in Aseprite tiles later.
##
## The angler stands on the near (bottom) bank facing upstream across the water.

const VIEW := Vector2(320, 200)
const BANK_TOP := 58.0
const BANK_BOTTOM := 148.0
const RIFFLE_END_X := 130.0

const RIFFLE_SPEED := 55.0  # px/s at mid-channel
const POOL_SPEED := 16.0
const EDGE_FACTOR := 0.35  # current near the banks, as a fraction of mid-channel

const ANGLER_SPEED := 40.0
const ROD_LENGTH := 26.0

const COL_GRASS := Color("4b6b3a")
const COL_TUFT := Color("5f8446")
const COL_GRAVEL := Color("8a7e62")
const COL_WATER := Color("3f6e7a")
const COL_POOL := Color("2c5260")
const COL_RIFFLE := Color("5e8f96")
const COL_FOAM := Color("c9dcd6")
const COL_STREAK := Color("4f8290")
const COL_WADERS := Color("5a5a48")
const COL_JACKET := Color("c26a3a")
const COL_HAT := Color("6b4a2a")
const COL_SKIN := Color("e0b48a")
const COL_ROD := Color("e8d8a8")

var angler_pos := Vector2(160, BANK_BOTTOM + 16)

var _streaks: Array[Vector2] = []
var _tufts: Array[Vector2] = []
var _rng := RandomNumberGenerator.new()
@onready var _cast: Node = get_node_or_null(^"Cast")


func _ready() -> void:
	_rng.seed = 1979
	for i in 70:
		_streaks.append(_random_water_point())
	for i in 40:
		var y := _rng.randf_range(0, BANK_TOP - 8) if i % 2 == 0 else _rng.randf_range(BANK_BOTTOM + 8, VIEW.y)
		_tufts.append(Vector2(_rng.randf_range(0, VIEW.x), y).floor())


func _process(delta: float) -> void:
	var move := Controls.move_vector() if _cast == null or _cast.allows_walking() else Vector2.ZERO
	angler_pos.x = clampf(angler_pos.x + move.x * ANGLER_SPEED * delta, 12.0, VIEW.x - 12.0)

	for i in _streaks.size():
		var s := _streaks[i] + flow_at(_streaks[i]) * delta
		if s.x > VIEW.x + 8.0:
			s = _random_water_point()
			s.x = -8.0
		_streaks[i] = s
	queue_redraw()


## Current velocity (px/s) at a point on screen. The fly's drift will use this,
## and mending exists to fight the difference between the fly's lane and the line's.
func flow_at(p: Vector2) -> Vector2:
	if p.y < BANK_TOP or p.y > BANK_BOTTOM:
		return Vector2.ZERO
	var half := (BANK_BOTTOM - BANK_TOP) * 0.5
	var mid := BANK_TOP + half
	var channel := 1.0 - absf(p.y - mid) / half  # 1 mid-channel, 0 at banks
	var speed := lerpf(RIFFLE_SPEED, POOL_SPEED, smoothstep(RIFFLE_END_X - 30.0, RIFFLE_END_X + 30.0, p.x))
	speed *= lerpf(EDGE_FACTOR, 1.0, channel)
	return Vector2(speed, 0.0)


func is_water(p: Vector2) -> bool:
	return p.y >= BANK_TOP and p.y <= BANK_BOTTOM


func rod_tip() -> Vector2:
	return hand_position() + _rod_direction() * ROD_LENGTH


func hand_position() -> Vector2:
	return angler_pos + Vector2(3, -9)


func _random_water_point() -> Vector2:
	return Vector2(_rng.randf_range(0, VIEW.x), _rng.randf_range(BANK_TOP + 3, BANK_BOTTOM - 3))


## The casting controller poses the rod during a cast; otherwise the right stick
## aims the tip.
func _rod_direction() -> Vector2:
	if _cast != null:
		var pose: Vector2 = _cast.rod_pose()
		if pose != Vector2.ZERO:
			return pose
	var stick := Controls.rod_vector()
	if stick.length() > 0.25:
		return stick.normalized()
	return Vector2(0.45, -1.0).normalized()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), COL_GRASS)
	for t in _tufts:
		draw_rect(Rect2(t, Vector2(1, 2)), COL_TUFT)
		draw_rect(Rect2(t + Vector2(2, 1), Vector2(1, 1)), COL_TUFT)

	draw_rect(Rect2(0, BANK_TOP - 5, VIEW.x, 5), COL_GRAVEL)
	draw_rect(Rect2(0, BANK_BOTTOM, VIEW.x, 6), COL_GRAVEL)
	draw_rect(Rect2(0, BANK_TOP, VIEW.x, BANK_BOTTOM - BANK_TOP), COL_WATER)
	draw_rect(Rect2(RIFFLE_END_X, BANK_TOP + 12, VIEW.x - RIFFLE_END_X, BANK_BOTTOM - BANK_TOP - 24), COL_POOL)
	draw_rect(Rect2(0, BANK_TOP + 8, RIFFLE_END_X - 24, BANK_BOTTOM - BANK_TOP - 16), COL_RIFFLE)

	for s in _streaks:
		var speed := flow_at(s).x
		var length := clampf(speed * 0.12, 1.0, 7.0)
		var col := COL_FOAM if s.x < RIFFLE_END_X - 24 else COL_STREAK
		draw_line(s.floor(), (s + Vector2(length, 0)).floor(), col, 1.0)

	_draw_angler()


func _draw_angler() -> void:
	var p := angler_pos.floor()
	draw_rect(Rect2(p + Vector2(-3, -6), Vector2(6, 6)), COL_WADERS)
	draw_rect(Rect2(p + Vector2(-3, -12), Vector2(6, 6)), COL_JACKET)
	draw_rect(Rect2(p + Vector2(-2, -16), Vector2(4, 4)), COL_SKIN)
	draw_rect(Rect2(p + Vector2(-3, -17), Vector2(6, 2)), COL_HAT)
	draw_line(hand_position().floor(), rod_tip().floor(), COL_ROD, 1.0)
