extends SceneTree
## Weather you can see (REQ-0009, REQ-0015): the grade, what falls and the
## water effects follow the look for each weather, slot and intensity; rain and
## snow fall in two depths under the drop cap; a change fades in; the debug
## key's days step round every weather on the same date; and in the real scene
## the key changes the day for the hatch but keeps the fish, moves the light
## with the debug overlay open, and the rain reaches the water and the bank.
##   godot --headless --path . --script res://tests/weather_view_test.gd

const LOOK := "res://data/weather_looks/default.tres"

var _failures := 0
var _calendar: Calendar = preload("res://data/calendar.tres")
var _climate: Climate = preload("res://data/climates/central_oregon.tres")
var _look: WeatherLook


func _initialize() -> void:
	_look = load(LOOK)
	_check(_look != null and _look.is_complete(), "the weather look loads and is complete")
	if _look == null:
		_finish()
		return
	_test_grade()
	_test_falling()
	_test_intensity()
	_test_blend()
	_test_debug_days()
	_run_scene.call_deferred()


func _day(w: Calendar.Weather, slot := Calendar.Slot.NOON, intensity := 0.0) -> Conditions:
	return Conditions.at(_calendar, _climate, Calendar.Season.SPRING, 10, slot, w, 60, false, intensity)


## The grade is the weather's style times the slot's, and night is darker.
func _test_grade() -> void:
	var m := WeatherMix.of(_look, _day(Calendar.Weather.OVERCAST))
	var s := _look.overcast
	var noon := Calendar.Slot.NOON
	_check(is_equal_approx(m.brightness, s.brightness * _look.slot_brightness[noon]), "overcast noon brightness follows the look")
	_check(is_equal_approx(m.saturation, s.saturation), "overcast saturation follows the look")
	var want := s.tint * _look.slot_tint[noon]
	want.a = 1.0
	_check(m.tint.is_equal_approx(want), "overcast noon tint is the style's times the slot's")
	var night := WeatherMix.of(_look, _day(Calendar.Weather.SUNNY, Calendar.Slot.NIGHT))
	var day := WeatherMix.of(_look, _day(Calendar.Weather.SUNNY))
	_check(night.brightness < day.brightness, "night is darker than noon (%.2f < %.2f)" % [night.brightness, day.brightness])
	var plain := WeatherMix.of(null, _day(Calendar.Weather.STORM, Calendar.Slot.NOON, 1.0))
	_check(plain.brightness == 1.0 and plain.fall_amount == 0.0 and plain.tint == Color.WHITE, "no look leaves the picture as drawn")


## Rain, dimples and lightning in a storm; nothing falls on a sunny day; the
## two depths share the sheet's drops and never pass the cap.
func _test_falling() -> void:
	var storm := WeatherMix.of(_look, _day(Calendar.Weather.STORM, Calendar.Slot.NOON, 1.0))
	_check(storm.fall_amount > 0.0 and storm.ripples > 0.0 and storm.flashes_per_minute > 0.0, "a storm has rain, dimples and lightning")
	_check(storm.fall_texture != null and storm.splash_texture != null, "storm rain is a sprite sheet with a splash")
	for w in Calendar.Weather.size():
		var m := WeatherMix.of(_look, _day(w as Calendar.Weather, Calendar.Slot.NOON, 1.0))
		_check(m.fall_amount <= WeatherMix.MAX_FALL, "%s stays under %d drops" % [Calendar.Weather.keys()[w], WeatherMix.MAX_FALL])
		if m.fall_texture != null:
			_check(m.fall_texture.get_width() % m.fall_variants == 0
				and m.fall_texture.get_height() == m.fall_texture.get_width() / m.fall_variants * m.fall_slant_rows,
				"%s: the sheet is %d square cells across and %d down" % [Calendar.Weather.keys()[w], m.fall_variants, m.fall_slant_rows])
	var sunny := WeatherMix.of(_look, _day(Calendar.Weather.SUNNY))
	_check(sunny.fall_amount == 0.0, "nothing falls on a sunny day")
	var near := 0
	var ok := true
	for i in WeatherMix.MAX_FALL:
		var v := WeatherFallView.variant(i, 4)
		if WeatherFallView.is_near(i):
			near += 1
			ok = ok and v >= 2 and v < 4
		else:
			ok = ok and v >= 0 and v < 2
	_check(ok, "the far layer draws the small drops, the near layer the large ones")
	_check(near > 0 and near < WeatherMix.MAX_FALL / 2, "most drops are in the far layer (%d near)" % near)
	_check(WeatherFallView.variant(5, 1) == 0, "a one-drop sheet works for both layers")
	_check(WeatherFallView.slant_row(0.0, 4) == 0 and WeatherFallView.slant_row(-25.0, 4) == 2
		and WeatherFallView.slant_row(80.0, 4) == 3 and WeatherFallView.slant_row(30.0, 1) == 0,
		"the rain sheet's row follows the lean")


