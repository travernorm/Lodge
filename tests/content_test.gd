extends SceneTree
## Content sheets (tools/import_content.gd): the sheets in content/ agree with
## data/, an edit or a new row plans the right writes, and every kind of bad
## cell is caught before anything is written. Plans only, so data/ is never
## touched.
##   godot --headless --path . --script res://tests/content_test.gd

const Sheets := preload("res://tools/content_sheets.gd")
const TMP := "user://content_test"

var _failures := 0


func _initialize() -> void:
	_test_sheets_match_data()
	_test_round_trip()
	_test_edit_rewrites_one_field()
	_test_new_rows_link_each_other()
	_test_bad_cells()
	_test_missing_row_is_reported()
	_test_art_cells()
	_clean()
	if _failures == 0:
		print("Content tests passed.")
		quit(0)
	else:
		printerr("%d content test(s) failed." % _failures)
		quit(1)


func _test_sheets_match_data() -> void:
	var plan := Sheets.plan(Sheets.SHEET_DIR)
	var fix := "Run tools/import_content.gd after editing a sheet, or with -- --export after editing a .tres"
	_check(plan.errors.is_empty(), "the sheets in content/ have no bad cells %s" % [plan.errors])
	_check(plan.in_sync(), "the sheets and data/ agree" if plan.in_sync() else "the sheets and data/ disagree. %s.\n%s" % [fix, plan.summary()])
	for kind in Sheets.KINDS:
		var header := Sheets.read_csv(Sheets.sheet_path(Sheets.SHEET_DIR, kind))[0]
		var fields := PackedStringArray()
		for c in Sheets.columns(Sheets.script_for(kind)):
			fields.append(c.name)
		_check(header == fields, "%s.csv has a column for every field (%s). Run tools/import_content.gd -- --export" % [kind, ", ".join(fields)])


## Writing the sheets from data/ and reading them back changes nothing.
func _test_round_trip() -> void:
	_check(Sheets.export_sheets(TMP) == OK, "export writes a sheet per kind")
	var plan := Sheets.plan(TMP)
	_check(plan.in_sync(), "exported sheets plan no writes" if plan.in_sync() else "exported sheets plan writes\n%s %s" % [plan.summary(), plan.errors])


func _test_edit_rewrites_one_field() -> void:
	_sheets({"fish": [",4d574d,0.6,", ",4d574d,0.65,"]})
	var plan := Sheets.plan(TMP)
	_check(plan.errors.is_empty() and plan.writes.size() == 1, "one edited cell plans one write %s" % [plan.errors])
	if plan.writes.size() != 1:
		return
	var w: Dictionary = plan.writes[0]
	var fish: FishSpecies = w.res
	_check(w.path.ends_with("fish/redband.tres") and not w.new, "the write is the redband's file")
	_check(w.fields == PackedStringArray(["bite_chance"]) and is_equal_approx(fish.bite_chance, 0.65),
		"only bite_chance changes (%s)" % [w.fields])
	_check(fish.diet.size() == 3 and fish.diet[2].insect.id == &"caddis" and is_equal_approx(fish.diet[2].weight, 0.5),
		"the diet comes through whole")
	_check(is_equal_approx(load("res://data/fish/redband.tres").bite_chance, 0.6), "planning leaves the file alone")


func _test_new_rows_link_each_other() -> void:
	_sheets({}, {"insects": "test_hopper,Hopper,terrestrial",
		"flies": "test_daves,Dave's Hopper,\"Yellow, with a red tail.\",c9a36b,ffffff,8c6640,dry,test_hopper;caddis"})
	var plan := Sheets.plan(TMP)
	_check(plan.errors.is_empty() and plan.writes.size() == 2, "a new insect and a new fly plan two new files %s" % [plan.errors])
	if plan.writes.size() != 2:
		return
	var bug: Insect = plan.writes[0].res
	var fly: FlyPattern = plan.writes[1].res
	_check(plan.writes[0].new and plan.writes[0].path == "res://data/insects/test_hopper.tres", "insects are written first, to data/insects/")
	_check(plan.writes[1].path == "res://data/tackle/flies/test_daves.tres", "a new fly goes to the flies folder")
	_check(fly.imitates.size() == 2 and fly.imitates[0] == bug and fly.imitates[1].id == &"caddis",
		"the fly links to the new insect and to one on disk")
	_check(fly.description == "Yellow, with a red tail." and fly.fly_type == FlyPattern.Type.DRY,
		"quoted commas and lower-case enum names read")
	_check(fly.body_color.to_html(false) == "c9a36b" and fly.wing_color == Color.WHITE, "colours read from html")
	_check(not FileAccess.file_exists("res://data/tackle/flies/test_daves.tres"), "planning writes no file")


