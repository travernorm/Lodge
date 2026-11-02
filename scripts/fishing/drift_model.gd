class_name DriftModel
extends RefCounted
## The fly and line lying on the water.
##
## The fly rides the current where it sits, and the belly of the line rides the
## current where it sits. Your rod tip holds the near end still, so the belly
## bows downstream over time, faster when it lies in quicker water than the fly.
## Once the bow gets ahead of the fly it pulls on it: that's drag, and trout
## refuse a dragging fly. A mend (right-stick loop) flips the belly back upstream.
## Mend too early, with no bow to fix, and you yank the fly.

const SLACK := 8.0  # extra line beyond a straight line to the fly...
const SLACK_PER_PX := 0.15  # ...plus this much per px of cast
const TAUT_RANGE := 4.0  # the last px of slack, over which the line comes tight
const BOW_FREE := 10.0  # downstream bow (px) before drag starts
const BOW_RANGE := 16.0  # bow beyond BOW_FREE that reaches full drag
const DRAG_SPEED := 22.0  # px/s the line can drag the fly at full drag
const DRAG_RESPONSE := 4.0  # how fast drag follows its target, per second
const MEND_SHIFT := 22.0
const OVER_MEND := 14.0  # bow after a mend more upstream than this jolts the fly
const JOLT_TIME := 0.25

var tip := Vector2.ZERO
var fly := Vector2.ZERO
var belly := Vector2.ZERO
var line_length := 0.0
## 0 = drag-free drift, 1 = the fly is skating.
var drag := 0.0
## Set by the last mend(): it moved the fly.
var over_mended := false

var _jolt := 0.0


func start(p_tip: Vector2, p_fly: Vector2) -> void:
	tip = p_tip
	fly = p_fly
	belly = (tip + fly) * 0.5
	var reach := tip.distance_to(fly)
	line_length = reach + SLACK + reach * SLACK_PER_PX
	drag = 0.0
	_jolt = 0.0
	over_mended = false


## How far the belly is bowed downstream of the straight line to the fly.
func bow() -> float:
	return belly.x - (tip.x + fly.x) * 0.5


## flow: Callable taking a position and returning the current there (px/s).
func update(dt: float, flow: Callable) -> void:
	belly += flow.call(belly) * dt

	var bow_drag := clampf((bow() - BOW_FREE) / BOW_RANGE, 0.0, 1.0)
	var taut := clampf((tip.distance_to(fly) - (line_length - TAUT_RANGE)) / TAUT_RANGE, 0.0, 1.0)
	var target := maxf(bow_drag, taut)
	_jolt = maxf(0.0, _jolt - dt)
	if _jolt > 0.0:
		target = maxf(target, 0.6)
	drag = move_toward(drag, target, DRAG_RESPONSE * dt)

	var pull := (belly - fly).normalized() if not belly.is_equal_approx(fly) else Vector2.ZERO
	fly += (flow.call(fly) + pull * drag * DRAG_SPEED) * dt

	# The line can't stretch: the fly swings on a taut line, and the belly
	# straightens out when there's no slack left for it.
	if tip.distance_to(fly) > line_length:
		fly = tip + (fly - tip).normalized() * line_length
	var excess := tip.distance_to(belly) + belly.distance_to(fly) - line_length
	if excess > 0.0:
		belly = belly.move_toward((tip + fly) * 0.5, excess)


func mend() -> void:
	belly.x -= MEND_SHIFT
	over_mended = bow() < -OVER_MEND
	if over_mended:
		_jolt = JOLT_TIME
