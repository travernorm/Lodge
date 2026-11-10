extends SceneTree
## Headless tests for the sky over a visit (REQ-0015): the light blends from
## one slot's key to the next as the day moves, a visit drifts through its
## slot and holds, the cloud cover wanders the same way for the same seed,
## clouds travel with the wind, and the ground wets in rain and dries after.
##   godot --headless --path . --script res://tests/sky_light_test.gd

const LOOK := "res://data/weather_looks/default.tres"

var _failures := 0
var _calendar: Calendar = preload("res://data/calendar.tres")
var _climate: Climate = preload("res://data/climates/central_oregon.tres")
var _look: WeatherLook


func _initialize() -> void:
	_look = load(LOOK)
	_test_keys()
	_test_light_blends()
	_test_visit_drifts_and_holds()
	_test_cover_seeded()
	_test_clouds_travel()
	_test_wetness()
	_test_storms()
	if _failures == 0:
		print("Sky light tests passed.")
		quit(0)
	else:
		printerr("%d sky light test(s) failed." % _failures)
		quit(1)


func _day(w: Calendar.Weather, slot := Calendar.Slot.NOON, intensity := 0.0) -> Conditions:
	return Conditions.at(_calendar, _climate, Calendar.Season.SPRING, 10, slot, w, 60, false, intensity)


func _sky(p_seed: int) -> SkyLight:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	return SkyLight.new(rng)


func _test_keys() -> void:
	var mid := SkyLight.keys_at(Calendar.Slot.DUSK + 0.5)
	_check(mid[0] == Calendar.Slot.DUSK and is_zero_approx(mid[2]), "keys: the middle of Dusk is Dusk's key alone")
	var edge := SkyLight.keys_at(float(Calendar.Slot.DUSK))
	_check(edge[0] == Calendar.Slot.AFTERNOON and edge[1] == Calendar.Slot.DUSK and is_equal_approx(edge[2], 0.5),
		"keys: the start of Dusk is half Afternoon, half Dusk")
	var wrap := SkyLight.keys_at(0.0)
	_check(wrap[0] == Calendar.Slot.NIGHT and wrap[1] == Calendar.Slot.DAWN and is_equal_approx(wrap[2], 0.5),
		"keys: the start of Dawn is half Night, half Dawn")
	var late := SkyLight.keys_at(Calendar.Slot.NIGHT + 0.75)
	_check(late[0] == Calendar.Slot.NIGHT and late[1] == Calendar.Slot.DAWN, "keys: late Night heads for Dawn")


## Acceptance: at a slot's midpoint the light is that slot's key; halfway
## between two slots it is their even blend.
func _test_light_blends() -> void:
	var dusk := Calendar.Slot.DUSK
	var c := _day(Calendar.Weather.SUNNY, dusk)
	var s := _look.sunny
	var mid := WeatherMix.of(_look, c, dusk + 0.5)
	var want := s.tint * _look.slot_tint[dusk]
	want.a = 1.0
	_check(mid.tint.is_equal_approx(want), "light: mid-Dusk highlights are Dusk's key")
	var want_shadow := s.tint * _look.slot_shadow_tint[dusk]
	want_shadow.a = 1.0
	_check(mid.shadow_tint.is_equal_approx(want_shadow), "light: mid-Dusk shadows are Dusk's key")
	_check(WeatherMix.of(_look, c).tint.is_equal_approx(mid.tint), "light: with no time given, the day's own slot at its middle")
	var edge := WeatherMix.of(_look, c, dusk + 1.0)
	var night := Calendar.Slot.NIGHT
	var even := s.tint * _look.slot_tint[dusk].lerp(_look.slot_tint[night], 0.5)
	even.a = 1.0
	_check(edge.tint.is_equal_approx(even), "light: the end of Dusk is the even blend of Dusk and Night")
	_check(is_equal_approx(edge.brightness, s.brightness * lerpf(_look.slot_brightness[dusk], _look.slot_brightness[night], 0.5)),
		"light: brightness blends the same way")
	_check(mid.brightness > edge.brightness, "light: Dusk darkens toward Night (%.2f > %.2f)" % [mid.brightness, edge.brightness])
	for slot in Calendar.Slot.size():
		var m := WeatherMix.of(_look, _day(Calendar.Weather.SUNNY, slot as Calendar.Slot))
		_check(m.shadow_tint.b >= m.shadow_tint.r, "light: %s shadows are no warmer than neutral" % Calendar.Slot.keys()[slot])


## A visit starts at the beginning of its slot, reaches the end after
## slot_seconds and holds there.
func _test_visit_drifts_and_holds() -> void:
	var sky := _sky(1)
	sky.slot_seconds = 600.0
	sky.begin(Calendar.Slot.AFTERNOON)
	_check(is_equal_approx(sky.day_time, float(Calendar.Slot.AFTERNOON)), "visit: starts at the beginning of its slot")
	for i in 300:
		sky.step(1.0, 0.4, 0.5, Vector2.RIGHT, false)
	_check(absf(sky.day_time - (Calendar.Slot.AFTERNOON + 0.5)) < 0.01, "visit: half way through after half the time (%.2f)" % sky.day_time)
	for i in 900:
		sky.step(1.0, 0.4, 0.5, Vector2.RIGHT, false)
	_check(sky.day_time < Calendar.Slot.AFTERNOON + 1.0 and sky.day_time > Calendar.Slot.AFTERNOON + 0.99,
		"visit: holds at the end of the slot (%.3f)" % sky.day_time)
	sky.scrub(0.5)
	_check(int(floorf(sky.day_time)) == Calendar.Slot.DUSK, "visit: the scrub moves on into the next slot")
	sky.scrub(float(Calendar.Slot.size()))
	_check(sky.day_time >= 0.0 and sky.day_time < Calendar.Slot.size(), "visit: the scrub wraps round the day")
	var still := _sky(1)
	still.slot_seconds = 0.0
	still.begin(Calendar.Slot.NOON)
	still.step(100.0, 0.4, 0.5, Vector2.RIGHT, false)
	_check(is_equal_approx(still.day_time, Calendar.Slot.NOON + 0.5), "visit: slot_seconds 0 holds the light at mid-slot")


