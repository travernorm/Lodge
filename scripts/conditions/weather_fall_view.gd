class_name WeatherFallView
extends Node2D
## The rain and snow falling over the river (REQ-0015), drawn for WeatherView,
## which owns it and tells it what falls. Two depths: a far layer (smaller,
## slower, dimmer, most of the drops) and a near layer (bigger, faster, fewer).
## A rain drop ends in a little splash where it lands.
##
## Drops live in screen pixels (they fall past the camera); splashes stay
## where they landed on the ground. With no sprite sheet in the look, a plain
## streak or dot stands in.

## One drop in this many is in the near layer.
const NEAR_EVERY := 3
## Speed and opacity of the far and near layers, against the look's numbers.
const FAR_SPEED := 0.7
const NEAR_SPEED := 1.25
const FAR_ALPHA := 0.6
## One rain drop in this many leaves a splash, and how long one lasts (s).
const SPLASH_EVERY := 2
const SPLASH_SECONDS := 0.3
const MAX_SPLASH := 128

## What falls (WeatherView sets it each frame, mid-fade included).
var mix := WeatherMix.new()
## Lean from straight down right now, wind included (degrees, + to the right).
var slant_deg := 0.0
## The world position of the screen's top-left corner (px).
var origin := Vector2.ZERO

var _rng := RandomNumberGenerator.new()
var _time := 0.0
## Each drop or flake: where it is (screen px), its age and lifetime (s), and
## its sway phase.
var _pos := PackedVector2Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _phase := PackedFloat32Array()
## Each splash: where it landed (world px) and its age (s).
var _splash_pos := PackedVector2Array()
var _splash_age := PackedFloat32Array()
var _next_splash := 0


func _init(p_seed := 1) -> void:
	_rng.seed = p_seed


func _ready() -> void:
	_pos.resize(WeatherMix.MAX_FALL)
	_age.resize(WeatherMix.MAX_FALL)
	_life.resize(WeatherMix.MAX_FALL)
	_phase.resize(WeatherMix.MAX_FALL)
	_splash_pos.resize(MAX_SPLASH)
	_splash_age.resize(MAX_SPLASH)
	_splash_age.fill(INF)
	for i in WeatherMix.MAX_FALL:
		_spawn(i)
		_age[i] = _rng.randf() * _life[i]


## How many drops or flakes are on screen (never more than MAX_FALL).
func count() -> int:
	return mini(int(mix.fall_amount), WeatherMix.MAX_FALL)


static func is_near(i: int) -> bool:
	return i % NEAR_EVERY == 0


## Which cell across the sheet drop `i` uses: the far layer takes the small
## half of the variants, the near layer the large half.
static func variant(i: int, variants: int) -> int:
	var small := maxi(variants / 2, 1)
	if not is_near(i) or variants <= small:
		return (i / NEAR_EVERY) % small
	return small + (i / NEAR_EVERY) % (variants - small)


## Which row of a rain sheet suits a lean of `deg`.
static func slant_row(deg: float, rows: int) -> int:
	return clampi(roundi(absf(deg) / WeatherStyle.FALL_ROW_DEG), 0, maxi(rows, 1) - 1)


func step(delta: float) -> void:
	_time += delta
	var px := WorldScale.PX_PER_M
	var lean := deg_to_rad(slant_deg)
	var vel := Vector2(sin(lean), cos(lean)) * mix.fall_speed_mps * px
	var bounds := get_viewport_rect().grow(24.0)
	var n := count()
	var splashes := mix.splash_texture != null
	for i in WeatherMix.MAX_FALL:
		_pos[i] += vel * delta * (NEAR_SPEED if is_near(i) else FAR_SPEED)
		_age[i] += delta
		if _age[i] >= _life[i]:
			if splashes and i < n and i % SPLASH_EVERY == 0:
				_splash_pos[_next_splash] = _pos[i] + origin
				_splash_age[_next_splash] = 0.0
				_next_splash = (_next_splash + 1) % MAX_SPLASH
			_spawn(i)
		elif not bounds.has_point(_pos[i]):
			_spawn(i)
	for i in MAX_SPLASH:
		_splash_age[i] += delta
	queue_redraw()


## A new drop somewhere on screen. Drops land all over, not only at the
## bottom: the view looks down on the river.
func _spawn(i: int) -> void:
	var size := get_viewport_rect().size
	_pos[i] = Vector2(_rng.randf_range(-16.0, size.x + 16.0), _rng.randf_range(-16.0, size.y))
	_age[i] = 0.0
	_life[i] = _rng.randf_range(0.4, 1.0) * (3.0 if mix.fall_length_m <= 0.0 else 1.0)
	_phase[i] = _rng.randf() * TAU


func _draw() -> void:
	_draw_splashes()
	var n := count()
	if n <= 0:
		return
	var px := WorldScale.PX_PER_M
	var lean := deg_to_rad(slant_deg)
	var streak := Vector2(sin(lean), cos(lean)) * mix.fall_length_m * px
	var sway := mix.fall_sway_m * px
	var tex := mix.fall_texture
	var cell := 0.0 if tex == null else float(tex.get_width()) / mix.fall_variants
	var row := slant_row(slant_deg, mix.fall_slant_rows)
	var flip := -1.0 if slant_deg < 0.0 else 1.0
	for i in n:
		var col := mix.fall_colour
		col.a *= clampf(minf(_age[i], _life[i] - _age[i]) / 0.15, 0.0, 1.0) * (1.0 if is_near(i) else FAR_ALPHA)
		var p := (_pos[i] + Vector2(sin(_time * 1.7 + _phase[i]) * sway, 0.0)).floor()
		if tex != null:
			var src := Rect2(variant(i, mix.fall_variants) * cell, row * cell, cell, cell)
			var half := floorf(cell * 0.5)
			draw_texture_rect_region(tex, Rect2(p.x - half * flip, p.y - half, cell * flip, cell), src, col)
		elif streak.length() >= 1.0:
			draw_line(p, p - streak.round(), col, 1.0)
		else:
			draw_rect(Rect2(p, Vector2.ONE), col)


func _draw_splashes() -> void:
	var tex := mix.splash_texture
	if tex == null:
		return
	var cell := float(tex.get_width()) / mix.splash_frames
	var half := Vector2(floorf(cell * 0.5), floorf(cell * 0.5))
	var col := mix.fall_colour
	col.a = minf(col.a * 1.4, 1.0)
	for i in MAX_SPLASH:
		if _splash_age[i] >= SPLASH_SECONDS:
			continue
		var frame := mini(int(_splash_age[i] / SPLASH_SECONDS * mix.splash_frames), mix.splash_frames - 1)
		var p := (_splash_pos[i] - origin).floor() - half
		draw_texture_rect_region(tex, Rect2(p, Vector2(cell, cell)), Rect2(frame * cell, 0.0, cell, cell), col)
