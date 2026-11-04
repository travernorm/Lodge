extends SceneTree
## Weather overlays (REQ-0009): the grade, what falls and the water effects
## follow the look for each weather, slot, intensity and version; a change
## fades in; the debug key's days step round every weather on the same date;
## and in the real scene the key changes the day for the hatch but keeps the
## fish.
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
	_test_versions()
	_test_intensity()
	_test_blend()
	_test_debug_days()
	_run_scene.call_deferred()


func _day(w: Calendar.Weather, slot := Calendar.Slot.NOON, intensity := 0.0) -> Conditions:
	return Conditions.at(_calendar, _climate, Calendar.Season.SPRING, 10, slot, w, 60, false, intensity)


## The grade is the weather's style times the slot's, and night is darker.
func _test_grade() -> void:
	var m := WeatherMix.of(_look, _day(Calendar.Weather.OVERCAST), WeatherMix.Version.GRADE)
	var s := _look.overcast
	var noon := Calendar.Slot.NOON
	_check(is_equal_approx(m.brightness, s.brightness * _look.slot_brightness[noon]), "overcast noon brightness follows the look")
	_check(is_equal_approx(m.saturation, s.saturation), "overcast saturation follows the look")
	var want := s.tint * _look.slot_tint[noon]
	want.a = 1.0
	_check(m.tint.is_equal_approx(want), "overcast noon tint is the style's times the slot's")
	var night := WeatherMix.of(_look, _day(Calendar.Weather.SUNNY, Calendar.Slot.NIGHT), WeatherMix.Version.GRADE)
	var day := WeatherMix.of(_look, _day(Calendar.Weather.SUNNY), WeatherMix.Version.GRADE)
	_check(night.brightness < day.brightness, "night is darker than noon (%.2f < %.2f)" % [night.brightness, day.brightness])
	var plain := WeatherMix.of(null, _day(Calendar.Weather.STORM, Calendar.Slot.NOON, 1.0), WeatherMix.Version.WATER)
	_check(plain.brightness == 1.0 and plain.fall_amount == 0.0 and plain.tint == Color.WHITE, "no look leaves the picture as drawn")


## A is the grade only, B adds falling, C adds the water and the sky.
func _test_versions() -> void:
	var storm := _day(Calendar.Weather.STORM, Calendar.Slot.NOON, 1.0)
	var a := WeatherMix.of(_look, storm, WeatherMix.Version.GRADE)
	var b := WeatherMix.of(_look, storm, WeatherMix.Version.FALLING)
	var c := WeatherMix.of(_look, storm, WeatherMix.Version.WATER)
	_check(a.fall_amount == 0.0 and a.ripples == 0.0 and a.flashes_per_minute == 0.0, "version A: grade only")
	_check(b.fall_amount > 0.0 and b.ripples == 0.0 and b.flashes_per_minute == 0.0, "version B: rain falls, the water is untouched")
	_check(c.fall_amount > 0.0 and c.ripples > 0.0 and c.flashes_per_minute > 0.0, "version C: rain, dimples and lightning")
	_check(a.brightness == b.brightness and b.brightness == c.brightness, "every version shares the grade")
	for w in Calendar.Weather.size():
		var m := WeatherMix.of(_look, _day(w as Calendar.Weather, Calendar.Slot.NOON, 1.0), WeatherMix.Version.WATER)
		_check(m.fall_amount <= WeatherMix.MAX_FALL, "%s stays under %d drops" % [Calendar.Weather.keys()[w], WeatherMix.MAX_FALL])
	var sunny := WeatherMix.of(_look, _day(Calendar.Weather.SUNNY), WeatherMix.Version.WATER)
	_check(sunny.fall_amount == 0.0, "nothing falls on a sunny day")


## A drizzle shows less than a downpour.
func _test_intensity() -> void:
	var light := WeatherMix.of(_look, _day(Calendar.Weather.RAIN, Calendar.Slot.NOON, 0.2), WeatherMix.Version.WATER)
	var heavy := WeatherMix.of(_look, _day(Calendar.Weather.RAIN, Calendar.Slot.NOON, 1.0), WeatherMix.Version.WATER)
	_check(light.fall_amount < heavy.fall_amount, "light rain has fewer drops (%.0f < %.0f)" % [light.fall_amount, heavy.fall_amount])
	_check(light.ripples < heavy.ripples, "light rain dimples the water less")
	_check(light.brightness > heavy.brightness, "light rain is brighter than heavy rain")


## A change fades from one look to the next.
func _test_blend() -> void:
	var a := WeatherMix.of(_look, _day(Calendar.Weather.SUNNY), WeatherMix.Version.WATER)
	var b := WeatherMix.of(_look, _day(Calendar.Weather.STORM, Calendar.Slot.NOON, 1.0), WeatherMix.Version.WATER)
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
	view.rain_on_water.connect(func(a: float): rain[0] = a)
	view.set_debug_view(1)
	var w: Calendar.Weather = fishing.conditions.weather
	await _press(main, &"debug_weather")
	await _press(main, &"debug_weather")
	_check(view.version == WeatherMix.Version.WATER and fishing.conditions.weather == w,
		"scene: with a debug view open, F2 steps the version and keeps the weather")
	view.set_debug_view(0)
	fishing.set_conditions(_day(Calendar.Weather.RAIN, Calendar.Slot.NOON, 1.0))
	view.set_version(WeatherMix.Version.WATER)
	for i in 3:
		await process_frame
	_check(rain[0] > 0.0, "scene: version C rain reaches the water (%.2f)" % rain[0])
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
