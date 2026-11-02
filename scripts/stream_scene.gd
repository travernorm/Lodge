extends Node2D
## Placeholder test stream: one screen, a fast riffle on the left feeding a slow
## pool on the right, with a boulder at the head of the pool. Everything is drawn
## with primitives so casting feel can be tuned before any real art exists. Swap
## in Aseprite tiles later.
##
## The current comes from a RiverField (scripts/river/river_field.gd): the
## thalweg (deepest, fastest line), slow edges, the boulder's cushion, pocket and
## seams, and where trout would hold. The drift, the streaks and the water colour
## all read that one field.
##
## Units (REQ-0001): the river's layout and the field work in metres; this scene
## draws in pixels through WorldScale. Fishing reads river.flow_at() and
## river.is_water() in metres. flow_at() and is_water() below are screen-space
## helpers (pixels in and out) for the things still placed in pixels: the cast's
## fly position and the drifting streaks.
##
## The angler stands on the near (bottom) bank facing upstream across the water.

const VIEW := Vector2(320, 200)

# River layout, in metres. One screen is 40 m by 25 m.
const REACH_M := 40.0
const BANK_TOP_M := 7.25  # far bank
const BANK_BOTTOM_M := 18.5  # near bank: about 11 m of water
const RIFFLE_END_M := 16.25  # where the riffle drops into the pool
## Boulders: x, y = centre, z = radius, in metres.
const ROCKS_M: Array[Vector3] = [Vector3(17.75, 11.25, 0.625)]

# The same banks in screen pixels, for drawing and for code not yet in metres.
const BANK_TOP := BANK_TOP_M * WorldScale.PX_PER_M
const BANK_BOTTOM := BANK_BOTTOM_M * WorldScale.PX_PER_M

## Water faster than this fraction of RiverField.WATER_SPEED shows white foam streaks.
const FOAM_SPEED := 36.0 / 55.0
const STREAK_COUNT := 90
const STREAK_LIFE := Vector2(3.0, 8.0)

const ANGLER_SPEED := 40.0
const ROD_LENGTH := 26.0

const COL_GRASS := Color("4b6b3a")
const COL_TUFT := Color("5f8446")
const COL_GRAVEL := Color("8a7e62")
const COL_WATER := Color("3f6e7a")
const COL_POOL := Color("2c5260")
const COL_DEEP := Color("244550")
const COL_RIFFLE := Color("5e8f96")
const COL_SHALLOW := Color("6f9188")
const COL_ROCK := Color("6d6a5e")
const COL_ROCK_LIGHT := Color("8f8a78")
const COL_ROCK_DARK := Color("4f4c43")
const COL_FOAM := Color("c9dcd6")
const COL_STREAK := Color("4f8290")
const COL_WADERS := Color("5a5a48")
const COL_JACKET := Color("c26a3a")
const COL_HAT := Color("6b4a2a")
const COL_SKIN := Color("e0b48a")
const COL_ROD := Color("e8d8a8")

var angler_pos := Vector2(160, BANK_BOTTOM + 16)
var river := _make_river()

var _streaks: Array[Vector2] = []
var _streak_life: Array[float] = []
var _water_tex: ImageTexture
var _tufts: Array[Vector2] = []
var _rng := RandomNumberGenerator.new()
@onready var _cast: Node = get_node_or_null(^"Cast")


func _ready() -> void:
	add_to_group(&"stream")
	_rng.seed = 1979
	_water_tex = _make_water_texture()
	for i in STREAK_COUNT:
		_streaks.append(_random_water_point())
		_streak_life.append(_rng.randf_range(0.0, STREAK_LIFE.y))
	for i in 40:
		var y := _rng.randf_range(0, BANK_TOP - 8) if i % 2 == 0 else _rng.randf_range(BANK_BOTTOM + 8, VIEW.y)
		_tufts.append(Vector2(_rng.randf_range(0, VIEW.x), y).floor())


func _process(delta: float) -> void:
	var move := Controls.move_vector() if _cast == null or _cast.allows_walking() else Vector2.ZERO
	angler_pos.x = clampf(angler_pos.x + move.x * ANGLER_SPEED * delta, 12.0, VIEW.x - 12.0)

	for i in _streaks.size():
		var s := _streaks[i]
		s += flow_at(s) * delta
		_streak_life[i] -= delta
		if s.x > VIEW.x + 2.0:
			# Leaving downstream: feed a new one in at the top of the screen.
			s = _random_water_point()
			s.x = 0.0
			_streak_life[i] = _rng.randf_range(STREAK_LIFE.x, STREAK_LIFE.y)
		elif _streak_life[i] <= 0.0 or not is_water(s):
			# Faded, or swirled into the rock or onto the bank.
			s = _random_water_point()
			_streak_life[i] = _rng.randf_range(STREAK_LIFE.x, STREAK_LIFE.y)
		_streaks[i] = s
	queue_redraw()