## A drizzle shows less than a downpour.
func _test_intensity() -> void:
	var light := WeatherMix.of(_look, _day(Calendar.Weather.RAIN, Calendar.Slot.NOON, 0.2))
	var heavy := WeatherMix.of(_look, _day(Calendar.Weather.RAIN, Calendar.Slot.NOON, 1.0))
	_check(light.fall_amount < heavy.fall_amount, "light rain has fewer drops (%.0f < %.0f)" % [light.fall_amount, heavy.fall_amount])
	_check(light.ripples < heavy.ripples, "light rain dimples the water less")
	_check(light.brightness > heavy.brightness, "light rain is brighter than heavy rain")


## A change fades from one look to the next.
func _test_blend() -> void:
	var a := WeatherMix.of(_look, _day(Calendar.Weather.SUNNY))
	var b := WeatherMix.of(_look, _day(Calendar.Weather.STORM, Calendar.Slot.NOON, 1.0))
	var half := WeatherMix.blend(a, b, 0.5)
	_check(is_equal_approx(WeatherMix.blend(a, b, 0.0).brightness, a.brightness), "blend at 0 is the old look")
	_check(is_equal_approx(WeatherMix.blend(a, b, 1.0).brightness, b.brightness), "blend at 1 is the new look")
	_check(half.fall_amount > 0.0 and half.fall_amount < b.fall_amount, "the rain fades in")
	_check(is_equal_approx(half.fall_speed_mps, b.fall_speed_mps), "falling takes the new shape at once")
	var clearing := WeatherMix.blend(b, a, 0.5)
	_check(is_equal_approx(clearing.fall_speed_mps, b.fall_speed_mps), "clearing rain keeps its shape while it thins out")


## The debug key's days: same date and slot, every weather, back round.
func _test_debug_days() -> void:
	var start := _day(Calendar.Weather.SUNNY, Calendar.Slot.DUSK)
	var c := start
	var seen := {}
	for i in WeatherMix.DEBUG_STEPS.size():
		c = WeatherMix.next_debug_day(_calendar, _climate, c)
		seen[c.weather] = true
		_check(c.season == start.season and c.day == start.day and c.slot == start.slot,
			"debug day %d keeps the date and slot" % i)
		var step: Array = WeatherMix.DEBUG_STEPS[WeatherMix.debug_step(c)]
		_check(c.weather == step[0] and is_equal_approx(c.intensity, step[1]), "debug day %d is a step on the list" % i)
	_check(seen.size() == Calendar.Weather.size(), "the debug key reaches every weather")
	_check(c.weather == start.weather and c.intensity == start.intensity, "the debug key comes back round to the first weather")
	var spring := Conditions.at(_calendar, _climate, Calendar.Season.SUMMER, 5, Calendar.Slot.NOON, Calendar.Weather.SUNNY, 90, true)
	var next := WeatherMix.next_debug_day(_calendar, _climate, spring)
	_check(next.water_f >= Calendar.SPRING_FED_RANGE_F.x and next.water_f <= Calendar.SPRING_FED_RANGE_F.y,
		"spring-fed water stays spring fed (%ds)" % next.water_f)


