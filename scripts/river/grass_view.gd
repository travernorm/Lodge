class_name GrassView
extends Node2D
## Draws the tall grass on the bank (REQ-0012): the clumps GrassField grows in
## each GrassPatch, leaning in the wind and away from the angler. A view: it
## owns the field and the wind, and only reads the angler and the day.
##
## Wiring: the stream scene calls setup(river) once and angler_at() each frame,
## and puts this node under the angler. main.tscn connects the fishing node's
## conditions_changed (the wind follows the weather) and the debug overlay's
## view_changed.
##
## Drawing order: clumps behind the angler draw here, under him. Clumps just in
## front of his feet draw on a child layer above him, so he stands in the grass.
##
## Debug: Select / F1 to the Grass view shows the variant and the wind; there,
## R2 / F2 steps through the variants (A lean, B part and trail, C rustle).

const FONT_SIZE := 8
const COL_PANEL := Color(0, 0, 0, 0.55)
const COL_TEXT := Color("f4efe0")
## Clumps this close in front of the angler's feet (m, across and down) draw over him.
const FRONT_REACH_M := Vector2(1.6, 1.5)
## The debug overlay's Grass view (its View.GRASS; playthrough_test checks they match).
const DEBUG_VIEW := 4
## Placeholder clumps: how many blades, and how many different clumps.
const BLADES := 5
const PLACEHOLDERS := 4

@export var look: GrassLook
## Seeds where the clumps grow and the day's wind.
@export var grass_seed := 7

var field := GrassField.new()
var wind := Wind.new()
var push := GrassField.Push.LEAN

var _day: Conditions
var _angler := Vector2.INF
var _panel := false
var _front: Node2D
var _rng := RandomNumberGenerator.new()
## The clumps drawn when the look has no sprites, baked once in setup().
var _placeholders: Array[Texture2D] = []


func _ready() -> void:
	_front = Node2D.new()
	_front.z_index = 1
	_front.draw.connect(_draw_front)
	add_child(_front)
	if look != null:
		push = look.push


## Grows the grass for the river's patches. Called once by the stream scene.
func setup(river: RiverField) -> void:
	if look == null:
		return
	_rng.seed = grass_seed
	if look.clumps.is_empty():
		_placeholders = []
		for k in PLACEHOLDERS:
			_placeholders.append(_bake_placeholder(k))
	field = GrassField.grow(river, look, _rng, maxi(look.clumps.size(), PLACEHOLDERS))
	wind = Wind.new(_rng)
	wind.ease_seconds = look.wind_ease_seconds
	wind.gust_size_m = look.gust_size_m
	wind.gust_speed_mps = look.gust_speed_mps
	wind.blow_for(_day, look.wind_by_weather)
	wind.strength = wind.target


## Where the angler's feet are (screen px), each frame.
func angler_at(feet: Vector2) -> void:
	_angler = WorldScale.vec_to_m(feet)


## The day changed: the wind eases toward the new weather's strength.
func show_conditions(c: Conditions) -> void:
	_day = c
	if look != null:
		wind.blow_for(c, look.wind_by_weather)


## The debug overlay's view changed. The Grass view shows the numbers.
func set_debug_view(view: int) -> void:
	_panel = view == DEBUG_VIEW


## The variant on trial.
func set_push(p: GrassField.Push) -> void:
	push = p


func _unhandled_input(event: InputEvent) -> void:
	if _panel and event.is_action_pressed(Controls.DEBUG_WEATHER):
		get_viewport().set_input_as_handled()
		set_push(((push + 1) % GrassField.Push.size()) as GrassField.Push)


func _process(delta: float) -> void:
	if look == null or field.size() == 0:
		return
	wind.step(delta)
	if _angler != Vector2.INF:
		field.step(delta, _angler, push, look)
	queue_redraw()
	_front.queue_redraw()


func _draw() -> void:
	_draw_clumps(self, false)


func _draw_front() -> void:
	_draw_clumps(_front, true)
	if _panel:
		_draw_panel()