func _test_bad_cells() -> void:
	var cases := [
		["flies", "pmd;baetis;march_brown", "pmdd;baetis;march_brown", "no Insect 'pmdd'"],
		["fish", ",4d574d,0.6,", ",4d574d,1.5,", "1.5 is outside 0 to 1"],
		["fish", "pmd:1;baetis:1;caddis:0.5", "pmd:1;baetis:1;caddis:lots", "weight: 'lots' isn't a number"],
		["fish", "brook,Brook", "Brook Trout,Brook", "id must be lower case"],
		["fish", "cutthroat,Westslope", "brook,Westslope", "id is used twice"],
		["flies", ",8a8a8a,", ",grey,", "'grey' isn't an html colour"],
		["flies", ",Dry,caddis", ",Wet,caddis", "'Wet' isn't one of Dry, Nymph, Streamer"],
		["rods", "Dry;Nymph", "Dry;Wet", "'Wet' isn't one of Dry, Nymph, Streamer"],
		["rods", ",4,Dry,", ",4.5,Dry,", "'4.5' isn't a whole number"],
		["insects", "id,display_name,kind", "id,display_name,kinds", "unknown column 'kinds'"],
	]
	for c in cases:
		_sheets({c[0]: [c[1], c[2]]})
		var plan := Sheets.plan(TMP)
		var hit := false
		for e in plan.errors:
			hit = hit or e.contains(c[3])
		_check(hit, "%s.csv: %s %s" % [c[0], c[3], plan.errors])
		_check(Sheets.apply(plan) == ERR_INVALID_DATA, "  and nothing is written")


func _test_missing_row_is_reported() -> void:
	_sheets({"insects": ["pmd,PMD,mayfly\n", ""]})
	var plan := Sheets.plan(TMP)
	_check(plan.unlisted == PackedStringArray(["res://data/insects/pmd.tres"]) and plan.writes.is_empty(),
		"a file with no row is listed, not deleted (%s)" % [plan.unlisted])
	_check(not plan.in_sync(), "  and the sheets don't count as in sync")


## Copies today's sheets to TMP with one text swap per kind and rows added.
## A fly's art is a file path, not an id: a real texture links, anything else
## is a bad cell.
func _test_art_cells() -> void:
	var prop := {}
	for c in Sheets.columns(FlyPattern):
		if c.name == "sprite_sheet":
			prop = c
	_check(not prop.is_empty(), "flies.csv has a sprite_sheet column")
	if prop.is_empty():
		return
	var errors := PackedStringArray()
	var path := "res://assets/flies/parachute_adams.png"
	var art: Variant = Sheets.decode(path, prop, "art", errors, {})
	_check(art is Texture2D and errors.is_empty(), "a sprite_sheet cell links the texture at its path")
	_check(Sheets.encode(art, prop) == path, "and writes back as the same path")
	Sheets.decode("res://assets/flies/no_such_fly.png", prop, "art", errors, {})
	Sheets.decode("res://data/insects/pmd.tres", prop, "art", errors, {})
	_check(errors.size() == 2, "a missing file or one that isn't a texture is a bad cell %s" % [errors])


func _sheets(swaps: Dictionary, extra := {}) -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	for kind in Sheets.KINDS:
		var text := FileAccess.get_file_as_string(Sheets.sheet_path(Sheets.SHEET_DIR, kind))
		if swaps.has(kind):
			_check(text.contains(swaps[kind][0]), "fixture: %s.csv contains '%s'" % [kind, swaps[kind][0]])
			text = text.replace(swaps[kind][0], swaps[kind][1])
		if extra.has(kind):
			text += extra[kind] + "\n"
		FileAccess.open(Sheets.sheet_path(TMP, kind), FileAccess.WRITE).store_string(text)


func _clean() -> void:
	for f in DirAccess.get_files_at(TMP):
		DirAccess.remove_absolute(TMP.path_join(f))
	DirAccess.remove_absolute(TMP)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
