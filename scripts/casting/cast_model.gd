class_name CastModel
extends RefCounted
## The bumper casting rhythm as pure logic, with no drawing or input reading.
## Call update() every frame with the time and whether L and R are held, then read
## the state and listen to the signals. (update()'s `r` argument is the back-cast
## action, cast_back, and `l` is cast_forward: the names predate the bumper swap.) Kept apart from the scene so the rhythm
## can be tested headless (see tests/cast_test.gd).
##
## The rhythm:
##   1. Hold L: back cast. The line unrolls behind you. Wait for it to straighten
##      (the ideal time grows with the line that's out).
##   2. Press R while still holding L, then let go of L: a slight overlap shoots
##      the forward cast.
##   3. While R is held the line unrolls forward. Either:
##      - overlap back into L for a false cast, which adds line, or
##      - let go of R to deliver the fly.
##
## Mistakes: letting go of L before pressing R collapses the cast; holding a
## stroke too long drops the line; overlapping the bumpers too long throws a
## tailing loop or tangles the leader.
##
## How strokes turn into line and distance is up to `rules` (a CastRules
## "chassis"), so different rhythms can be swapped in and compared.

enum State { IDLE, BACK, BACK_TO_FORWARD, GAP, FORWARD, FORWARD_TO_BACK, FLIGHT, LANDED }

## A coaching message after a stroke, overlap or fault. quality is 0..1.
signal feedback(text: String, quality: float)
## The fly left the rod. offset (m) is relative to the rod tip at release.
signal delivered(offset: Vector2, quality: float)
## The fly touched down.
signal landed(presentation: String, quality: float)
## The cast fell apart and the line is back on the reel.
signal collapsed(reason: String)

var tuning: CastTuning
## The chassis: how strokes become line and distance. Swap it any time the line
## is reeled in.
var rules: CastRules
## The rod (REQ-0005): it caps the line (max_line()) and widens or narrows the
## timing windows (forgiveness()). Null plays like the rule set alone. Set by
## its owner (the fishing node's Tackle) while the line is reeled in.
var rod: FlyRod
## Every stroke and overlap of the current cast, oldest first, for practice mode:
## {kind: "back" | "forward" | "overlap", seconds, ideal, quality}
var strokes: Array[Dictionary] = []
## Reach (m) of the last delivery.
var last_reach := 0.0
var state := State.IDLE
## Line out in metres. 0 when reeled in.
var line_out := 0.0
## -1 (cast angled left) .. 1 (angled right). 0 is straight across the river.
var aim := 0.0
## Which way "across the river" is, as an angle from straight up the screen.
## The stream sets it from where the angler stands; 0 on the test screen.
var facing_angle := 0.0
## When the current stroke (back or forward) started, and its ideal length.
var phase_start := 0.0
var phase_ideal := 0.0
var false_casts := 0
## Results of the most recent delivery.
var last_cast_quality := 0.0
var presentation := ""
## Where the fly lands, in metres from the rod tip.
var landing_offset := Vector2.ZERO
## Quality of the most recent scored stroke or overlap.
var last_score := 0.0

var _now := 0.0
## Scores for the whole cast and for the current false-cast cycle.
## x = quality, y = weight. A clean overlap counts half as much as a stroke.
var _scores: Array[Vector2] = []
var _cycle: Array[Vector2] = []
var _overlap_start := 0.0
var _gap_start := 0.0
var _flight_start := 0.0
var _rng := RandomNumberGenerator.new()
## After a collapse, R has to be let go before a new cast can start.
var _needs_release := false


func _init(p_tuning: CastTuning = null, rng_seed := 0, p_rules: CastRules = null) -> void:
	tuning = p_tuning if p_tuning != null else CastTuning.new()
	rules = p_rules if p_rules != null else CastRules.new()
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()


## True while a cast is in progress (not idle and not lying on the water).
func is_busy() -> bool:
	return state != State.IDLE and state != State.LANDED


func ideal_stroke_time() -> float:
	return rules.stroke_ideal(self)


## +/- seconds counted as perfect / okay for the stroke being held now: the
## rule set's window, times the rod's forgiveness.
func perfect_window() -> float:
	return rules.perfect_window(self) * forgiveness()


func ok_window() -> float:
	return rules.ok_window(self) * forgiveness()


## The rod's forgiveness, or 1 with no rod.
func forgiveness() -> float:
	return rod.forgiveness if rod != null else 1.0


## The most line (m) that can be out: the rod's, or `rule_max` (the rule set's
## own longest line) with no rod.
func max_line(rule_max: float) -> float:
	return rod.max_line_m if rod != null else rule_max


## 0 at the start of a stroke, 1 at its ideal moment, above 1 when late.
func stroke_progress() -> float:
	if phase_ideal <= 0.0:
		return 0.0
	return (_now - phase_start) / phase_ideal


func flight_progress() -> float:
	return clampf((_now - _flight_start) / tuning.flight_time, 0.0, 1.0)


## Unit vector the cast travels along. Aim 0 is straight across the river
## (up the screen, turned by facing_angle).
func aim_direction() -> Vector2:
	var angle := deg_to_rad(aim * tuning.max_aim_degrees)
	var dir := Vector2(sin(angle), -cos(angle))
	return dir.rotated(facing_angle) if facing_angle != 0.0 else dir


func reel_in() -> void:
	state = State.IDLE
	line_out = 0.0
	_scores.clear()
	_cycle.clear()


