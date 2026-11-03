extends Control
## Debug overlays. Select/View (Create on a PS5 pad, F1 on keyboard) cycles:
## hidden -> controller view -> read-the-water view -> hidden. Starts hidden.
##
## Controller view:
## The top strip is a 2 second timeline of the L and R bumpers, which is how
## we'll tune the back cast / forward cast rhythm on a real Steam Deck. It also
## shows how long each bumper was last held and how long they overlapped.
## Opening it gives a short rumble, to check the pad's haptics.
##
## Read-the-water view draws the river field the fly drifts on: current arrows
## (longer and whiter is faster), the thalweg (deepest, fastest line), seams
## (where the speed changes sharply), green cells where a trout would hold, and
## a white ring where each trout is actually holding.

const HISTORY_SECONDS := 2.0
const FONT_SIZE := 8

const COL_PANEL := Color(0, 0, 0, 0.55)
const COL_R := Color("f2a65a")
const COL_L := Color("6ec3e0")
const COL_OFF := Color(1, 1, 1, 0.15)
const COL_TEXT := Color("f4efe0")
const COL_SLOW := Color("3a6fd8")
const COL_FAST := Color("f4efe0")
const COL_THALWEG := Color("f2c35a")
const COL_SEAM := Color("f2a65a")
const COL_LIE := Color("8fd16a")
const ARROW_GRID := 12.0

enum View { HIDDEN, CONTROLS, WATER }

var view := View.HIDDEN

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
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(Controls.TOGGLE_DEBUG):
		view = ((view + 1) % View.size()) as View
		visible = view != View.HIDDEN
		if view == View.CONTROLS:
			Controls.rumble(0.3, 0.7, 0.15)  # rumble test


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
	if view == View.WATER:
		_draw_water()
		return
	var font := ThemeDB.fallback_font
	var w := size.x

	# Bumper timeline
	var strip := Rect2(4, 4, w - 8, 26)
	draw_rect(strip, COL_PANEL)
	var lane_x := strip.position.x + 14
	var lane_w := strip.size.x - 18
	draw_string(font, Vector2(strip.position.x + 3, 14), "L", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_R)
	draw_string(font, Vector2(strip.position.x + 3, 26), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_L)
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
	var fishing := get_tree().get_first_node_in_group(&"fishing")
	if fishing != null:
		lines.append_array(fishing.debug_lines())
	var info := Rect2(4, 33, 150, 30 + 9 * lines.size())
	draw_rect(info, COL_PANEL)
	draw_string(font, Vector2(8, 42), "L held %d ms   R held %d ms" % [_last_r_ms, _last_l_ms],
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_TEXT)
	draw_string(font, Vector2(8, 51), "L/R overlap %d ms" % _last_overlap_ms,
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


func _draw_water() -> void:
	var stream := get_tree().get_first_node_in_group(&"stream")
	if stream == null:
		return
	# The river works in metres; this view draws in pixels. It sits on its own
	# canvas layer, so world drawing is shifted by the camera, and only the
	# cells on screen are drawn.
	var river: RiverField = stream.river
	var origin: Vector2 = stream.screen_origin() if stream.has_method(&"screen_origin") else Vector2.ZERO
	var view_m := Rect2(WorldScale.vec_to_m(origin), WorldScale.vec_to_m(size))
	var cell_px := WorldScale.to_px(RiverField.CELL)
	var i0 := maxi(0, floori(view_m.position.x / RiverField.CELL))
	var i1 := mini(river.cols - 1, ceili(view_m.end.x / RiverField.CELL))
	var j0 := maxi(0, floori((view_m.position.y - river.top) / RiverField.CELL))
	var j1 := mini(river.rows - 1, ceili((view_m.end.y - river.top) / RiverField.CELL))
	draw_set_transform(-origin)

	# Trout lies: green, brighter where a fish would hold.
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var score := river.lie[j * river.cols + i]
			if score > 0.15:
				var c := WorldScale.vec_to_px(river.cell_pos(i, j))
				draw_rect(Rect2(c - Vector2.ONE * cell_px * 0.5, Vector2.ONE * cell_px), Color(COL_LIE, 0.2 + 0.6 * score))

	# Seams: orange dots where the speed changes sharply.
	for j in range(j0 - j0 % 2, j1 + 1, 2):
		for i in range(i0 - i0 % 2, i1 + 1, 2):
			if river.seam[j * river.cols + i] > 0.55:
				draw_rect(Rect2(WorldScale.vec_to_px(river.cell_pos(i, j)), Vector2.ONE), COL_SEAM)

	# Thalweg: dotted line along the deepest, fastest water.
	for k in river.thalweg.size():
		var tp := WorldScale.vec_to_px(river.thalweg[k])
		if Rect2(origin, size).grow(4).has_point(tp):
			draw_rect(Rect2(tp.round(), Vector2(2, 1)), COL_THALWEG)

	# Current arrows, on a grid fixed to the world.
	var y := floorf(origin.y / ARROW_GRID) * ARROW_GRID + ARROW_GRID * 0.5
	while y < origin.y + size.y:
		var x := floorf(origin.x / ARROW_GRID) * ARROW_GRID + ARROW_GRID * 0.5
		while x < origin.x + size.x:
			var p := Vector2(x, y)
			var v := WorldScale.vec_to_px(river.flow_at(WorldScale.vec_to_m(p)))
			var speed := v.length()
			if speed > 0.5:
				var dir := v / speed
				var tip := p + dir * clampf(speed * 0.18, 1.5, 9.0)
				var col := COL_SLOW.lerp(COL_FAST, clampf(speed / WorldScale.to_px(RiverField.WATER_SPEED), 0.0, 1.0))
				draw_line(p, tip, col, 1.0)
				draw_rect(Rect2(tip.floor(), Vector2.ONE), col)
				draw_rect(Rect2((tip - dir * 1.5 + dir.orthogonal()).floor(), Vector2.ONE), col)
				draw_rect(Rect2((tip - dir * 1.5 - dir.orthogonal()).floor(), Vector2.ONE), col)
			x += ARROW_GRID
		y += ARROW_GRID

	# Where each trout is holding.
	var fishing := get_tree().get_first_node_in_group(&"fishing")
	if fishing != null:
		for f in fishing.fish:
			if f.state != Fish.State.CAUGHT:
				draw_arc(WorldScale.vec_to_px(f.lie), 3.5, 0.0, TAU, 12, COL_FAST, 1.0)
	draw_set_transform(Vector2.ZERO)

	# Key, and what the water is doing under the fly.
	var font := ThemeDB.fallback_font
	var fly_line := ""
	if fishing != null and fishing.phase == 1:  # drifting
		var fly: Vector2 = fishing.drift.fly
		fly_line = "fly lane %.1f m/s  seam %.1f  lie %.1f" % [
			river.flow_at(fly).length(), river.seam_at(fly), river.lie_at(fly)]
	var panel := Rect2(4, 4, 208, 22 if fly_line.is_empty() else 31)
	draw_rect(panel, COL_PANEL)
	draw_string(font, Vector2(8, 12), "READ THE WATER", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_TEXT)
	draw_string(font, Vector2(132, 12), "F1 / View: hide", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(COL_TEXT, 0.6))
	draw_string(font, Vector2(8, 21), "current", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_FAST)
	draw_string(font, Vector2(48, 21), "thalweg", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_THALWEG)
	draw_string(font, Vector2(92, 21), "seams", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_SEAM)
	draw_string(font, Vector2(126, 21), "trout lies", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_LIE)
	if not fly_line.is_empty():
		draw_string(font, Vector2(8, 30), fly_line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_TEXT)
