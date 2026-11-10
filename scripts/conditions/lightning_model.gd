class_name LightningModel
extends RefCounted
## When lightning strikes and how bright the screen is from it (REQ-0015). A
## strike is two to four flickers and then a short fade. Most strikes are far
## (dim, from everywhere); some are near (bright, from one side, and your eyes
## take a second to adjust afterwards). WeatherView steps it and paints
## `flash`; sound can follow `struck` later.
##
## Flash safety: flickers never start closer together than MIN_GAP (so never
## more than three a second) and never brighter than MAX_FLASH, and
## `strength` scales the lot down to nothing. All timing comes from a seeded
## RNG (R8), so a storm plays back the same.

## A new strike began. `near` strikes are the bright ones.
signal struck(near: bool)

const MIN_GAP := 0.34
const MAX_FLASH := 0.85
const FLICKER_SECONDS := Vector2(0.04, 0.09)
const FAR_PEAK := Vector2(0.25, 0.4)
const NEAR_PEAK := Vector2(0.7, 0.85)
## One strike in this many is near.
const NEAR_SHARE := 0.2
## The fade after the last flicker: its length (s) and its share of the peak.
const TAIL_SECONDS := 0.5
const TAIL_SHARE := 0.3
## After a near strike the picture sits this much darker, easing back.
const AFTERGLOW := 0.15
const AFTERGLOW_SECONDS := 1.0

## How bright the flash is right now, 0 to MAX_FLASH.
var flash := 0.0
## Where the light comes from: -1 the left, 1 the right, 0 everywhere (far).
var side := 0.0
## How much darker than normal the picture is while the eyes adjust, 0 to AFTERGLOW.
var afterglow := 0.0
## Scales every flash; 0 turns lightning's light off (the look's slider).
var strength := 1.0
## The current strike's flickers: when each starts (s after the strike), how
## long it lasts and how bright it peaks.
var starts := PackedFloat32Array()
var lengths := PackedFloat32Array()
var peaks := PackedFloat32Array()

var _rng := RandomNumberGenerator.new()
var _age := INF
var _wait := INF
var _near := false


func _init(p_seed := 1) -> void:
	_rng.seed = p_seed


## Advances the storm. `per_minute` is how often it strikes (0 = never).
func step(delta: float, per_minute: float) -> void:
	if per_minute <= 0.0:
		_wait = INF
	else:
		var gap := 60.0 / per_minute
		if _wait == INF:
			_wait = _rng.randf_range(0.3, 1.0) * gap
		_wait -= delta
		if _wait <= 0.0 and not is_striking():
			strike(_rng.randf() < NEAR_SHARE)
			_wait = _rng.randf_range(0.5, 1.5) * gap
	_age += delta
	flash = flash_at(_age)
	afterglow = _afterglow_at(_age)


## Starts a strike now.
func strike(near: bool) -> void:
	_near = near
	_age = 0.0
	side = 0.0 if not near else (-1.0 if _rng.randf() < 0.5 else 1.0)
	var n := _rng.randi_range(2, 4)
	var range_ := NEAR_PEAK if near else FAR_PEAK
	starts.resize(n)
	lengths.resize(n)
	peaks.resize(n)
	var t := 0.0
	for i in n:
		starts[i] = t
		lengths[i] = _rng.randf_range(FLICKER_SECONDS.x, FLICKER_SECONDS.y)
		peaks[i] = minf(_rng.randf_range(range_.x, range_.y), MAX_FLASH)
		t += _rng.randf_range(MIN_GAP, MIN_GAP * 1.5)
	flash = flash_at(0.0)
	struck.emit(near)


## True from a strike's first flicker to the end of its fade.
func is_striking() -> bool:
	return _age < _end() + TAIL_SECONDS


## How bright the flash is `age` seconds into the current strike.
func flash_at(age: float) -> float:
	if starts.is_empty() or age < 0.0 or strength <= 0.0:
		return 0.0
	var v := 0.0
	for i in starts.size():
		var into := age - starts[i]
		if into >= 0.0 and into < lengths[i]:
			v = maxf(v, peaks[i] * (1.0 - into / lengths[i]))
	var after := age - _end()
	if after >= 0.0 and after < TAIL_SECONDS:
		v = maxf(v, peaks[peaks.size() - 1] * TAIL_SHARE * (1.0 - after / TAIL_SECONDS))
	return minf(v * clampf(strength, 0.0, 1.0), MAX_FLASH)


## When the last flicker ends (s after the strike began).
func _end() -> float:
	if starts.is_empty():
		return 0.0
	var last := starts.size() - 1
	return starts[last] + lengths[last]


func _afterglow_at(age: float) -> float:
	var after := age - _end() - TAIL_SECONDS
	if not _near or starts.is_empty() or after < 0.0 or after >= AFTERGLOW_SECONDS:
		return 0.0
	return AFTERGLOW * clampf(strength, 0.0, 1.0) * (1.0 - after / AFTERGLOW_SECONDS)
