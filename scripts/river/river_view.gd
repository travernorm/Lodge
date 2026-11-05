class_name RiverView
extends Node2D
## Draws the river (step A2, split from stream_scene.gd): the ground (grass,
## gravel, cut banks and point bars) where no BankView paints it (REQ-0013),
## the water in depth bands where no WaterView paints it, the little current streaks, and boulders and logs.
## Everything is drawn with primitives until real art replaces it.
##
## Reads the RiverField; changes nothing. The stream scene owns it, hands it
## the field with setup() and the part of the world on screen with tick().
## Pixels here, through WorldScale; the field is in metres.

## Water faster than this fraction of RiverField.WATER_SPEED shows white foam streaks.
const FOAM_SPEED := 36.0 / 55.0
## How many little current streaks drift on screen. 22 (down from 90, Traver 2026-11-03):
## the water textures now show the movement, so the streaks are just accents.
const STREAK_COUNT := 22
const STREAK_LIFE := Vector2(3.0, 8.0)

const COL_GRASS := ChunkPainter.COL_GRASS
const COL_TUFT := ChunkPainter.COL_TUFT
const COL_GRAVEL := ChunkPainter.COL_GRAVEL
const COL_ROCK := Color("6d6a5e")
const COL_ROCK_LIGHT := Color("8f8a78")
const COL_ROCK_DARK := Color("4f4c43")
const COL_FOAM := Color("c9dcd6")
const COL_STREAK := Color("4f8290")
const COL_LOG := Color("5a442c")
const COL_LOG_LIGHT := Color("7a5e3e")
## The old flat water's depth bands (ChunkPainter owns them).
const BANDS := ChunkPainter.BANDS
const CUTS := ChunkPainter.CUTS
const DITHER := ChunkPainter.DITHER

var _river: RiverField
var _stretch: Stretch
## The test screen's size and its banks (y, px), when there is no stretch.
var _screen := Vector2.ZERO
var _banks := Vector2.ZERO
var _view := Rect2()
var _streaks: Array[Vector2] = []
var _streak_life: Array[float] = []
var _water_tex: ImageTexture
var _tufts: Array[Vector2] = []
var _rng := RandomNumberGenerator.new()


## `stretch` null means the one-screen test stream, `screen` px across with
## banks at `banks` (top, bottom, px). `clear_water`: a WaterView paints the
## water underneath, so the ground leaves it transparent. `view` is the part
## of the world on screen (px), where the first streaks start. `clear_land`: a
## BankView paints the land underneath, so it's left transparent too.
func setup(river: RiverField, stretch: Stretch, screen: Vector2, banks: Vector2, clear_water: bool,
		view := Rect2(), clear_land := false) -> void:
	_river = river
	_stretch = stretch
	_screen = screen
	_banks = banks
	_view = view if view.has_area() else Rect2(Vector2.ZERO, screen)
	_rng.seed = 1979
	if stretch == null:
		_water_tex = _make_water_texture()
	elif not river is SectionField:
		_water_tex = _make_stretch_texture(clear_water, clear_land)
	else:
		_water_tex = null  # a streamed section: RiverStreamer draws the ground per chunk
	_streaks.clear()
	_streak_life.clear()
	for i in STREAK_COUNT:
		_streaks.append(_random_water_point())
		_streak_life.append(_rng.randf_range(0.0, STREAK_LIFE.y))
	_tufts.clear()
	for i in 40:
		var y := _rng.randf_range(0, banks.x - 8) if i % 2 == 0 else _rng.randf_range(banks.y + 8, screen.y)
		_tufts.append(Vector2(_rng.randf_range(0, screen.x), y).floor())


## The ground picture (the whole stretch, or the test screen's water), for tests.
func ground_texture() -> Texture2D:
	return _water_tex


