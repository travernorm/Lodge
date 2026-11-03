extends SceneTree
## Content sheets -> data files. Edit content/<kind>.csv in any spreadsheet
## app (one row per insect, fly, rod or fish), then:
##   godot --headless --path . --script res://tools/import_content.gd
## Every cell is checked first, and nothing is written if any is wrong. Only
## files whose rows changed are rewritten, and the catalog is rebuilt when a
## row is new. Rows are never deleted from data/ by a missing row; the tool
## lists them instead.
##
##   ... import_content.gd -- --check    report what would change, write nothing
##   ... import_content.gd -- --export   rewrite the sheets from data/ (after
##                                       editing a .tres in the inspector)
## tests/content_test.gd fails while the sheets and data/ disagree.

const Sheets := preload("res://tools/content_sheets.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--export"):
		var err := Sheets.export_sheets(Sheets.SHEET_DIR)
		print("Wrote the sheets in %s" % Sheets.SHEET_DIR if err == OK else "Couldn't write the sheets (error %d)" % err)
		quit(0 if err == OK else 1)
		return
	var plan := Sheets.plan(Sheets.SHEET_DIR)
	for e in plan.errors:
		printerr(e)
	if not plan.errors.is_empty():
		printerr("%d problem(s) in the sheets. Nothing was written." % plan.errors.size())
		quit(1)
		return
	if plan.in_sync():
		print("The sheets and data/ already agree.")
		quit(0)
		return
	print(plan.summary())
	if args.has("--check"):
		print("(--check: nothing written)")
		quit(1)
		return
	var result := Sheets.apply(plan)
	print("Wrote %d file(s)." % plan.writes.size() if result == OK else "Import failed (error %d)." % result)
	quit(0 if result == OK else 1)