## Acceptance: the same seed gives the same cover over time. A broken sky
## comes and goes; a clear or a solid one hardly moves.
func _test_cover_seeded() -> void:
	var a := _sky(7)
	var b := _sky(7)
	var c := _sky(8)
	var same := true
	var differs := false
	var low := 1.0
	var high := 0.0
	for i in 240:
		a.step(1.0, 0.4, 0.5, Vector2.RIGHT, false)
		b.step(1.0, 0.4, 0.5, Vector2.RIGHT, false)
		c.step(1.0, 0.4, 0.5, Vector2.RIGHT, false)
		same = same and a.cover == b.cover
		differs = differs or not is_equal_approx(a.cover, c.cover)
		low = minf(low, a.cover)
		high = maxf(high, a.cover)
	_check(same, "cover: the same seed gives the same sky")
	_check(differs, "cover: another seed gives another sky")
	_check(high - low > 0.15, "cover: a broken sky comes and goes (%.2f to %.2f)" % [low, high])
	_check(low >= 0.0 and high <= 1.0, "cover: stays between clear and solid")
	var solid := _sky(7)
	_check(is_equal_approx(solid.cover_at(1.0, 30.0), 1.0) and is_equal_approx(solid.cover_at(0.0, 30.0), 0.0),
		"cover: a solid sky stays solid and a clear one clear")


func _test_clouds_travel() -> void:
	var sky := _sky(1)
	sky.step(10.0, 0.4, 0.6, Vector2.LEFT, false)
	_check(sky.drift.is_equal_approx(Vector2(-6.0, 0.0)), "clouds: drift downwind at their speed (%s)" % sky.drift)
	var sunny := WeatherMix.of(_look, _day(Calendar.Weather.SUNNY))
	var overcast := WeatherMix.of(_look, _day(Calendar.Weather.OVERCAST))
	var storm := WeatherMix.of(_look, _day(Calendar.Weather.STORM, Calendar.Slot.NOON, 1.0))
	_check(sunny.cloud_cover > 0.15 and sunny.cloud_cover < 0.6, "clouds: a sunny day has broken cloud (%.2f)" % sunny.cloud_cover)
	_check(overcast.cloud_cover > 0.85, "clouds: overcast is nearly solid (%.2f)" % overcast.cloud_cover)
	_check(sunny.clouds > overcast.clouds, "clouds: sunny shadows are crisper than overcast ones")
	_check(storm.cloud_speed_mps > sunny.cloud_speed_mps, "clouds: storm clouds travel faster")


func _test_wetness() -> void:
	var sky := _sky(1)
	sky.step(SkyLight.WET_SECONDS * 0.5, 1.0, 0.5, Vector2.RIGHT, true)
	_check(is_equal_approx(sky.wetness, 0.5), "wet: the ground wets while it rains (%.2f)" % sky.wetness)
	sky.step(SkyLight.WET_SECONDS, 1.0, 0.5, Vector2.RIGHT, true)
	_check(is_equal_approx(sky.wetness, 1.0), "wet: and stops at soaked")
	sky.step(SkyLight.DRY_SECONDS * 0.5, 0.4, 0.5, Vector2.RIGHT, false)
	_check(is_equal_approx(sky.wetness, 0.5), "wet: it dries more slowly afterwards (%.2f)" % sky.wetness)


## Acceptance: a storm's darkness and strike rate rise with intensity; Sunny
## and Overcast never strike; a storm builds and passes slowly.
func _test_storms() -> void:
	var light := WeatherMix.of(_look, _day(Calendar.Weather.STORM, Calendar.Slot.NOON, 0.1))
	var heavy := WeatherMix.of(_look, _day(Calendar.Weather.STORM, Calendar.Slot.NOON, 1.0))
	_check(heavy.flashes_per_minute > light.flashes_per_minute and light.flashes_per_minute > 0.0,
		"storm: a harder storm strikes more often (%.1f > %.1f)" % [heavy.flashes_per_minute, light.flashes_per_minute])
	_check(heavy.brightness < light.brightness, "storm: and is darker")
	for w in [Calendar.Weather.SUNNY, Calendar.Weather.OVERCAST, Calendar.Weather.RAIN, Calendar.Weather.SNOW]:
		_check(WeatherMix.of(_look, _day(w, Calendar.Slot.NOON, 1.0)).flashes_per_minute == 0.0,
			"storm: %s never strikes" % Calendar.Weather.keys()[w])
	var storm := Calendar.Weather.STORM
	_check(_look.fade_for(Calendar.Weather.SUNNY, storm) == _look.storm_fade_seconds
		and _look.fade_for(storm, Calendar.Weather.RAIN) == _look.storm_fade_seconds,
		"storm: builds and passes over storm_fade_seconds")
	_check(_look.fade_for(Calendar.Weather.SUNNY, Calendar.Weather.RAIN) == _look.fade_seconds,
		"storm: other changes fade over fade_seconds")
	var sunny := WeatherMix.of(_look, _day(Calendar.Weather.SUNNY))
	_check(WeatherMix.blend(sunny, heavy, 0.3).flashes_per_minute < heavy.flashes_per_minute * 0.3,
		"storm: lightning holds off while the storm builds")


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", what)
