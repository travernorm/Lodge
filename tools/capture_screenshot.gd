extends SceneTree
## Plays a scripted cast through the input system and saves screenshots along the
## way. Needs a display (use xvfb-run on a headless Linux box):
##   godot --path . --script res://tools/capture_screenshot.gd -- out_prefix
## Writes <out_prefix>-backcast.png, -forward.png and -landed.png at 3x scale.

var _main: Node
var _cast: Node
var _prefix := "user://shot"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_cast = _main.get_node(^"Cast")
	_run.call_deferred()


func _run() -> void:
	await _wait(0.3)
	var t: CastTuning = _cast.model.tuning
	# Back cast, forward cast, then two false casts to shoot more line.
	Input.action_press(&"cast_back")
	await _wait(_ideal())
	for i in 3:
		Input.action_press(&"cast_forward")
		await _wait(0.08)
		Input.action_release(&"cast_back")
		await _wait(_ideal() * (0.6 if i == 2 else 1.0))
		if i == 2:
			await _save("forward")
			await _wait(_ideal() * 0.4)
			break
		Input.action_press(&"cast_back")
		await _wait(0.08)
		Input.action_release(&"cast_forward")
		await _wait(_ideal() * 0.7)
		if i == 1:
			await _save("backcast")
		await _wait(_ideal() * 0.3)
	Input.action_release(&"cast_forward")
	await _wait(t.flight_time + 0.5)
	await _save("landed")
	quit(0)


func _ideal() -> float:
	return _cast.model.ideal_stroke_time()


func _wait(seconds: float) -> void:
	var until: float = _cast._time + seconds
	while _cast._time < until:
		await process_frame


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	var path := "%s-%s.png" % [_prefix, label]
	img.save_png(path)
	print("Saved ", path)
