extends SceneTree
## River sheets -> stretches (REQ-0014 step 1). Write a river in
## content/rivers.csv and content/river_markers.csv (any spreadsheet app, or a
## Google Sheet exported as CSV), then:
##   godot --headless --path . --script res://tools/import_river.gd
## Every row is checked first, and nothing is written if any is wrong. Each
## named section becomes data/stretches/<river>_<section>.tres, and a preview
## plate (a top-down map labelled by distance) goes to docs/rivers/.
##
##   ... import_river.gd -- --check    check the sheets, write nothing
##   ... import_river.gd -- --plates   write the plates only
## The sheet is the source of truth for a generated stretch: an import
## overwrites it, so move things in the sheet, not in the Inspector.

const Rivers := preload("res://tools/river_sheets.gd")
const Plate := preload("res://tools/river_plate.gd")
const BUILD := preload("res://tools/build_catalog.gd")
const PLATE_DIR := "res://docs/rivers"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var p := Rivers.plan()
	for e in p.errors:
		printerr(e)
	for n in p.notes:
		print(n)
	if not p.errors.is_empty():
		printerr("%d problem(s) in the river sheets. Nothing was written." % p.errors.size())
		quit(1)
		return
	for s in p.sections:
		var st: Stretch = s.stretch
		print("  %s: %s, %d to %d m, map %d x %d m, %d features" % [s.path, s.name, s.from, s.to,
			st.size_m.x, st.size_m.y, st.features.size()])
	if args.has("--check"):
		print("(--check: nothing written)")
		quit(0)
		return
	if not args.has("--plates"):
		var added := false
		for s in p.sections:
			added = added or not ResourceLoader.exists(s.path)
		if Rivers.apply(p) != OK:
			printerr("Couldn't write the stretches.")
			quit(1)
			return
		print("Wrote %d stretch(es)." % p.sections.size())
		if added and BUILD.build() != OK:
			quit(1)
			return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PLATE_DIR))
	for s in p.sections:
		var out := PLATE_DIR.path_join(s.path.get_file().get_basename() + ".png")
		Plate.draw(s).save_png(ProjectSettings.globalize_path(out))
		print("Wrote %s" % out)
	quit(0)
