extends Node2D
## Connects the casting rhythm (CastModel) to the stream scene. It reads the
## bumpers, draws the line in the air, the fly, timing meter and coaching text, and
## plays the rumble "tug" when the line loads. Once the fly lands, the sibling
## Fishing node takes over the drift, rises and fights.
##
## Expects its parent to be the stream scene (scripts/stream_scene.gd).

@export var tuning: CastTuning = preload("res://data/cast_tuning.tres")

const FEEDBACK_SECONDS := 1.8
const AIM_SPEED := 1.6  # aim units per second at full stick
const BACK_CAST_SCALE := 0.3  # the back cast is foreshortened: it's behind and above you
const LINE_HEIGHT := 12.0  # px the airborne line floats above its shadow
const METER_SIZE := Vector2(4, 24)
const METER_SPAN := 1.5  # the meter covers 0..1.5x the ideal stroke time
const RING_SECONDS := 0.9

const COL_LINE := Color("f2e6b8")
const COL_LINE_WET := Color("d8cfa6")
const COL_SHADOW := Color(0, 0, 0, 0.22)
const COL_FLY := Color("d9563a")
const COL_FLY_POST := Color("ffffff")
const COL_TARGET := Color(1, 1, 1, 0.45)
const COL_METER_BG := Color(0, 0, 0, 0.55)
const COL_METER_FILL := Color("f4efe0")
const COL_METER_OK := Color(0.56, 0.82, 0.42, 0.45)
const COL_METER_PERFECT := Color("8fd16a")
const COL_TEXT := Color("f4efe0")
const COL_TEXT_GOOD := Color("b8e68f")
const COL_TEXT_BAD := Color("f2a65a")
const COL_RING := Color(1, 1, 1, 0.8)

var model: CastModel
var fly_pos := Vector2.ZERO

var _stream: Node2D
var _fishing: Node
var _time := 0.0
var _feedback := ""
var _feedback_quality := 1.0
var _feedback_at := -100.0
var _rings: Array[Vector3] = []  # x, y = position; z = time it appeared
var _ring_size := 4.0
var _flight_from := Vector2.ZERO
var _flight_to := Vector2.ZERO
var _tugged_stroke := -1.0
var _snagged := false


func _ready() -> void:
	add_to_group(&"cast")
	_stream = get_parent() as Node2D
	_fishing = _stream.get_node_or_null(^"Fishing")
	model = CastModel.new(tuning)
	model.feedback.connect(show_message)
	model.delivered.connect(_on_delivered)
	model.landed.connect(_on_landed)
	model.collapsed.connect(func(_reason: String): Controls.rumble(0.5, 0.2, 0.2))


func _process(delta: float) -> void:
	_time += delta
	if model.is_busy():
		model.aim = clampf(model.aim + Controls.move_vector().x * AIM_SPEED * delta, -1.0, 1.0)
	elif model.state == CastModel.State.IDLE:
		model.aim = move_toward(model.aim, 0.0, delta * 2.0)

	var fighting: bool = _fishing != null and not _fishing.can_pick_up()
	if model.state == CastModel.State.LANDED and not fighting:
		if _fishing == null:
			_drift(delta)
		if Input.is_action_just_pressed(Controls.BACK):
			reel_in_line("Reeled in.")

	var r: bool = Input.is_action_pressed(Controls.CAST_BACK) and not fighting
	model.update(_time, r, Input.is_action_pressed(Controls.CAST_FORWARD))
	_tug()
	queue_redraw()


## Whether the angler can walk. The line has to be reeled in first.
func allows_walking() -> bool:
	return model.state == CastModel.State.IDLE


## The rod's direction for the current point in the cast, or ZERO to let the
## stream scene aim it with the right stick.
func rod_pose() -> Vector2:
	var dir := model.aim_direction()
	match model.state:
		CastModel.State.BACK, CastModel.State.GAP:
			return (-dir + Vector2(0.6, 0.0)).normalized()
		CastModel.State.BACK_TO_FORWARD, CastModel.State.FORWARD_TO_BACK:
			return Vector2(0.6, -0.2).normalized()
		CastModel.State.FORWARD, CastModel.State.FLIGHT:
			return dir
		CastModel.State.LANDED:
			var target: Vector2 = _fishing.line_target() if _fishing != null else fly_pos
			return ((target - _stream.hand_position()).normalized() + Vector2(0.0, -1.0)).normalized()
	return Vector2.ZERO


func debug_lines() -> PackedStringArray:
	var state_name: String = CastModel.State.keys()[model.state]
	return PackedStringArray([
		"cast %s  line %d px" % [state_name.to_lower(), roundi(model.line_out)],
		"ideal %d ms  last %.2f  falses %d" % [roundi(model.ideal_stroke_time() * 1000.0), model.last_score, model.false_casts],
	])


