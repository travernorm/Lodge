class_name WeatherView
extends Node2D
## Paints the weather and the light over the river (REQ-0009, REQ-0015): a
## colour grade that follows the time of day, cloud shadows drifting with the
## wind, lightning in a storm, and rain or snow falling (its WeatherFallView
## child). It sits on the Weather canvas layer, above the river and below the
## debug overlay.
##
## The fishing node owns the day; main.tscn connects its conditions_changed
## here. A change of weather fades in over the look's fade_seconds, and a
## storm builds and passes over storm_fade_seconds. The view owns the sky
## (SkyLight: the time of day inside the slot, the cloud cover, how wet the
## ground is) and the lightning (LightningModel), and steps both.
##
## Debug key, R2 / F2: the next weather (Sunny, Overcast, light and heavy Rain,
## light and heavy Snow, Storm). The day really changes, so the hatch follows,
## but the fish stay. With the debug overlay open it moves the time of day on
## half a slot instead (the light only), and in a storm also strikes. Either
## way the corner shows what's on. In the debug overlay's Grass view the key
## belongs to the grass (REQ-0012).

## The debug key's next day. main.tscn connects it to the fishing node.
signal day_requested(c: Conditions)
## How much rain dimples the water (0 to 1). main.tscn connects it to the water.
signal rain_on_water(amount: float)
## How wet the ground is (0 to 1). main.tscn connects it to the bank.
signal ground_wet(amount: float)

const SHADER := preload("res://shaders/weather_grade.gdshader")
const FONT_SIZE := 8
const LABEL_SECONDS := 3.0
const COL_PANEL := Color(0, 0, 0, 0.55)
const COL_TEXT := Color("f4efe0")
## The wind's gusts lean the rain this much more and less, this often (s).
const GUST_SWING := 0.25
const GUST_SECONDS := 7.0
## The debug overlay's Grass view, where R2 / F2 steps the grass (GrassView.DEBUG_VIEW).
const GRASS_DEBUG_VIEW := 4

@export var look: WeatherLook:
	set(v):
		if look != null and look.changed.is_connected(_on_look_changed):
			look.changed.disconnect(_on_look_changed)
		look = v
		if look != null:
			look.changed.connect(_on_look_changed)
		_on_look_changed()
## For the debug key's next day.
@export var calendar: Calendar = preload("res://data/calendar.tres")
@export var climate: Climate = preload("res://data/climates/central_oregon.tres")
## Seeds where the rain falls, how the clouds come and go and when lightning strikes.
@export var fall_seed := 1

## The day on screen, and what it looks like right now (mid-fade included).
var conditions: Conditions
var mix := WeatherMix.new()
var sky: SkyLight
var lightning: LightningModel

var _from := WeatherMix.new()
var _fade := 1.0
var _fade_seconds := 0.0
var _debug_open := false
var _grass_view := false
var _label_until := -1.0
var _time := 0.0
var _wind_dir := Vector2.RIGHT
var _wind := 0.0
var _last_ripples := -1.0
var _last_wet := -1.0
var _mat := ShaderMaterial.new()
var _fall: WeatherFallView
var _grade: ColorRect
var _label: Node2D


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = fall_seed
	sky = SkyLight.new(rng)
	lightning = LightningModel.new(fall_seed)
	_mat.shader = SHADER
	_fall = WeatherFallView.new(fall_seed)
	add_child(_fall)
	_grade = ColorRect.new()
	_grade.material = _mat
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grade)
	_label = Node2D.new()
	_label.draw.connect(_draw_label)
	add_child(_label)
	_on_look_changed()
	if conditions != null:
		sky.begin(conditions.slot)
	_retarget(false)


## The day changed (a new visit, a new slot, or the debug key). A new slot or
## date starts the light at the beginning of the slot; a change of weather
## alone leaves the time of day where it was.
func show_conditions(c: Conditions) -> void:
	var old := conditions
	conditions = c
	var new_time := old == null or c == null or old.slot != c.slot or old.day != c.day or old.season != c.season
	if new_time and sky != null and c != null:
		sky.begin(c.slot)
	_fade_seconds = 0.0
	if old != null and c != null and look != null:
		_fade_seconds = look.fade_for(old.weather, c.weather)
	_retarget(old != null and is_inside_tree())


## The wind over the bank (main.tscn connects the grass's wind_blew here):
## it carries the clouds and leans the rain.
func set_wind(direction: Vector2, strength: float) -> void:
	_wind_dir = direction
	_wind = clampf(strength, 0.0, 1.0)