## The real scene: the view gets the fishing node's day; F2 changes the day
## for the hatch and keeps the fish; with a debug view open it changes the
## version; the rain reaches the water.
func _run_scene() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	var fishing: Node = main.get_node_or_null(^"Fishing")
	var view := main.get_node_or_null(^"Weather/WeatherView") as WeatherView
	_check(view != null, "scene: Main has Weather/WeatherView")
	if view == null or fishing == null:
		_finish()
		return
	_check(view.look != null and view.look.resource_path == LOOK, "scene: the weather view uses %s" % LOOK)
	_check(view.conditions == fishing.conditions, "scene: the view shows the fishing node's day")
	var fish_before: Array = fishing.fish.duplicate()
	var before: Conditions = fishing.conditions
	await _press(main, &"debug_weather")
	_check(fishing.conditions != before and fishing.conditions.weather == WeatherMix.DEBUG_STEPS[(WeatherMix.debug_step(before) + 1) % WeatherMix.DEBUG_STEPS.size()][0],
		"scene: F2 moves the day to the next weather")
	_check(view.conditions == fishing.conditions and view.is_fading(), "scene: the view fades to the new day")
	var same: bool = fishing.fish.size() == fish_before.size()
	for i in fish_before.size():
		same = same and fishing.fish[i] == fish_before[i]
	_check(same, "scene: the fish stay when the weather changes")

	var rain := [-1.0]
	var wet := [-1.0]
	view.rain_on_water.connect(func(a: float): rain[0] = a)
	view.ground_wet.connect(func(a: float): wet[0] = a)
	view.set_debug_view(1)
	var w: Calendar.Weather = fishing.conditions.weather
	var time_before: float = view.sky.day_time
	await _press(main, &"debug_weather")
	_check(fishing.conditions.weather == w and absf(fposmod(view.sky.day_time - time_before, 6.0) - WeatherMix.SCRUB_SLOTS) < 0.05,
		"scene: with a debug view open, F2 moves the light on half a slot and keeps the weather")
	view.set_debug_view(0)
	fishing.set_conditions(_day(Calendar.Weather.RAIN, Calendar.Slot.DUSK, 1.0))
	_check(is_equal_approx(view.sky.day_time, float(Calendar.Slot.DUSK)), "scene: a new slot starts the light at the beginning of it")
	view.sky.scrub(0.25)
	fishing.set_conditions(_day(Calendar.Weather.STORM, Calendar.Slot.DUSK, 1.0))
	_check(is_equal_approx(view.sky.day_time, Calendar.Slot.DUSK + 0.25), "scene: a change of weather alone leaves the time of day")
	for i in 30:
		await process_frame
	_check(rain[0] > 0.0, "scene: the rain reaches the water (%.2f)" % rain[0])
	_check(wet[0] > 0.0, "scene: the rain wets the bank (%.2f)" % wet[0])
	var fall := view.get_child(0) as WeatherFallView
	_check(fall != null and fall.count() > 0 and fall.count() <= WeatherMix.MAX_FALL, "scene: rain is falling, under the cap")
	view.set_debug_view(1)
	await _press(main, &"debug_weather")
	_check(view.lightning.is_striking(), "scene: in a storm with a debug view open, F2 also strikes")
	view.set_debug_view(0)
	var grass := main.get_node_or_null(^"Grass")
	_check(grass != null and grass.wind_blew.is_connected(view.set_wind), "scene: the grass's wind reaches the weather view")
	main.queue_free()
	await process_frame
	_finish()


func _press(main: Node, action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	await process_frame
	var up := InputEventAction.new()
	up.action = action
	Input.parse_input_event(up)
	await process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", what)


func _finish() -> void:
	if _failures == 0:
		print("Weather view tests passed.")
		quit(0)
	else:
		printerr("%d weather view test(s) failed." % _failures)
		quit(1)