func _tug() -> void:
	# A short rumble when the line straightens, which is the moment to switch bumpers.
	var stroke := model.state == CastModel.State.BACK or model.state == CastModel.State.FORWARD
	if not stroke or is_equal_approx(_tugged_stroke, model.phase_start):
		return
	var early_edge := 1.0 - tuning.perfect_window / model.phase_ideal
	if model.stroke_progress() >= early_edge:
		_tugged_stroke = model.phase_start
		Controls.rumble(0.0, 0.35, 0.06)


func _drift(delta: float) -> void:
	if _snagged:
		return
	fly_pos += _stream.flow_at(fly_pos) * delta
	var out := fly_pos.distance_to(_stream.rod_tip())
	model.line_out = clampf(out, tuning.line_start, tuning.line_max)
	if fly_pos.x > _stream.VIEW.x - 4.0 or out > tuning.line_max + 24.0:
		reel_in_line("Drift's done. Reeled in.")


func reel_in_line(message: String) -> void:
	model.reel_in()
	_snagged = false
	if message != "":
		show_message(message, 1.0)


## Shows a coaching line at the bottom of the screen. quality 0..1 picks the colour.
func show_message(text: String, quality: float) -> void:
	_feedback = text
	_feedback_quality = quality
	_feedback_at = _time


func _on_delivered(offset: Vector2, _quality: float) -> void:
	_flight_from = _line_end(_stream.rod_tip(), 1.0)
	_flight_to = _stream.rod_tip() + offset
	_snagged = false


func _on_landed(presentation: String, quality: float) -> void:
	fly_pos = _flight_to
	_ring_size = lerpf(11.0, 3.0, quality)
	_rings.append(Vector3(fly_pos.x, fly_pos.y, _time))
	if not _stream.is_water(fly_pos):
		_snagged = true
		show_message("Snagged on the bank. Press B to reel in.", 0.0)
		Controls.rumble(0.4, 0.0, 0.12)
		return
	show_message("%s landing. %d px out." % [presentation, roundi(fly_pos.distance_to(_stream.rod_tip()))], quality)
	Controls.rumble(lerpf(0.5, 0.05, quality), 0.0, 0.08)


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	var tip: Vector2 = _stream.rod_tip()
	match model.state:
		CastModel.State.BACK, CastModel.State.GAP, CastModel.State.BACK_TO_FORWARD:
			_draw_back_cast(tip)
		CastModel.State.FORWARD, CastModel.State.FORWARD_TO_BACK:
			_draw_forward_cast(tip)
		CastModel.State.FLIGHT:
			_draw_flight(tip)
		CastModel.State.LANDED:
			if _fishing == null:
				_draw_on_water(tip)
	_draw_rings()
	if model.is_busy():
		_draw_target(tip)
		_draw_meter()
	_draw_feedback()


## Where the end of the forward line is at a given unroll fraction.
func _line_end(tip: Vector2, unroll: float) -> Vector2:
	return tip + model.aim_direction() * model.line_out * clampf(unroll, 0.05, 1.0)


func _draw_back_cast(tip: Vector2) -> void:
	var p := model.stroke_progress() if model.state == CastModel.State.BACK else 1.0
	var dir := -model.aim_direction()
	var reach := model.line_out * BACK_CAST_SCALE * clampf(p, 0.1, 1.0)
	var end := tip + dir * reach
	# Late: the line sinks toward the grass.
	var lateness := maxf(0.0, (p - 1.0) * model.phase_ideal / tuning.drop_time)
	var height := LINE_HEIGHT * (1.0 - clampf(lateness, 0.0, 1.0))
	var loop := (1.0 - clampf(p, 0.0, 1.0)) * 6.0
	_draw_airborne_line(tip, end, height, loop)


func _draw_forward_cast(tip: Vector2) -> void:
	var p := model.stroke_progress() if model.state == CastModel.State.FORWARD else 1.0
	var end := _line_end(tip, p)
	var lateness := maxf(0.0, (p - 1.0) * model.phase_ideal / tuning.drop_time)
	var height := LINE_HEIGHT * (1.0 - clampf(lateness, 0.0, 1.0))
	var loop := (1.0 - clampf(p, 0.0, 1.0)) * 8.0
	_draw_airborne_line(tip, end, height, loop)


func _draw_flight(tip: Vector2) -> void:
	var t := model.flight_progress()
	var pos := _flight_from.lerp(_flight_to, t)
	var height := LINE_HEIGHT * (1.0 - t)
	_draw_airborne_line(tip, pos, height, 2.0)


func _draw_on_water(tip: Vector2) -> void:
	var mid := (tip + fly_pos) * 0.5
	var belly: Vector2 = mid + _stream.flow_at(mid) * 0.25  # the current bows the line downstream
	_draw_curve(tip, belly, fly_pos, COL_LINE_WET)
	_draw_fly(fly_pos)


