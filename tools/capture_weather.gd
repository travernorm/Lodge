extends SceneTree
## Saves a screenshot of the game in a chosen weather and time of day
## (REQ-0015), for checking the light without waiting for it. Needs a display
## (use xvfb-run on a headless Linux box):
##   godot --path . --script res://tools/capture_weather.gd -- out.png [weather] [slot] [intensity] [flash] [wait=SECONDS] [at=X,Y]
## weather: sunny overcast rain snow storm. slot: dawn morning noon afternoon
## dusk night. `flash` catches a near lightning strike at its brightest.
## `wait` lets clouds drift and rain build first (default 3). `at` moves the
## angler (metres) to look at another part of the river. Saved at 3x.

const SCALE := 3


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://weather.png"
	var weather := Calendar.Weather.SUNNY
	var slot := Calendar.Slot.NOON
	var intensity := 1.0
	var flash := false
	var wait := 3.0
	var at := Vector2.INF
	for i in range(1, args.size()):
		var a := args[i].to_lower()
		if a == "flash":
			flash = true
		elif a.begins_with("wait="):
			wait = a.trim_prefix("wait=").to_float()
		elif a.begins_with("at="):
			var xy := a.trim_prefix("at=").split_floats(",")
			at = Vector2(xy[0], xy[1])
		elif Calendar.Weather.keys().has(a.to_upper()):
			weather = Calendar.Weather[a.to_upper()]
		elif Calendar.Slot.keys().has(a.to_upper()):
			slot = Calendar.Slot[a.to_upper()]
		elif a.is_valid_float():
			intensity = a.to_float()
	_run.call_deferred(out, weather, slot, intensity, flash, wait, at)


func _run(out: String, weather: Calendar.Weather, slot: Calendar.Slot, intensity: float, flash: bool, wait: float, at: Vector2) -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _wait(0.3)
	if at != Vector2.INF:
		main.angler_pos = WorldScale.vec_to_px(at)
	var fishing: Node = main.get_node(^"Fishing")
	var view: WeatherView = main.get_node(^"Weather/WeatherView")
	var old: Conditions = fishing.conditions
	fishing.set_conditions(Conditions.at(view.calendar, view.climate, old.season, old.day, slot, weather, 60, false, intensity))
	view.sky.scrub(0.5)  # the middle of the slot
	view.settle()
	if view.mix.ripples > 0.0:
		view.sky.wetness = 1.0
	await _wait(wait)
	if flash:
		view.lightning.strike(true)
		view.lightning.lengths[0] = 1.0  # hold the first flicker for the picture
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(img.get_width() * SCALE, img.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	img.save_png(out)
	print("Saved ", out)
	quit(0)


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await process_frame
		t += root.get_process_delta_time()
