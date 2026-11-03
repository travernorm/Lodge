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
##
## Each mend also feeds out line (a feel experiment, see MendFeed below), so
## mending again and again lengthens the drift.

## Distances in metres, speeds in m/s (REQ-0001).
const SLACK := 1.0  # extra line (m) beyond a straight line to the fly...
const SLACK_PER_M := 0.15  # ...plus this much per metre of cast
const TAUT_RANGE := 0.5  # the last metres of slack, over which the line comes tight
const BOW_FREE := 1.25  # downstream bow (m) before drag starts
const BOW_RANGE := 2.0  # bow beyond BOW_FREE that reaches full drag
const DRAG_SPEED := 2.75  # m/s the line can drag the fly at full drag
const DRAG_RESPONSE := 4.0  # how fast drag follows its target, per second
const MEND_SHIFT := 2.75  # m the belly flips upstream on a mend
const OVER_MEND := 1.75  # bow (m) after a mend more upstream than this jolts the fly
const JOLT_TIME := 0.25

## How a mend feeds out line. Feel experiment: Traver plays them and picks.
##   FLAT       the same amount every mend
##   MATCH_BOW  as much as the belly had bowed downstream (MEND_FEED_MIN to
##              MEND_SHIFT): a late, big mend feeds more than a small early
##              one. Always enough that the flipped belly isn't pulled
##              straight again
##   TAPER      a lot on the first mend, less on each one after
enum MendFeed { FLAT, MATCH_BOW, TAPER }
const MEND_FEED_NAMES: Array[String] = ["Flat 1 m", "Matches the bow", "Taper"]
const MEND_FEED_FLAT := 1.0  # m fed per mend (FLAT)
const MEND_FEED_MIN := 0.5  # m fed at least (MATCH_BOW)
const MEND_FEED_TAPER := 1.5  # m fed on the first mend (TAPER); then 1.5/(1 + 0.5 n)
## Most line that can be out (m): what a full-length 14.75 m cast lands with.
const LINE_LIMIT := 14.75 + SLACK + 14.75 * SLACK_PER_M

var tip := Vector2.ZERO
var fly := Vector2.ZERO
var belly := Vector2.ZERO
var line_length := 0.0
## Which way is downstream here (unit vector): the bow is measured along it and
## a mend flips the belly back against it. The fishing controller sets it from
## the current where the fly lands; the test screen's river runs +x.
var downstream := Vector2.RIGHT
## 0 = drag-free drift, 1 = the fly is skating.
var drag := 0.0
## Set by the last mend(): it moved the fly.
var over_mended := false
var mend_feed := MendFeed.FLAT
## Set by the last mend(): the line (m) it fed out. 0 once the line is all out.
var fed := 0.0
## Mends since the fly landed.
var mends := 0
## How fast (m/s) the fly moved against the water under it in the last update:
## 0 when it rides the current, more when drag, a jolt or a tight line pulls it.
var slip := 0.0

var _jolt := 0.0


func start(p_tip: Vector2, p_fly: Vector2) -> void:
	tip = p_tip
	fly = p_fly
	belly = (tip + fly) * 0.5
	var reach := tip.distance_to(fly)
	line_length = reach + SLACK + reach * SLACK_PER_M
	drag = 0.0
	slip = 0.0
	_jolt = 0.0
	over_mended = false
	fed = 0.0
	mends = 0


## How far the belly is bowed downstream of the straight line to the fly.
func bow() -> float:
	return (belly - (tip + fly) * 0.5).dot(downstream)


## flow: Callable taking a position (m) and returning the current there (m/s).
func update(dt: float, flow: Callable) -> void:
	var fly_before := fly
	var water: Vector2 = flow.call(fly)
	belly += flow.call(belly) * dt

	var bow_drag := clampf((bow() - BOW_FREE) / BOW_RANGE, 0.0, 1.0)
	var taut := clampf((tip.distance_to(fly) - (line_length - TAUT_RANGE)) / TAUT_RANGE, 0.0, 1.0)
	var target := maxf(bow_drag, taut)
	_jolt = maxf(0.0, _jolt - dt)
	if _jolt > 0.0:
		target = maxf(target, 0.6)
	drag = move_toward(drag, target, DRAG_RESPONSE * dt)

	var pull := (belly - fly).normalized() if not belly.is_equal_approx(fly) else Vector2.ZERO
	fly += (water + pull * drag * DRAG_SPEED) * dt

	# The line can't stretch: the fly swings on a taut line, and the belly
	# straightens out when there's no slack left for it.
	if tip.distance_to(fly) > line_length:
		fly = tip + (fly - tip).normalized() * line_length
	var excess := tip.distance_to(belly) + belly.distance_to(fly) - line_length
	if excess > 0.0:
		belly = belly.move_toward((tip + fly) * 0.5, excess)
	if dt > 0.0:
		slip = ((fly - fly_before) / dt - water).length()


func mend() -> void:
	var before := line_length
	var bowed := bow()
	belly -= downstream * MEND_SHIFT
	match mend_feed:
		MendFeed.FLAT:
			line_length += MEND_FEED_FLAT
		MendFeed.MATCH_BOW:
			var needs := tip.distance_to(belly) + belly.distance_to(fly)
			line_length = maxf(needs, line_length + clampf(bowed, MEND_FEED_MIN, MEND_SHIFT))
		MendFeed.TAPER:
			line_length += MEND_FEED_TAPER / (1.0 + 0.5 * mends)
	line_length = minf(line_length, maxf(LINE_LIMIT, before))
	fed = line_length - before
	mends += 1
	over_mended = bow() < -OVER_MEND
	if over_mended:
		_jolt = JOLT_TIME