## A line in the air: its shadow on the ground, then the line lifted by height.
## loop bows the middle sideways like an unrolling loop.
func _draw_airborne_line(from: Vector2, to: Vector2, height: float, loop: float) -> void:
	var lift := Vector2(0.0, -height)
	var side := (to - from).orthogonal().normalized() * loop
	var mid := (from + to) * 0.5 + side
	_draw_curve(from, mid, to, COL_SHADOW)
	_draw_curve(from, mid + lift * 0.7, to + lift, COL_LINE)
	_draw_fly(to + lift)


func _draw_curve(a: Vector2, control: Vector2, b: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	var steps := 14
	for i in steps + 1:
		var t := float(i) / steps
		var p := a.lerp(control, t).lerp(control.lerp(b, t), t)
		points.append(p.floor() + Vector2(0.5, 0.5))
	draw_polyline(points, color, 1.0)


func _draw_fly(p: Vector2) -> void:
	if _fishing != null:
		_fishing.current_fly().draw_at(self, p)
		return
	var q := p.floor()
	draw_rect(Rect2(q + Vector2(-1, 0), Vector2(3, 2)), COL_FLY)
	draw_rect(Rect2(q + Vector2(0, -1), Vector2(1, 1)), COL_FLY_POST)


func _draw_target(tip: Vector2) -> void:
	var p := (tip + model.aim_direction() * model.line_out).floor()
	for o in [Vector2(-3, 0), Vector2(2, 0), Vector2(0, -3), Vector2(0, 2)]:
		draw_rect(Rect2(p + o, Vector2(1, 1)), COL_TARGET)


## Vertical timing meter beside the angler. It fills during each stroke; switch
## bumpers while the fill is in the green band.
func _draw_meter() -> void:
	var origin: Vector2 = (_stream.angler_pos + Vector2(-12, -26)).floor()
	var rect := Rect2(origin, METER_SIZE)
	draw_rect(rect.grow(1), COL_METER_BG)
	var stroke := model.state == CastModel.State.BACK or model.state == CastModel.State.FORWARD
	var ideal := model.phase_ideal if model.phase_ideal > 0.0 else model.ideal_stroke_time()
	_meter_band(rect, 1.0, tuning.ok_window / ideal, COL_METER_OK)
	_meter_band(rect, 1.0, tuning.perfect_window / ideal, COL_METER_PERFECT)
	if stroke:
		var p := clampf(model.stroke_progress() / METER_SPAN, 0.0, 1.0)
		var h := roundf(METER_SIZE.y * p)
		var in_zone := absf(model.stroke_progress() - 1.0) * ideal <= tuning.perfect_window
		var col := COL_METER_PERFECT if in_zone else COL_METER_FILL
		draw_rect(Rect2(rect.position + Vector2(1, METER_SIZE.y - h), Vector2(METER_SIZE.x - 2, h)), col)
	var label := "R" if model.state in [CastModel.State.BACK, CastModel.State.GAP] else "L"
	draw_string(ThemeDB.fallback_font, origin + Vector2(-1, -2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_TEXT)


func _meter_band(rect: Rect2, center: float, half_width: float, color: Color) -> void:
	var top := clampf((center + half_width) / METER_SPAN, 0.0, 1.0)
	var bottom := clampf((center - half_width) / METER_SPAN, 0.0, 1.0)
	var y0 := rect.position.y + METER_SIZE.y * (1.0 - top)
	var y1 := rect.position.y + METER_SIZE.y * (1.0 - bottom)
	draw_rect(Rect2(rect.position.x, roundf(y0), METER_SIZE.x, maxf(1.0, roundf(y1 - y0))), color)


func _draw_rings() -> void:
	var alive: Array[Vector3] = []
	for r in _rings:
		var age := _time - r.z
		if age > RING_SECONDS:
			continue
		alive.append(r)
		var t := age / RING_SECONDS
		var col := COL_RING
		col.a *= 1.0 - t
		draw_arc(Vector2(r.x, r.y), 1.0 + _ring_size * t, 0.0, TAU, 16, col, 1.0)
	_rings = alive


func _draw_feedback() -> void:
	var age := _time - _feedback_at
	if age > FEEDBACK_SECONDS or _feedback == "":
		return
	var col := COL_TEXT_GOOD if _feedback_quality >= 0.85 else (COL_TEXT if _feedback_quality >= 0.5 else COL_TEXT_BAD)
	col.a = clampf((FEEDBACK_SECONDS - age) / 0.4, 0.0, 1.0)
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(_feedback, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var pos := Vector2(roundf((_stream.VIEW.x - width) * 0.5), _stream.VIEW.y - 24)
	draw_rect(Rect2(pos + Vector2(-3, -8), Vector2(width + 6, 10)), Color(0, 0, 0, 0.5 * col.a))
	draw_string(font, pos, _feedback, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)
