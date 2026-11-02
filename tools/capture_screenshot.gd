extends SceneTree
## Plays a scripted cast, drift, hook set and fight through the input system and
## saves screenshots along the way. Needs a display (use xvfb-run on a headless
## Linux box):
##   godot --path . --script res://tools/capture_screenshot.gd -- out_prefix
## Writes <out_prefix>-backcast.png, -drift.png, -fight.png and -caught.png at 3x.

var _main: Node
var _cast: Node
var _fishing: Node
var _prefix := "user://shot"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_cast = _main.get_node(^"Cast")
	_fishing = _main.get_node(^"Fishing")
	_run.call_deferred()


func _run() -> void:
	await _wait(0.3)
	# Tie on a Royal Wulff and walk a little upstream.
	_fishing.fly_index = 2
	Input.action_press(&"move_left")
	await _wait(0.6)
	Input.action_release(&"move_left")

	# Back cast, forward cast, two false casts, deliver.
	Input.action_press(&"cast_back")
	await _wait(_ideal())
	for i in 3:
		Input.action_press(&"cast_forward")
		await _wait(0.08)
		Input.action_release(&"cast_back")
		await _wait(_ideal())
		if i == 2:
			break
		Input.action_press(&"cast_back")
		await _wait(0.08)
		Input.action_release(&"cast_forward")
		await _wait(_ideal() * 0.7)
		if i == 1:
			await _save("backcast")
		await _wait(_ideal() * 0.3)
	Input.action_release(&"cast_forward")
	await _wait(_cast.model.tuning.flight_time + 0.1)

	# Plant an eager brook trout just downstream of the fly.
	var brook: Fish = null
	for f in _fishing.fish:
		if f.species.id == &"brook":
			brook = f
	brook.species = brook.species.duplicate()
	brook.species.take_chance = 1.0
	brook.lie = _cast.fly_pos + Vector2(22, 1)
	brook.pos = brook.lie
	brook.state = Fish.State.HOLDING
	await _wait(0.35)
	await _save("drift")
	while brook.state != Fish.State.TAKEN:
		await process_frame
	await _wait(brook.species.set_min + 0.05)
	_stick(Vector2(0, -1))
	await _wait(0.05)

	var t0: float = _cast._time
	var saved_fight := false
	while _fishing.phase == 2:
		var fm: FightModel = _fishing.fight
		_stick(Vector2(-fm.run_dir * 0.4, -0.1) if fm.running else Vector2(0, -0.85))
		if not saved_fight and _cast._time - t0 > 1.2:
			saved_fight = true
			await _save("fight")
		await process_frame
	_stick(Vector2.ZERO)
	await _wait(0.5)
	await _save("caught")
	quit(0)


func _ideal() -> float:
	return _cast.model.ideal_stroke_time()


func _wait(seconds: float) -> void:
	var until: float = _cast._time + seconds
	while _cast._time < until:
		await process_frame


func _stick(v: Vector2) -> void:
	for a in [&"rod_left", &"rod_right", &"rod_up", &"rod_down"]:
		Input.action_release(a)
	if v.x < 0.0:
		Input.action_press(&"rod_left", -v.x)
	elif v.x > 0.0:
		Input.action_press(&"rod_right", v.x)
	if v.y < 0.0:
		Input.action_press(&"rod_up", -v.y)
	elif v.y > 0.0:
		Input.action_press(&"rod_down", v.y)


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	var path := "%s-%s.png" % [_prefix, label]
	img.save_png(path)
	print("Saved ", path)
