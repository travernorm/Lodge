extends SceneTree
## Records a sample of the demo stretch's river field (every STRIDE-th cell:
## velocity, depth, seam, lie) to tests/fixtures/demo_field.txt, so
## river_test can check a refactor leaves the water exactly as it was.
## Only re-record when a change to the water is intended, and say so in the PR.
##   godot --headless --path . --script res://tools/record_field_fixture.gd

const STRETCH := "res://data/stretches/demo_freestone.tres"
const OUT := "res://tests/fixtures/demo_field.txt"
const STRIDE := 6


func _initialize() -> void:
	var f := RiverField.new()
	f.build_stretch(load(STRETCH))
	var lines := PackedStringArray(["# i j vx vy depth seam lie  (demo stretch, every %d cells)" % STRIDE])
	for j in range(0, f.rows, STRIDE):
		for i in range(0, f.cols, STRIDE):
			var idx := j * f.cols + i
			var v := f.velocity[idx]
			lines.append("%d %d %.5f %.5f %.5f %.5f %.5f" % [i, j, v.x, v.y, f.depth[idx], f.seam[idx], f.lie[idx]])
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("Wrote %s (%d cells)" % [OUT, lines.size() - 1])
	quit(0)
