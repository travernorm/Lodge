extends Node2D
## Casting practice range. Toggle with T (L3, click the left stick).
##
## While it's on, fish don't bite. A target marks Short, Middle or Long in
## turn, every cast is scored against it, and a stroke log shows how long you
## held each bumper against what the rules wanted. Tab (R3) swaps the casting
## rule set, so different rhythms can be compared back to back.

## Rule sets to cycle through with Tab / R3.
@export var chassis: Array[CastRules] = [
	preload("res://data/cast_rules/classic.tres"),
	preload("res://data/cast_rules/count_false_casts.tres"),
	preload("res://data/cast_rules/find_your_tempo.tres"),
]

const TARGETS := ["Short", "Middle", "Long"]
## Target ring distances (px from the rod tip), one per entry in TARGETS.
## Target distances (m from the rod tip) for Short, Middle and Long.
const TARGET_REACH := [4.0, 8.125, 12.5]
## How far up (m) the distance ruler runs: the longest line you can carry.
const LONG_RULER_M := 14.75
const AUTO_REEL_DELAY := 1.2
const LOG_ROWS := 8
const RESULT_ROWS := 4
const BAR_SCALE := 70.0  # px per second in the stroke log

const COL_PANEL := Color(0, 0, 0, 0.6)
const COL_TEXT := Color("f4efe0")
const COL_DIM := Color(0.96, 0.94, 0.88, 0.65)
const COL_GOOD := Color("8fd16a")
const COL_OK := Color("f2c35a")
const COL_BAD := Color("e8553a")
const COL_TARGET := Color(1, 1, 1, 0.8)
const COL_IDEAL := Color(1, 1, 1, 0.9)

var active := false
var target_index := 0
## Per target: [hits, attempts].
var tally := {"Short": [0, 0], "Middle": [0, 0], "Long": [0, 0]}
var results: Array[String] = []

var _stream: Node2D
var _cast: Node
var _fishing: Node
var _rules_index := 0
var _landed_at := -1.0
var _time := 0.0


func _ready() -> void:
	_stream = get_parent() as Node2D
	_cast = _stream.get_node(^"Cast")
	_fishing = _stream.get_node_or_null(^"Fishing")
	_cast.model.landed.connect(_on_landed)
	_cast.model.collapsed.connect(_on_collapsed)
	for i in chassis.size():
		if chassis[i] == _cast.model.rules:
			_rules_index = i


func current_rules() -> CastRules:
	return _cast.model.rules


func set_active(on: bool) -> void:
	active = on
	if _fishing != null:
		_fishing.enabled = not on
	if on:
		_cast.show_message("Practice: hit the %s target. Tab/R3 switches rules." % TARGETS[target_index], 1.0)
	else:
		_cast.show_message("Practice off. Fish are biting again.", 1.0)


## Swaps the casting rule set. Only between casts.
func select_rules(index: int) -> bool:
	if active and _cast.model.state == CastModel.State.LANDED:
		_cast.model.reel_in()
	elif _cast.model.state != CastModel.State.IDLE:
		_cast.show_message("Reel in first (Circle / Backspace) to switch rules.", 0.5)
		return false
	_rules_index = posmod(index, chassis.size())
	_cast.rules = chassis[_rules_index]
	_cast.model.rules = chassis[_rules_index]
	_cast.show_message("Rules: %s" % chassis[_rules_index].display_name, 1.0)
	return true


func _process(delta: float) -> void:
	_time += delta
	if Input.is_action_just_pressed(Controls.PRACTICE_MODE):
		set_active(not active)
	if Input.is_action_just_pressed(Controls.CYCLE_RULES):
		select_rules(_rules_index + 1)
	if active and _landed_at >= 0.0 and _time - _landed_at > AUTO_REEL_DELAY:
		_landed_at = -1.0
		if active and _cast.model.state == CastModel.State.LANDED:
			_cast.reel_in_line("")
	queue_redraw()


func _on_landed(presentation: String, _quality: float) -> void:
	if not active:
		return
	var model: CastModel = _cast.model
	var target: String = TARGETS[target_index]
	var got := CastRules.distance_label(model.last_reach)
	var hit := got == target
	tally[target][1] += 1
	if hit:
		tally[target][0] += 1
	var line := "%s: %.1f m %s %s, %d false, %s" % [
		target, model.last_reach, got, "HIT" if hit else "miss", model.false_casts, presentation]
	_add_result(line)
	if hit:
		_cast.show_message("Hit! %s, %.1f m." % [got, model.last_reach], 1.0)
	else:
		_cast.show_message("%s, %.1f m. Wanted %s." % [got, model.last_reach, target], 0.4)
	target_index = (target_index + 1) % TARGETS.size()
	_landed_at = _time


func _on_collapsed(_reason: String) -> void:
	if not active:
		return
	var target: String = TARGETS[target_index]
	tally[target][1] += 1
	_add_result("%s: collapsed" % target)


func _add_result(line: String) -> void:
	results.push_front(line)
	if results.size() > RESULT_ROWS:
		results.resize(RESULT_ROWS)


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	if not active:
		return
	_draw_ruler()
	_draw_header()
	_draw_stroke_log()
	_draw_results()
	_draw_target()


