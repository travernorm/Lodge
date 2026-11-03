extends Node2D
## The river the angler fishes. Two layouts:
## - With a `stretch` (REQ-0002, the demo): a winding river several screens
##   across, with bends, cut banks, point bars, a boulder garden, an eddy and a
##   fallen log. The camera scrolls with the angler, who walks the bank.
## - Without one: the original test screen, a fast riffle on the left feeding a
##   slow pool on the right, with a boulder at the head of the pool.
## Everything is drawn with primitives so feel can be tuned before any real art
## exists. Swap in Aseprite tiles later.
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
## On the test screen the angler stands on the near (bottom) bank facing across
## the water. On a stretch the angler faces the river from wherever they stand:
## facing_angle() turns casting and the rod to match.

## The demo stretch. Leave empty for the one-screen test stream.
@export var stretch: Stretch

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

## Walking speed (px/s, 8 px = 1 m). 60 = 7.5 m/s, raised 1.5x from 40 so the bank feels less sluggish.
const ANGLER_SPEED := 60.0
const ROD_LENGTH := 26.0
## How quickly the angler turns to face the water (per second).
const TURN_SPEED := 4.0
## Camera: how far ahead of the angler it looks, toward the water (px).
const LOOK_AHEAD := 40.0

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
const COL_CUT_BANK := Color("5b3e26")
const COL_LOG := Color("5a442c")
const COL_LOG_LIGHT := Color("7a5e3e")
## The old flat water: a colour per depth band, where each band starts, and a 2x2 dither.
const BANDS: Array[Color] = [COL_SHALLOW, COL_RIFFLE, COL_WATER, COL_POOL, COL_DEEP]
const CUTS: Array[float] = [0.1, 0.38, 0.62, 0.86]
const DITHER: Array[float] = [-0.03, 0.01, 0.03, -0.01]

var angler_pos := Vector2(160, BANK_BOTTOM + 16)
var river := _make_river()
var camera: Camera2D

var _facing := Vector2.UP

var _streaks: Array[Vector2] = []
var _streak_life: Array[float] = []
var _water_tex: ImageTexture
var _tufts: Array[Vector2] = []
var _rng := RandomNumberGenerator.new()
@onready var _cast: Node = get_node_or_null(^"Cast")
## Paints the water with a WaterLook when it has one (scripts/river/water_view.gd).
@onready var _water: WaterView = get_node_or_null(^"Water")


func _enter_tree() -> void:
	# Built here, not in _ready(), because the casting and fishing nodes read
	# the river in their own _ready(), which runs before this node's.
	if stretch == null or river.stretch == stretch:
		return
	river.build_stretch(stretch)
	angler_pos = WorldScale.vec_to_px(stretch.angler_start)
	_facing = _water_direction()
	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = roundi(world_size().x)
	camera.limit_bottom = roundi(world_size().y)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	camera.position = _camera_target()
	add_child(camera)


func _ready() -> void:
	add_to_group(&"stream")
	_rng.seed = 1979
	if camera != null:
		camera.make_current()
		camera.reset_smoothing()
	if stretch != null and _water != null:
		_water.setup(river)
	_water_tex = _make_stretch_texture() if stretch != null else _make_water_texture()
	for i in STREAK_COUNT:
		_streaks.append(_random_water_point())
		_streak_life.append(_rng.randf_range(0.0, STREAK_LIFE.y))
	for i in 40:
		var y := _rng.randf_range(0, BANK_TOP - 8) if i % 2 == 0 else _rng.randf_range(BANK_BOTTOM + 8, VIEW.y)
		_tufts.append(Vector2(_rng.randf_range(0, VIEW.x), y).floor())


func _process(delta: float) -> void:
	var walking: bool = _cast == null or _cast.allows_walking()
	var move := Controls.move_vector() if walking else Vector2.ZERO
	if stretch == null:
		angler_pos.x = clampf(angler_pos.x + move.x * ANGLER_SPEED * delta, 12.0, VIEW.x - 12.0)
	else:
		_walk(move * ANGLER_SPEED * delta)
		if walking:
			var target := _water_direction()
			_facing = Vector2.from_angle(lerp_angle(_facing.angle(), target.angle(), minf(1.0, TURN_SPEED * delta)))
		camera.position = _camera_target()
	_update_streaks(delta)
	queue_redraw()


func _update_streaks(delta: float) -> void:
	var view := visible_rect()
	for i in _streaks.size():
		var s := _streaks[i]
		s += flow_at(s) * delta
		_streak_life[i] -= delta
		if stretch != null:
			if _streak_life[i] <= 0.0 or not is_water(s) or not view.grow(8.0).has_point(s):
				s = _random_water_point()
				_streak_life[i] = _rng.randf_range(STREAK_LIFE.x, STREAK_LIFE.y)
		elif s.x > VIEW.x + 2.0:
			# Leaving downstream: feed a new one in at the top of the screen.
			s = _random_water_point()
			s.x = 0.0
			_streak_life[i] = _rng.randf_range(STREAK_LIFE.x, STREAK_LIFE.y)
		elif _streak_life[i] <= 0.0 or not is_water(s):
			# Faded, or swirled into the rock or onto the bank.
			s = _random_water_point()
			_streak_life[i] = _rng.randf_range(STREAK_LIFE.x, STREAK_LIFE.y)
		_streaks[i] = s