## The clumps on screen, behind the angler or just in front of him.
func _draw_clumps(ci: CanvasItem, front: bool) -> void:
	if look == null:
		return
	var tall := WorldScale.to_px(look.height_m) + 8.0
	var view := (get_canvas_transform().affine_inverse() * get_viewport_rect()).grow(tall)
	var from := field.first_at(WorldScale.to_m(view.position.y))
	var to := field.first_at(WorldScale.to_m(view.end.y))
	for i in range(from, to):
		var base := WorldScale.vec_to_px(field.pos[i]).floor()
		if view.has_point(base) and _in_front(i) == front:
			_draw_clump(ci, i, base)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


func _in_front(i: int) -> bool:
	if _angler == Vector2.INF:
		return false
	var d := field.pos[i] - _angler
	return d.y > 0.0 and d.y < FRONT_REACH_M.y and absf(d.x) < FRONT_REACH_M.x


## One clump, sheared so its top leans by its sway and squashed as it lies flat.
func _draw_clump(ci: CanvasItem, i: int, base: Vector2) -> void:
	var s := field.sway(i, wind, look)
	var squash := 1.0 - field.flat[i]
	var sprites: Array[Texture2D] = look.clumps if not look.clumps.is_empty() else _placeholders
	var tex: Texture2D = null
	if not sprites.is_empty():
		tex = sprites[field.kind[i] % sprites.size()]
	if look.flat_clump != null and field.flat[i] > 0.5 * look.flatten:
		tex = look.flat_clump
		squash = 1.0
	if tex == null:
		return
	ci.draw_set_transform_matrix(Transform2D(Vector2.RIGHT, Vector2(-s, squash), base))
	var sz := tex.get_size()
	ci.draw_texture(tex, Vector2(-floorf(sz.x * 0.5), -sz.y))


## Placeholder until Traver's clump sprites arrive: a few blades, dark at the
## root and bright at the tip, curling outward, painted once into a texture so
## each clump is a single draw.
func _bake_placeholder(k: int) -> Texture2D:
	var h := roundi(WorldScale.to_px(look.height_m))
	var w := roundi(WorldScale.to_px(look.width_m))
	var img := Image.create(w + 4, h + 1, false, Image.FORMAT_RGBA8)
	var mid := w / 2 + 2
	var mid_tint := look.base_tint.lerp(look.tip_tint, 0.4)
	var ph := k * 1.7 + 0.4
	for b in BLADES:
		var t := (b + 0.5) / BLADES - 0.5
		var x0 := mid + roundf(t * w * 0.5)
		var bh := roundf(h * (0.7 + 0.3 * absf(sin(ph * 3.0 + b * 1.9))))
		var tip := Vector2(x0 + roundf(t * w * 0.9 + signf(t + 0.01) * absf(sin(ph + b))), h - bh)
		var knee := Vector2(roundf(lerpf(x0, tip.x, 0.25)), roundf(h - bh * 0.55))
		_paint_line(img, Vector2(x0, h), knee, mid_tint)
		_paint_line(img, knee, tip, look.tip_tint)
		_paint_line(img, Vector2(x0, h), Vector2(x0, h), look.base_tint)
	return ImageTexture.create_from_image(img)


static func _paint_line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var n := maxi(ceili(maxf(absf(b.x - a.x), absf(b.y - a.y))), 1)
	for q in n + 1:
		var p := Vector2i(a.lerp(b, float(q) / n).round())
		if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
			img.set_pixelv(p, col)


func _draw_panel() -> void:
	var origin := (get_canvas_transform().affine_inverse() * Vector2.ZERO).floor()
	_front.draw_set_transform(origin)
	var font := ThemeDB.fallback_font
	var text := "R2/F2  Grass %s   wind %.2f" % [GrassField.PUSH_NAMES[push], wind.strength]
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	_front.draw_rect(Rect2(2.0, 2.0, w + 4.0, FONT_SIZE + 4.0), COL_PANEL)
	_front.draw_string(font, Vector2(4.0, FONT_SIZE + 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_TEXT)
	_front.draw_set_transform(Vector2.ZERO)
