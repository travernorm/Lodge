class_name WeatherView
extends Node2D
## Paints the weather and the time of day over the river (REQ-0009): a colour
## grade over the whole picture, rain or snow falling, and in version C cloud
## shadows, lightning and (through the water view) rain dimples. It sits on the
## Weather canvas layer, above the river and below the debug overlay.
##
## The fishing node owns the day; main.tscn connects its conditions_changed
## here. A change of weather or slot fades in over the look's fade_seconds.
##
## Debug key, R2 / F2: the next weather (Sunny, Overcast, light and heavy Rain,
## light and heavy Snow, Storm). The day really changes, so the hatch follows,
## but the fish stay. With the debug overlay open it steps through the three
## versions (WeatherMix.Version) instead. Either way the corner shows what's on.

## The debug key's next day. main.tscn connects it to the fishing node.
signal day_requested(c: Conditions)
## How much rain dimples the water (0 to 1). main.tscn connects it to the water.
signal rain_on_water(amount: float)

const SHADER := preload("res://shaders/weather_grade.gdshader")
const FONT_SIZE := 8
const LABEL_SECONDS := 3.0
const COL_PANEL := Color(0, 0, 0, 0.55)
const COL_TEXT := Color("f4efe0")
## Cloud shadows: about how big one is, and how fast they drift.
const CLOUD_SIZE_M := 12.0
const CLOUD_DRIFT_MPS := Vector2(0.6, 0.25)
## How long a lightning flash takes to die away.
const FLASH_SECONDS := 0.3

@export var look: WeatherLook:
	set(v):
		if look != null and look.changed.is_connected(_on_look_changed):
			look.changed.disconnect(_on_look_changed)
		look = v
		if look != null:
			look.changed.connect(_on_look_changed)
		_on_look_changed()
## The version on trial. R2 / F2 with the debug overlay open steps through them.
@export var version := WeatherMix.Version.GRADE
## For the debug key's next day.
@export var calendar: Calendar = preload("res://data/calendar.tres")
@export var climate: Climate = preload("res://data/climates/central_oregon.tres")
## Seeds where the rain falls and when lightning strikes.
@export var fall_seed := 1

## The day on screen, and what it looks like right now (mid-fade included).
var conditions: Conditions
var mix := WeatherMix.new()

var _from := WeatherMix.new()
var _to := WeatherMix.new()
var _fade := 1.0
var _debug_open := false
var _label_until := -1.0
var _time := 0.0
var _flash := 0.0
var _next_flash := INF
var _last_ripples := -1.0
var _rng := RandomNumberGenerator.new()
var _mat := ShaderMaterial.new()
var _fall: Node2D
var _grade: ColorRect
var _label: Node2D
## Each drop or flake: where it is (screen px), its age and lifetime (s), and
## its sway phase.
var _pos := PackedVector2Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _phase := PackedFloat32Array()


func _ready() -> void:
	_rng.seed = fall_seed
	_mat.shader = SHADER
	_fall = Node2D.new()
	_fall.draw.connect(_draw_fall)
	add_child(_fall)
	_grade = ColorRect.new()
	_grade.material = _mat
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grade)
	_label = Node2D.new()
	_label.draw.connect(_draw_label)
	add_child(_label)
	_pos.resize(WeatherMix.MAX_FALL)
	_age.resize(WeatherMix.MAX_FALL)
	_life.resize(WeatherMix.MAX_FALL)
	_phase.resize(WeatherMix.MAX_FALL)
	for i in WeatherMix.MAX_FALL:
		_spawn(i)
		_age[i] = _rng.randf() * _life[i]
	_retarget(false)


## The day changed (a new visit, a new slot, or the debug key).
func show_conditions(c: Conditions) -> void:
	var first := conditions == null
	conditions = c
	_retarget(not first and is_inside_tree())


## The debug overlay's view changed; open = any view showing.
func set_debug_view(view: int) -> void:
	_debug_open = view != 0
	if _label != null:
		_label.queue_redraw()


## The version on trial, and the corner label for a few seconds.
func set_version(v: WeatherMix.Version) -> void:
	version = v
	_label_until = _time + LABEL_SECONDS
	_retarget(true)


## True while a change of weather is still fading in.
func is_fading() -> bool:
	return _fade < 1.0


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(Controls.DEBUG_WEATHER):
		return
	get_viewport().set_input_as_handled()
	if _debug_open:
		set_version(((version + 1) % WeatherMix.Version.size()) as WeatherMix.Version)
	elif conditions != null:
		_label_until = _time + LABEL_SECONDS
		day_requested.emit(WeatherMix.next_debug_day(calendar, climate, conditions))