## Current velocity (px/s) at a point on screen (px).
## Pixel helper over river.flow_at() (metres), for screen-space callers.
func flow_at(p: Vector2) -> Vector2:
	return WorldScale.vec_to_px(river.flow_at(WorldScale.vec_to_m(p)))


## Pixel helper over river.is_water() (metres), for screen-space callers.
func is_water(p: Vector2) -> bool:
	return river.is_water(WorldScale.vec_to_m(p))


## Where the deepest, fastest line runs (m): it drifts from the far side of the
## riffle toward the near bank through the pool.
func thalweg_y(x: float) -> float:
	return lerpf(11.75, 13.25, smoothstep(7.5, 30.0, x))


## How deep the thalweg is (1 = deepest) at x (m): a shallow riffle dropping into
## the pool, which shallows again into a tail-out at the right edge.
func thalweg_depth(x: float) -> float:
	return lerpf(0.35, 1.0, smoothstep(RIFFLE_END_M - 3.75, RIFFLE_END_M + 5.0, x)) \
		- 0.2 * smoothstep(33.75, 41.25, x)


func _make_river() -> RiverField:
	var r := RiverField.new()
	r.build(BANK_TOP_M, BANK_BOTTOM_M, REACH_M, thalweg_y, thalweg_depth, ROCKS_M)
	return r


func rod_tip() -> Vector2:
	return hand_position() + _rod_direction() * ROD_LENGTH


func hand_position() -> Vector2:
	return angler_pos + Vector2(3, -9)


func _random_water_point() -> Vector2:
	for attempt in 8:
		var p := Vector2(_rng.randf_range(0, VIEW.x), _rng.randf_range(BANK_TOP + 3, BANK_BOTTOM - 3))
		if is_water(p):
			return p
	return Vector2(4, BANK_TOP + 6)


## Water colour from depth, in four pixel-art bands with a 2x2 dither between
## them: pale shallows at the edges, light riffle, darker run, dark pool.
func _make_water_texture() -> ImageTexture:
	var h := int(BANK_BOTTOM - BANK_TOP)
	var img := Image.create(int(VIEW.x), h, false, Image.FORMAT_RGBA8)
	var bands: Array[Color] = [COL_SHALLOW, COL_RIFFLE, COL_WATER, COL_POOL, COL_DEEP]
	var cuts: Array[float] = [0.1, 0.38, 0.62, 0.86]
	var dither: Array[float] = [-0.03, 0.01, 0.03, -0.01]
	for y in h:
		for x in int(VIEW.x):
			var p := WorldScale.vec_to_m(Vector2(x + 0.5, BANK_TOP + y + 0.5))
			var d := river.depth_at(p) + dither[(y % 2) * 2 + (x % 2)]
			var band := 0
			while band < cuts.size() and d > cuts[band]:
				band += 1
			img.set_pixel(x, y, bands[band])
	return ImageTexture.create_from_image(img)


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
	draw_texture(_water_tex, Vector2(0, BANK_TOP))

	for s in _streaks:
		var v := flow_at(s)
		var speed := v.length()
		if speed < 1.0:
			continue
		var length := clampf(speed * 0.12, 1.0, 7.0)
		var foam := WorldScale.to_px(FOAM_SPEED * RiverField.WATER_SPEED)
		var col := COL_FOAM if speed > foam or river.seam_at(WorldScale.vec_to_m(s)) > 0.6 else COL_STREAK
		draw_line(s.floor(), (s + v / speed * length).floor(), col, 1.0)

	for r in ROCKS_M:
		_draw_rock(WorldScale.vec_to_px(Vector2(r.x, r.y)), WorldScale.to_px(r.z))

	_draw_angler()


## A boulder with a foam cushion piling up on its upstream face.
func _draw_rock(c: Vector2, radius: float) -> void:
	c = c.floor()
	draw_arc(c + Vector2(-1, 0), radius + 1.5, PI * 0.6, PI * 1.4, 8, COL_FOAM, 1.0)
	draw_circle(c, radius, COL_ROCK_DARK)
	draw_circle(c + Vector2(-0.5, -0.5), radius - 1.0, COL_ROCK)
	draw_rect(Rect2(c + Vector2(-radius * 0.5, -radius * 0.6), Vector2(2, 1)), COL_ROCK_LIGHT)


func _draw_angler() -> void:
	var p := angler_pos.floor()
	draw_rect(Rect2(p + Vector2(-3, -6), Vector2(6, 6)), COL_WADERS)
	draw_rect(Rect2(p + Vector2(-3, -12), Vector2(6, 6)), COL_JACKET)
	draw_rect(Rect2(p + Vector2(-2, -16), Vector2(4, 4)), COL_SKIN)
	draw_rect(Rect2(p + Vector2(-3, -17), Vector2(6, 2)), COL_HAT)
	draw_line(hand_position().floor(), rod_tip().floor(), COL_ROD, 1.0)