## Current velocity (px/s) at a point on screen (px).
## Pixel helper over river.flow_at() (metres), for screen-space callers.
func flow_at(p: Vector2) -> Vector2:
	return WorldScale.vec_to_px(river.flow_at(WorldScale.vec_to_m(p)))


## Pixel helper over river.is_water() (metres), for screen-space callers.
func is_water(p: Vector2) -> bool:
	return river.is_water(WorldScale.vec_to_m(p))


## Size of the world in pixels: the stretch, or one screen.
func world_size() -> Vector2:
	return WorldScale.vec_to_px(stretch.size_m) if stretch != null else VIEW


## Top-left of what's on screen, in world pixels. HUD drawing offsets by this
## so it stays put while the camera scrolls.
func screen_origin() -> Vector2:
	if camera == null:
		return Vector2.ZERO
	return (camera.get_screen_center_position() - VIEW * 0.5).round()


## The part of the world on screen (px).
func visible_rect() -> Rect2:
	return Rect2(screen_origin(), VIEW)


## Which way the angler faces, as an angle from straight up the screen. 0 on
## the test screen. Casting aims, rod poses and practice targets turn by this.
func facing_angle() -> float:
	return Vector2.UP.angle_to(_facing)


## Whether a fly (px) is still in play: on the test screen, until it drifts off
## the right edge; on a stretch, until it leaves the world.
func in_play(p: Vector2) -> bool:
	if stretch == null:
		return p.x <= VIEW.x - 4.0
	return Rect2(Vector2(4, 4), world_size() - Vector2(8, 8)).has_point(p)


## Where a hooked fish (px) can be: kept in the water. `prev` is where it was.
func keep_in_water(p: Vector2, prev: Vector2) -> Vector2:
	if stretch == null:
		return Vector2(clampf(p.x, 4.0, VIEW.x - 4.0), clampf(p.y, BANK_TOP + 3.0, BANK_BOTTOM - 3.0))
	return p if is_water(p) else prev


## Stretch: walks the angler, sliding along the bank instead of into the water.
func _walk(step: Vector2) -> void:
	for axis in [Vector2(step.x, 0.0), Vector2(0.0, step.y)]:
		var next: Vector2 = angler_pos + axis
		if axis != Vector2.ZERO and _walkable(next):
			angler_pos = next


func _walkable(p: Vector2) -> bool:
	var size := world_size()
	if p.x < 8.0 or p.y < 20.0 or p.x > size.x - 8.0 or p.y > size.y - 4.0:
		return false
	for o in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -4)]:
		if is_water(p + o):
			return false
	return true


## Stretch: the direction from the angler to the middle of the nearest river.
func _water_direction() -> Vector2:
	var me := WorldScale.vec_to_m(hand_position())
	var k := river.nearest_centre(me)
	if k < 0:
		return Vector2.UP
	var dir := river.centre[k] - me
	return dir.normalized() if dir.length() > 0.01 else Vector2.UP


func _camera_target() -> Vector2:
	return angler_pos + Vector2(0, -8) + _facing * LOOK_AHEAD


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
	if stretch != null:
		var view := visible_rect()
		for attempt in 12:
			var p := Vector2(_rng.randf_range(view.position.x, view.end.x), _rng.randf_range(view.position.y, view.end.y))
			if is_water(p):
				return p
		return WorldScale.vec_to_px(river.centre[river.nearest_centre(WorldScale.vec_to_m(view.get_center()))])
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
	for y in h:
		for x in int(VIEW.x):
			var p := WorldScale.vec_to_m(Vector2(x + 0.5, BANK_TOP + y + 0.5))
			var d := river.depth_at(p) + DITHER[(y % 2) * 2 + (x % 2)]
			var band := 0
			while band < CUTS.size() and d > CUTS[band]:
				band += 1
			img.set_pixel(x, y, BANDS[band])
	return ImageTexture.create_from_image(img)


