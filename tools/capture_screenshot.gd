extends SceneTree
## Renders the main scene for a few seconds with scripted bumper presses and saves
## a PNG. Needs a display (use xvfb-run on a headless Linux box):
##   godot --path . --script res://tools/capture_screenshot.gd -- out.png

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://screenshot.png"
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_capture.call_deferred(out)


func _capture(out: String) -> void:
	# A fake back cast / forward cast rhythm so the debug timeline has something on it.
	var script := [["cast_back", true, 30], ["cast_forward", true, 6], ["cast_back", false, 20],
		["cast_forward", false, 15], ["cast_back", true, 25]]
	for step in script:
		if step[1]:
			Input.action_press(step[0])
		else:
			Input.action_release(step[0])
		for i in step[2]:
			await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	img.save_png(out)
	print("Saved ", out)
	quit(0)