func update(now: float, r: bool, l: bool) -> void:
	_now = now
	if _needs_release:
		if r or l:
			return
		_needs_release = false
	match state:
		State.IDLE, State.LANDED:
			if r and not l:
				# Every cast starts from the rules' starting line, even a pick-up
				# off the water, so reaching Middle or Long always takes false casts.
				line_out = rules.start_line(self)
				strokes.clear()
				_scores.clear()
				false_casts = 0
				_start_back()

		State.BACK:
			if r and l:
				_score_stroke("back")
				_overlap_start = now
				state = State.BACK_TO_FORWARD
			elif l:
				# R released and L pressed on the same frame: no overlap at all.
				_score_stroke("back")
				_score_overlap(0.0)
				_start_forward()
			elif not r:
				_score_stroke("back")
				_gap_start = now
				state = State.GAP
			elif now - phase_start - phase_ideal > tuning.drop_time:
				_collapse("Held L too long. The line ticked the grass behind you.")

		State.GAP:
			if l:
				_push(0.35, "Gap between bumpers. Press R before letting go of L.")
				_start_forward()
			elif r:
				_start_back()
			elif now - _gap_start > tuning.gap_grace:
				_collapse("Let go of L without pressing R. Overlap them slightly.")

		State.BACK_TO_FORWARD:
			if l and not r:
				_score_overlap(now - _overlap_start)
				_start_forward()
			elif r and not l:
				state = State.BACK
			elif not r and not l:
				_collapse("Let go of both bumpers. The cast fell apart.")
			elif now - _overlap_start > tuning.tailing_overlap * 2.0:
				_collapse("Wind knot! Both bumpers held far too long.")

		State.FORWARD:
			if r and l:
				_score_stroke("forward")
				_overlap_start = now
				state = State.FORWARD_TO_BACK
			elif r:
				_score_stroke("forward")
				_score_overlap(0.0)
				_finish_false_cast()
				_start_back()
			elif not l:
				_score_stroke("forward")
				_deliver()
			elif now - phase_start - phase_ideal > tuning.drop_time:
				_push(0.15, "Held R too long. The line slapped down.")
				_deliver()

		State.FORWARD_TO_BACK:
			if r and not l:
				_score_overlap(now - _overlap_start)
				_finish_false_cast()
				_start_back()
			elif l and not r:
				state = State.FORWARD
			elif not r and not l:
				_deliver()
			elif now - _overlap_start > tuning.tailing_overlap * 2.0:
				_collapse("Wind knot! Both bumpers held far too long.")

		State.FLIGHT:
			if now - _flight_start >= tuning.flight_time:
				state = State.LANDED
				landed.emit(presentation, last_cast_quality)


## Maps how far off the ideal moment a stroke ended (seconds) to 0..1.
func timing_quality(error: float) -> float:
	return CastRules.timing_quality(error, perfect_window(), ok_window())


func overlap_quality(overlap: float) -> float:
	if overlap < tuning.overlap_good_min:
		return 0.7
	var good_max := _overlap_good_max()
	if overlap <= good_max:
		return 1.0
	var t := (overlap - good_max) / (tuning.tailing_overlap - good_max)
	return clampf(lerpf(1.0, 0.4, t), 0.2, 1.0)


func _start_back() -> void:
	state = State.BACK
	_cycle.clear()
	phase_start = _now
	phase_ideal = ideal_stroke_time()


func _start_forward() -> void:
	state = State.FORWARD
	phase_start = _now
	phase_ideal = ideal_stroke_time()


func _score_stroke(stroke_name: String) -> void:
	var elapsed := _now - phase_start
	var ideal := phase_ideal
	var result := rules.score_stroke(self, elapsed, stroke_name)
	strokes.append({"kind": stroke_name, "seconds": elapsed, "ideal": ideal, "quality": result[0]})
	_push(result[0], result[1])


func _score_overlap(overlap: float) -> void:
	var q := overlap_quality(overlap)
	var msg := ""
	if overlap < tuning.overlap_good_min:
		msg = "Overlap the bumpers slightly"
	elif overlap >= tuning.tailing_overlap:
		msg = "Tailing loop. Let go of the first bumper sooner."
	elif q < 1.0:
		msg = "Overlap ran a little long"
	strokes.append({"kind": "overlap", "seconds": overlap, "ideal": _overlap_good_max() * 0.5, "quality": q})
	_push(q, msg, 0.5 if q >= 0.7 else 1.0)


## The longest overlap that still counts as clean, widened by the rod's
## forgiveness but always short of a tailing loop.
func _overlap_good_max() -> float:
	return minf(tuning.overlap_good_max * forgiveness(), tuning.tailing_overlap * 0.9)


func _push(q: float, msg: String, weight := 1.0) -> void:
	_scores.append(Vector2(q, weight))
	_cycle.append(Vector2(q, weight))
	last_score = q
	if msg != "":
		feedback.emit(msg, q)


func _finish_false_cast() -> void:
	var q := _average(_cycle)
	false_casts += 1
	var msg := rules.after_false_cast(self, q)
	if msg != "":
		feedback.emit(msg, q)


func _deliver() -> void:
	var q := _average(_scores)
	var reach := rules.delivery_reach(self, q)
	last_reach = reach
	var scatter := _rng.randf_range(-1.0, 1.0) * tuning.max_scatter_degrees * (1.0 - q)
	landing_offset = aim_direction().rotated(deg_to_rad(scatter)) * reach
	last_cast_quality = q
	if q >= tuning.delicate_quality:
		presentation = "Delicate"
	elif q >= tuning.fair_quality:
		presentation = "Fair"
	else:
		presentation = "Splashy"
	state = State.FLIGHT
	_flight_start = _now
	delivered.emit(landing_offset, q)


func _collapse(reason: String) -> void:
	reel_in()
	_needs_release = true
	feedback.emit(reason, 0.0)
	collapsed.emit(reason)


static func _average(values: Array[Vector2]) -> float:
	var total := 0.0
	var weight := 0.0
	for v in values:
		total += v.x * v.y
		weight += v.y
	return total / weight if weight > 0.0 else 0.0