## Moves the streaks on; `view` is the part of the world on screen (px).
func tick(delta: float, view: Rect2) -> void:
	_view = view
	for i in _streaks.size():
		var s := _streaks[i]
		s += _flow_px(s) * delta
		_streak_life[i] -= delta
		if _stretch != null:
			if _streak_life[i] <= 0.0 or not _wet_px(s) or not view.grow(8.0).has_point(s):
				s = _random_water_point()
				_streak_life[i] = _rng.randf_range(STREAK_LIFE.x, STREAK_LIFE.y)
		elif s.x > _screen.x + 2.0:
			# Leaving downstream: feed a new one in at the top of the screen.
			s = _random_water_point()
			s.x = 0.0
			_streak_life[i] = _rng.randf_range(STREAK_LIFE.x, STREAK_LIFE.y)
		elif _streak_life[i] <= 0.0 or not _wet_px(s):
			# Faded, or swirled into the rock or onto the bank.
			s = _random_water_point()
			_streak_life[i] = _rng.randf_range(STREAK_LIFE.x, STREAK_LIFE.y)
		_streaks[i] = s
	queue_redraw()


func _flow_px(p: Vector2) -> Vector2:
	return WorldScale.vec_to_px(_river.flow_at(WorldScale.vec_to_m(p)))


func _wet_px(p: Vector2) -> bool:
	return _river.is_water(WorldScale.vec_to_m(p))


func _random_water_point() -> Vector2:
	if _stretch != null:
		for attempt in 12:
			var p := Vector2(_rng.randf_range(_view.position.x, _view.end.x), _rng.randf_range(_view.position.y, _view.end.y))
			if _wet_px(p):
				return p
		return WorldScale.vec_to_px(_river.centre[_river.nearest_centre(WorldScale.vec_to_m(_view.get_center()))])
	for attempt in 8:
		var p := Vector2(_rng.randf_range(0, _screen.x), _rng.randf_range(_banks.x + 3, _banks.y - 3))
		if _wet_px(p):
			return p
	return Vector2(4, _banks.x + 6)


## Water colour from depth, in four pixel-art bands with a 2x2 dither between
## them: pale shallows at the edges, light riffle, darker run, dark pool.
func _make_water_texture() -> ImageTexture:
	var h := int(_banks.y - _banks.x)
	var img := Image.create(int(_screen.x), h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in int(_screen.x):
			var p := WorldScale.vec_to_m(Vector2(x + 0.5, _banks.x + y + 0.5))
			var d := _river.depth_at(p) + DITHER[(y % 2) * 2 + (x % 2)]
			var band := 0
			while band < CUTS.size() and d > CUTS[band]:
				band += 1
			img.set_pixel(x, y, BANDS[band])
	return ImageTexture.create_from_image(img)


## The whole stretch as one picture (ChunkPainter): grass, gravel banks, cut
## banks on the outside of bends, point bars on the inside, and water in depth
## bands, leaving clear what a WaterView or BankView paints underneath.
func _make_stretch_texture(clear_water: bool, clear_land: bool) -> ImageTexture:
	if clear_water and clear_land:
		return ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	var painter := ChunkPainter.new(_river, Rect2(Vector2.ZERO, _stretch.size_m), clear_water, clear_land)
	painter.run()
	var tex := painter.ground
	painter.free()
	return tex


func _draw() -> void:
	if _river == null:
		return
	if _stretch != null:
		if _water_tex != null:
			draw_texture(_water_tex, Vector2.ZERO)
	else:
		draw_rect(Rect2(Vector2.ZERO, _screen), COL_GRASS)
		for t in _tufts:
			draw_rect(Rect2(t, Vector2(1, 2)), COL_TUFT)
			draw_rect(Rect2(t + Vector2(2, 1), Vector2(1, 1)), COL_TUFT)
		draw_rect(Rect2(0, _banks.x - 5, _screen.x, 5), COL_GRAVEL)
		draw_rect(Rect2(0, _banks.y, _screen.x, 6), COL_GRAVEL)
		draw_texture(_water_tex, Vector2(0, _banks.x))

	for s in _streaks:
		var v := _flow_px(s)
		var speed := v.length()
		if speed < 1.0:
			continue
		var length := clampf(speed * 0.12, 1.0, 7.0)
		var foam := WorldScale.to_px(FOAM_SPEED * RiverField.WATER_SPEED)
		var col := COL_FOAM if speed > foam or _river.seam_at(WorldScale.vec_to_m(s)) > 0.6 else COL_STREAK
		draw_line(s.floor(), (s + v / speed * length).floor(), col, 1.0)

	for f in _river.features:
		_draw_feature(f)


## Boulders and logs have art; other kinds above ground show their footprint.
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