func _target_point() -> Vector2:
	var tip: Vector2 = _stream.hand_position() + Vector2(0, -_stream.ROD_LENGTH)
	return tip + Vector2(0, -WorldScale.to_px(TARGET_REACH[target_index]))


## Faint marks up the cast line where Short ends and Middle ends.
func _draw_ruler() -> void:
	var tip: Vector2 = (_stream.hand_position() + Vector2(0, -_stream.ROD_LENGTH)).floor()
	var x := tip.x + 26.0
	var font := ThemeDB.fallback_font
	var col := Color(1, 1, 1, 0.35)
	var top := WorldScale.to_px(LONG_RULER_M)
	draw_line(Vector2(x, tip.y), Vector2(x, tip.y - top), col, 1.0)
	for mark in [0.0, CastRules.SHORT_MAX, CastRules.MIDDLE_MAX]:
		var my := tip.y - WorldScale.to_px(mark)
		draw_line(Vector2(x - 2, my), Vector2(x + 2, my), col, 1.0)
	var bands := [["S", 0.0, CastRules.SHORT_MAX], ["M", CastRules.SHORT_MAX, CastRules.MIDDLE_MAX], ["L", CastRules.MIDDLE_MAX, LONG_RULER_M]]
	for b in bands:
		var y: float = tip.y - WorldScale.to_px((b[1] + b[2]) * 0.5)
		draw_string(font, Vector2(x + 4, y + 3), b[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)


func _draw_target() -> void:
	var p := _target_point().floor()
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	draw_arc(p, 6.0, 0.0, TAU, 20, COL_TARGET, 1.0)
	draw_arc(p, 2.0 + pulse, 0.0, TAU, 12, COL_TARGET, 1.0)
	draw_string(ThemeDB.fallback_font, p + Vector2(9, 3), TARGETS[target_index], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_TARGET)


func _draw_header() -> void:
	var font := ThemeDB.fallback_font
	var w: float = _stream.VIEW.x
	draw_rect(Rect2(0, 0, w, 32), COL_PANEL)
	var rules := current_rules()
	draw_string(font, Vector2(4, 9), "PRACTICE  %s" % rules.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_GOOD)
	var keys := "Tab/R3 rules  T/L3 exit"
	var kw := font.get_string_size(keys, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	draw_string(font, Vector2(w - kw - 4, 9), keys, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_DIM)
	draw_multiline_string(font, Vector2(4, 18), rules.description, HORIZONTAL_ALIGNMENT_LEFT, w - 8, 8, 2, COL_DIM)


## Each stroke of the current (or last) cast as a bar: its length is how long
## you held it, the white tick is what the rules wanted, the colour is its score.
func _draw_stroke_log() -> void:
	var font := ThemeDB.fallback_font
	var model: CastModel = _cast.model
	var rows: Array[Dictionary] = []
	for s in model.strokes:
		if s.kind != "overlap":
			rows.append(s)
	# The stroke you're holding right now, growing toward its tick.
	if model.state == CastModel.State.BACK or model.state == CastModel.State.FORWARD:
		rows.append({"kind": "back" if model.state == CastModel.State.BACK else "forward",
			"seconds": model.stroke_progress() * model.phase_ideal, "ideal": model.phase_ideal, "quality": -1.0})
	if rows.size() > LOG_ROWS:
		rows = rows.slice(rows.size() - LOG_ROWS)
	var origin := Vector2(_stream.VIEW.x - 104, 36)
	var height := 12 + rows.size() * 7
	draw_rect(Rect2(origin - Vector2(2, 2), Vector2(102, height)), COL_PANEL)
	draw_string(font, origin + Vector2(0, 7), "strokes  falses %d  line %.1f m" % [model.false_casts, model.line_out],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_DIM)
	for i in rows.size():
		var s := rows[i]
		var y := origin.y + 11 + i * 7
		var col := COL_GOOD if s.quality >= 0.99 else (COL_OK if s.quality >= 0.6 else COL_BAD)
		if s.quality < 0.0:
			col = COL_DIM
		draw_string(font, Vector2(origin.x, y + 5), "B" if s.kind == "back" else "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_DIM)
		var bar := Rect2(origin.x + 7, y, minf(s.seconds * BAR_SCALE, 90.0), 4)
		draw_rect(bar, col)
		var ix := origin.x + 7 + minf(s.ideal * BAR_SCALE, 90.0)
		draw_line(Vector2(ix, y - 1), Vector2(ix, y + 5), COL_IDEAL, 1.0)


func _draw_results() -> void:
	var font := ThemeDB.fallback_font
	var origin := Vector2(4, 36)
	var summary := PackedStringArray()
	for t in TARGETS:
		summary.append("%s %d/%d" % [t, tally[t][0], tally[t][1]])
	var lines := PackedStringArray(["  ".join(summary)])
	lines.append_array(PackedStringArray(results))
	draw_rect(Rect2(origin - Vector2(2, 2), Vector2(176, 4 + lines.size() * 9)), COL_PANEL)
	for i in lines.size():
		var col := COL_TEXT if i == 0 else (COL_GOOD if lines[i].contains("HIT") else COL_DIM)
		draw_string(font, origin + Vector2(0, 7 + i * 9), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)
