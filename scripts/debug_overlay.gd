extends Control
## Controller debug overlay. Toggle with Select/View (F1 on keyboard).
## On by default in debug builds.
##
## The top strip is a 2 second timeline of the R and L bumpers, which is how
## we'll tune the back cast / forward cast rhythm on a real Steam Deck. It also
## shows how long each bumper was last held and how long they overlapped.
## Press A (Space) while the overlay is open to test rumble.

const HISTORY_SECONDS := 2.0
const FONT_SIZE := 8

const COL_PANEL := Color(0, 0, 0, 0.55)
const COL_R := Color("f2a65a")
const COL_L := Color("6ec3e0")
const COL_OFF := Color(1, 1, 1, 0.15)
const COL_TEXT := Color("f4efe0")

var _time := 0.0
var _history: Array[Vector3] = []  # x = time, y = R held, z = L held
var _r_down_at := -1.0
var _l_down_at := -1.0
var _overlap_start := -1.0
var _last_r_ms := 0
var _last_l_ms := 0
var _last_overlap_ms := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = OS.is_debug_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(Controls.TOGGLE_DEBUG):
		visible = not visible
	elif visible and event.is_action_pressed(Controls.INTERACT):
		Controls.rumble(0.3, 0.7, 0.15)


func _process(delta: float) -> void:
	_time += delta
	var r := Input.is_action_pressed(Controls.CAST_BACK)
	var l := Input.is_action_pressed(Controls.CAST_FORWARD)
	_track(r, l)
	_history.append(Vector3(_time, 1.0 if r else 0.0, 1.0 if l else 0.0))
	while not _history.is_empty() and _history[0].x < _time - HISTORY_SECONDS:
		_history.pop_front()
	if visible:
		queue_redraw()


func _track(r: bool, l: bool) -> void:
	if r and _r_down_at < 0.0:
		_r_down_at = _time
	elif not r and _r_down_at >= 0.0:
		_last_r_ms = int((_time - _r_down_at) * 1000.0)
		_r_down_at = -1.0
	if l and _l_down_at < 0.0:
		_l_down_at = _time
	elif not l and _l_down_at >= 0.0:
		_last_l_ms = int((_time - _l_down_at) * 1000.0)
		_l_down_at = -1.0
	var both := r and l
	if both and _overlap_start < 0.0:
		_overlap_start = _time
	elif not both and _overlap_start >= 0.0:
		_last_overlap_ms = int((_time - _overlap_start) * 1000.0)
		_overlap_start = -1.0


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var w := size.x

	# Bumper timeline
	var strip := Rect2(4, 4, w - 8, 26)
	draw_rect(strip, COL_PANEL)
	var lane_x := strip.position.x + 14
	var lane_w := strip.size.x - 18
	draw_string(font, Vector2(strip.position.x + 3, 14), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_R)
	draw_string(font, Vector2(strip.position.x + 3, 26), "L", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_L)
	draw_rect(Rect2(lane_x, 8, lane_w, 7), COL_OFF)
	draw_rect(Rect2(lane_x, 19, lane_w, 7), COL_OFF)
	for i in range(1, _history.size()):
		var a := _history[i - 1]
		var b := _history[i]
		var x0 := lane_x + lane_w * (1.0 - (_time - a.x) / HISTORY_SECONDS)
		var x1 := lane_x + lane_w * (1.0 - (_time - b.x) / HISTORY_SECONDS)
		var seg := maxf(x1 - x0, 1.0)
		if b.y > 0.5:
			draw_rect(Rect2(x0, 8, seg, 7), COL_R)
		if b.z > 0.5:
			draw_rect(Rect2(x0, 19, seg, 7), COL_L)

	# Readouts
	var lines := PackedStringArray()
	var cast := get_tree().get_first_node_in_group(&"cast")
	if cast != null:
		lines = cast.debug_lines()
	var info := Rect2(4, 33, 150, 30 + 9 * lines.size())
	draw_rect(info, COL_PANEL)
	draw_string(font, Vector2(8, 42), "R held %d ms   L held %d ms" % [_last_r_ms, _last_l_ms],
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_TEXT)
	draw_string(font, Vector2(8, 51), "R/L overlap %d ms" % _last_overlap_ms,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_TEXT)
	draw_string(font, Vector2(8, 60), "%s  %d fps" % [Controls.pad_name().left(22), Engine.get_frames_per_second()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_TEXT)
	for i in lines.size():
		draw_string(font, Vector2(8, 69 + 9 * i), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_TEXT)

	# Sticks
	_draw_stick(Vector2(20, size.y - 20), Controls.move_vector(), "move")
	_draw_stick(Vector2(w - 20, size.y - 20), Controls.rod_vector(), "rod")


func _draw_stick(center: Vector2, value: Vector2, label: String) -> void:
	var radius := 12.0
	draw_circle(center, radius + 2, COL_PANEL)
	draw_arc(center, radius, 0, TAU, 24, COL_OFF, 1.0)
	draw_circle(center + value * radius, 2.5, COL_TEXT)
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius, -radius - 4), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_TEXT)