## The debug overlay's view changed; open = any view showing.
func set_debug_view(view: int) -> void:
	_debug_open = view != 0
	_grass_view = view == GRASS_DEBUG_VIEW
	if _label != null:
		_label.queue_redraw()


## Ends a fade at once (the screenshot tool, tests).
func settle() -> void:
	_fade = 1.0


## True while a change of weather is still fading in.
func is_fading() -> bool:
	return _fade < 1.0


func _unhandled_input(event: InputEvent) -> void:
	if _grass_view or not event.is_action_pressed(Controls.DEBUG_WEATHER):
		return
	get_viewport().set_input_as_handled()
	_label_until = _time + LABEL_SECONDS
	if _debug_open:
		sky.scrub(WeatherMix.SCRUB_SLOTS)
		if mix.flashes_per_minute > 0.0:
			lightning.strike(true)
	elif conditions != null:
		day_requested.emit(WeatherMix.next_debug_day(calendar, climate, conditions))


func _process(delta: float) -> void:
	_time += delta
	if _fade < 1.0:
		_fade = minf(_fade + delta / maxf(_fade_seconds, 0.01), 1.0)
	var cloud_mps := mix.cloud_speed_mps + (look.cloud_wind_mps * _wind if look != null else 0.0)
	sky.step(delta, mix.cloud_cover, cloud_mps, _wind_dir, mix.ripples > 0.0)
	mix = WeatherMix.blend(_from, WeatherMix.of(look, conditions, sky.day_time), _fade)
	lightning.step(delta, mix.flashes_per_minute)
	if not is_equal_approx(mix.ripples, _last_ripples):
		_last_ripples = mix.ripples
		rain_on_water.emit(mix.ripples)
	if absf(sky.wetness - _last_wet) >= 0.01 or (sky.wetness == 0.0) != (_last_wet == 0.0):
		_last_wet = sky.wetness
		ground_wet.emit(sky.wetness)
	_update_grade()
	_fall.mix = mix
	_fall.slant_deg = fall_slant()
	_fall.origin = get_viewport().get_canvas_transform().affine_inverse().origin
	_fall.step(delta)
	_label.queue_redraw()


## How far the rain or snow leans right now (degrees, + to the right): the
## weather's own lean plus the wind's, which comes and goes with the gusts,
## all toward where the wind is heading.
func fall_slant() -> float:
	var gust := 1.0 + GUST_SWING * sin(_time * TAU / GUST_SECONDS)
	var lean := mix.fall_slant_deg + (look.wind_slant_deg * _wind * gust if look != null else 0.0)
	return lean * (-1.0 if _wind_dir.x < 0.0 else 1.0)


func _on_look_changed() -> void:
	if sky != null and look != null:
		sky.slot_seconds = look.slot_minutes * 60.0
		lightning.strength = look.flash_strength
	if is_inside_tree() and sky != null:
		_retarget(false)


## Aims at the look for the current day, fading from what's showing or at once.
func _retarget(fade: bool) -> void:
	_from = mix
	_fade = 0.0 if fade and _fade_seconds > 0.0 else 1.0
	if sky != null:
		mix = WeatherMix.blend(_from, WeatherMix.of(look, conditions, sky.day_time), _fade)


func _update_grade() -> void:
	var size := get_viewport_rect().size
	_grade.size = size
	var px := WorldScale.PX_PER_M
	var origin := get_viewport().get_canvas_transform().affine_inverse().origin
	var cloud_m := look.cloud_size_m if look != null else 14.0
	for p in [[&"tint", mix.tint], [&"shadow_tint", mix.shadow_tint], [&"brightness", mix.brightness],
			[&"saturation", mix.saturation], [&"contrast", mix.contrast], [&"clouds", mix.clouds],
			[&"cover", sky.cover], [&"cloud_px", cloud_m * px], [&"world_origin", origin - sky.drift * px],
			[&"flash", lightning.flash], [&"flash_side", lightning.side], [&"afterglow", lightning.afterglow]]:
		_mat.set_shader_parameter(p[0], p[1])


func _draw_label() -> void:
	if conditions == null or not (_debug_open or _time < _label_until):
		return
	var font := ThemeDB.fallback_font
	var text := "R2/F2  %s  cloud %.2f" % [WeatherMix.describe(conditions, sky.day_time), sky.cover]
	var size := get_viewport_rect().size
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var at := Vector2(size.x - w - 4.0, size.y - 4.0)
	_label.draw_rect(Rect2(at - Vector2(2.0, FONT_SIZE + 1.0), Vector2(w + 4.0, FONT_SIZE + 4.0)), COL_PANEL)
	_label.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_TEXT)