## The whole stretch as one picture: grass, gravel banks, cut banks on the
## outside of bends, point bars on the inside, and water in depth bands.
## The field's grids are scaled up to pixels natively, then each pixel is
## classified, so the picture takes a fraction of a second to make.
func _make_stretch_texture() -> ImageTexture:
	var size := Vector2i(world_size())
	var depth_px := _layer_to_pixels(river.depth, size, 1.0)
	var wet_px := _layer_to_pixels(_wet_floats(), size, 1.0)
	var shore_px := _layer_to_pixels(river.shore, size, 20.0)
	var bend_px := _layer_to_pixels(river.bend, size, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1979
	var clear_water := _water != null and _water.is_active()
	var data := PackedByteArray()
	data.resize(size.x * size.y * 4)
	for y in size.y:
		for x in size.x:
			var idx := y * size.x + x
			var col := COL_GRASS
			if wet_px[idx] >= 0.5 and clear_water:
				col = Color.TRANSPARENT  # the WaterView paints it, underneath
			elif wet_px[idx] >= 0.5:
				var d := depth_px[idx] + DITHER[(y % 2) * 2 + (x % 2)]
				var band := 0
				while band < CUTS.size() and d > CUTS[band]:
					band += 1
				col = BANDS[band]
			else:
				var shore := shore_px[idx]
				var b := bend_px[idx]
				if b > 0.25 and shore < 0.5 + 0.5 * b:
					col = COL_CUT_BANK  # undercut earth on the outside of a bend
				elif shore < 0.75 + 3.0 * maxf(-b, 0.0):
					col = COL_GRAVEL  # the inside of a bend widens into a point bar
				elif rng.randf() < 0.025:
					col = COL_TUFT
			data[idx * 4] = col.r8
			data[idx * 4 + 1] = col.g8
			data[idx * 4 + 2] = col.b8
			data[idx * 4 + 3] = col.a8
	var img := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, data)
	for g in stretch.features.filter(func(x: RiverFeature) -> bool: return x is GravelBar):
		var c := WorldScale.vec_to_px(g.centre)
		var r := WorldScale.to_px(g.radius)
		for y in range(maxi(0, int(c.y - r)), mini(size.y, int(c.y + r) + 1)):
			for x in range(maxi(0, int(c.x - r)), mini(size.x, int(c.x + r) + 1)):
				if Vector2(x, y).distance_to(c) <= r and wet_px[y * size.x + x] < 0.5:
					img.set_pixel(x, y, COL_GRAVEL)
	return ImageTexture.create_from_image(img)


## One of the field's per-cell layers scaled up to `size` pixels (bilinear),
## as floats. Values are clamped to +-limit first (the shore layer holds INF).
func _layer_to_pixels(layer: PackedFloat32Array, size: Vector2i, limit: float) -> PackedFloat32Array:
	var vals := PackedFloat32Array()
	vals.resize(layer.size())
	for i in layer.size():
		vals[i] = clampf(layer[i], -limit, limit)
	var img := Image.create_from_data(river.cols, river.rows, false, Image.FORMAT_RF, vals.to_byte_array())
	img.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	return img.get_data().to_float32_array()


func _wet_floats() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(river.wet.size())
	for i in river.wet.size():
		out[i] = river.wet[i]
	return out


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
	return Vector2(0.45, -1.0).normalized().rotated(facing_angle())


func _draw() -> void:
	if stretch != null:
		draw_texture(_water_tex, Vector2.ZERO)
	else:
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

	for f in river.features:
		_draw_feature(f)

	_draw_angler()


## Boulders and logs have their own art. Other kinds (not gravel bars, which
## are on the ground) are outlined from their footprint until they get some.
func _draw_feature(f: RiverFeature) -> void:
	if f is Boulder:
		_draw_rock(WorldScale.vec_to_px((f as Boulder).centre), WorldScale.to_px((f as Boulder).radius))
	elif f is FallenLog:
		_draw_log(WorldScale.vec_to_px((f as FallenLog).a), WorldScale.vec_to_px((f as FallenLog).b))
	elif not f is GravelBar and not f.footprint().is_empty():
		var pts := Array(f.footprint()).map(func(q: Vector2) -> Vector2: return WorldScale.vec_to_px(q).floor())
		draw_polyline(PackedVector2Array(pts + [pts[0]]), COL_ROCK, 1.0)


## A boulder with a foam cushion piling up on its upstream face.
func _draw_rock(c: Vector2, radius: float) -> void:
	c = c.floor()
	draw_arc(c + Vector2(-1, 0), radius + 1.5, PI * 0.6, PI * 1.4, 8, COL_FOAM, 1.0)
	draw_circle(c, radius, COL_ROCK_DARK)
	draw_circle(c + Vector2(-0.5, -0.5), radius - 1.0, COL_ROCK)
	draw_rect(Rect2(c + Vector2(-radius * 0.5, -radius * 0.6), Vector2(2, 1)), COL_ROCK_LIGHT)


## A fallen log, with a few broken-off limbs.
func _draw_log(a: Vector2, b: Vector2) -> void:
	draw_line(a.floor(), b.floor(), COL_LOG, 4.0)
	draw_line(a.floor() + Vector2(0, -1), b.floor() + Vector2(0, -1), COL_LOG_LIGHT, 1.0)
	var along := b - a
	for t in [0.3, 0.55, 0.8]:
		var p: Vector2 = (a + along * t).floor()
		draw_line(p, p + along.normalized().rotated(0.7 if t != 0.55 else -0.7) * 5.0, COL_LOG, 1.0)


func _draw_angler() -> void:
	var p := angler_pos.floor()
	draw_rect(Rect2(p + Vector2(-3, -6), Vector2(6, 6)), COL_WADERS)
	draw_rect(Rect2(p + Vector2(-3, -12), Vector2(6, 6)), COL_JACKET)
	draw_rect(Rect2(p + Vector2(-2, -16), Vector2(4, 4)), COL_SKIN)
	draw_rect(Rect2(p + Vector2(-3, -17), Vector2(6, 2)), COL_HAT)
	draw_line(hand_position().floor(), rod_tip().floor(), COL_ROD, 1.0)
