class_name StickGestures
extends RefCounted
## Reads right-stick gestures: a sweeping loop (mend) and a quick upward flick
## (hook set). Feed it the stick every frame with update(), then check the flags.

const LOOP_RADIUS := 0.6  # stick must be pushed this far out to count toward a loop
const CENTER_RADIUS := 0.3
const LOOP_SWEEP := PI * 0.9  # about half a circle
const LOOP_MAX_TIME := 0.9

const FLICK_REST_Y := -0.35  # stick y above this counts as "not flicked yet"
const FLICK_UP_Y := -0.85
const FLICK_MAX_TIME := 0.12
const FLICK_MAX_X := 0.5

## True on the frame a loop or flick completes.
var looped := false
var flicked := false

var _loop_active := false
var _loop_start := 0.0
var _loop_last_angle := 0.0
var _loop_swept := 0.0
var _loop_needs_center := false
var _rest_at := -1.0
var _flick_spent := false


func update(now: float, stick: Vector2) -> void:
	looped = _update_loop(now, stick)
	flicked = _update_flick(now, stick)


func _update_loop(now: float, stick: Vector2) -> bool:
	var r := stick.length()
	if _loop_needs_center:
		if r < CENTER_RADIUS:
			_loop_needs_center = false
		return false
	if r < LOOP_RADIUS:
		if r < CENTER_RADIUS:
			_loop_active = false
		return false
	var angle := stick.angle()
	if not _loop_active or now - _loop_start > LOOP_MAX_TIME:
		_loop_active = true
		_loop_start = now
		_loop_swept = 0.0
		_loop_last_angle = angle
		return false
	_loop_swept += wrapf(angle - _loop_last_angle, -PI, PI)
	_loop_last_angle = angle
	if absf(_loop_swept) >= LOOP_SWEEP:
		_loop_active = false
		_loop_needs_center = true
		return true
	return false


func _update_flick(now: float, stick: Vector2) -> bool:
	if stick.y > FLICK_REST_Y:
		_rest_at = now
		_flick_spent = false
		return false
	if _flick_spent or _rest_at < 0.0:
		return false
	if stick.y <= FLICK_UP_Y and absf(stick.x) <= FLICK_MAX_X:
		_flick_spent = true
		return now - _rest_at <= FLICK_MAX_TIME
	return false