func _process(delta: float) -> void:
	_time += delta
	if _fade < 1.0:
		_fade = minf(_fade + delta / maxf(look.fade_seconds if look != null else 0.0, 0.01), 1.0)
		mix = WeatherMix.blend(_from, _to, _fade)
	if not is_equal_approx(mix.ripples, _last_ripples):
		_last_ripples = mix.ripples
		rain_on_water.emit(mix.ripples)
	_update_flash(delta)
	_update_grade()
	_update_fall(delta)
	_fall.queue_redraw()
	_label.queue_redraw()


func _on_look_changed() -> void:
	if is_inside_tree():
		_retarget(false)


## Aims at the look for the current day and version, fading or at once.
func _retarget(fade: bool) -> void:
	_from = mix
	_to = WeatherMix.of(look, conditions, version)
	_fade = 0.0 if fade and look != null and look.fade_seconds > 0.0 else 1.0
	mix = WeatherMix.blend(_from, _to, _fade)


func _update_grade() -> void:
	var size := get_viewport_rect().size
	_grade.size = size
	var px := WorldScale.PX_PER_M
	var origin := get_viewport().get_canvas_transform().affine_inverse().origin
	for p in [[&"tint", mix.tint], [&"brightness", mix.brightness], [&"saturation", mix.saturation],
			[&"contrast", mix.contrast], [&"clouds", mix.clouds], [&"cloud_px", CLOUD_SIZE_M * px],
			[&"world_origin", origin + CLOUD_DRIFT_MPS * px * _time], [&"flash", _flash]]:
		_mat.set_shader_parameter(p[0], p[1])


## Lightning: a flash at random, about flashes_per_minute times a minute.
func _update_flash(delta: float) -> void:
	_flash = maxf(_flash - delta / FLASH_SECONDS, 0.0)
	if mix.flashes_per_minute <= 0.0:
		_next_flash = INF
		return
	var gap := 60.0 / mix.flashes_per_minute
	if _next_flash == INF:
		_next_flash = _time + _rng.randf_range(0.3, 1.0) * gap
	elif _time >= _next_flash:
		_flash = 0.7
		_next_flash = _time + _rng.randf_range(0.5, 1.5) * gap


func _update_fall(delta: float) -> void:
	var px := WorldScale.PX_PER_M
	var slant := deg_to_rad(mix.fall_slant_deg)
	var vel := Vector2(sin(slant), cos(slant)) * mix.fall_speed_mps * px
	var bounds := get_viewport_rect().grow(24.0)
	for i in WeatherMix.MAX_FALL:
		_pos[i] += vel * delta
		_age[i] += delta
		if _age[i] >= _life[i] or not bounds.has_point(_pos[i]):
			_spawn(i)


## A new drop somewhere on screen. Drops land all over, not only at the
## bottom: the view looks down on the river.
func _spawn(i: int) -> void:
	var size := get_viewport_rect().size
	_pos[i] = Vector2(_rng.randf_range(-16.0, size.x + 16.0), _rng.randf_range(-16.0, size.y))
	_age[i] = 0.0
	_life[i] = _rng.randf_range(0.4, 1.0) * (3.0 if mix.fall_length_m <= 0.0 else 1.0)
	_phase[i] = _rng.randf() * TAU


func _draw_fall() -> void:
	var n := mini(int(mix.fall_amount), WeatherMix.MAX_FALL)
	if n <= 0:
		return
	var px := WorldScale.PX_PER_M
	var slant := deg_to_rad(mix.fall_slant_deg)
	var streak := Vector2(sin(slant), cos(slant)) * mix.fall_length_m * px
	var sway := mix.fall_sway_m * px
	var tex := mix.fall_texture
	for i in n:
		var col := mix.fall_colour
		col.a *= clampf(minf(_age[i], _life[i] - _age[i]) / 0.15, 0.0, 1.0)
		var p := (_pos[i] + Vector2(sin(_time * 1.7 + _phase[i]) * sway, 0.0)).floor()
		if tex != null:
			_fall.draw_texture(tex, p - (tex.get_size() * 0.5).floor(), col)
		elif streak.length() >= 1.0:
			_fall.draw_line(p, p - streak.round(), col, 1.0)
		else:
			_fall.draw_rect(Rect2(p, Vector2.ONE), col)


func _draw_label() -> void:
	if conditions == null or not (_debug_open or _time < _label_until):
		return
	var font := ThemeDB.fallback_font
	var text := "R2/F2  " + WeatherMix.describe(conditions, version)
	var size := get_viewport_rect().size
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var at := Vector2(size.x - w - 4.0, size.y - 4.0)
	_label.draw_rect(Rect2(at - Vector2(2.0, FONT_SIZE + 1.0), Vector2(w + 4.0, FONT_SIZE + 4.0)), COL_PANEL)
	_label.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_TEXT)
