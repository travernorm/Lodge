extends SceneTree
## Writes data/catalog.tres from the data/<kind>/ folders (REQ-0004 C1).
## Run it after adding, moving or deleting a fish, fly, rod, insect or stretch file:
##   godot --headless --path . --script res://tools/build_catalog.gd
## tests/data_test.gd fails until you do, so a new file can't be forgotten.
##
## Entries keep their current order and new files go at the end (sorted by
## file name), so the fly box and rod order only change when you change them.

const FOLDERS := {
	"flies": "res://data/tackle/flies",
	"rods": "res://data/tackle/rods",
	"fish": "res://data/fish",
	"insects": "res://data/insects",
	"stretches": "res://data/stretches",
}


func _initialize() -> void:
	quit(0 if build() == OK else 1)


## Writes the catalog and prints what it lists. Also run by
## tools/import_content.gd after a sheet adds a file.
static func build() -> Error:
	var old := FileAccess.get_file_as_string(Catalog.PATH)
	var cat := Catalog.new()
	for field in FOLDERS:
		var ordered := merge_order(listed_paths(old, field), files_in(FOLDERS[field]))
		var list: Array = cat.get(field)
		for path in ordered:
			list.append(load(path))
		print("  %-9s %d" % [field, list.size()])
	var err := ResourceSaver.save(cat, Catalog.PATH)
	if err != OK:
		printerr("Couldn't write %s (error %d)" % [Catalog.PATH, err])
	else:
		print("Wrote %s" % Catalog.PATH)
	return err


## The paths one field of a catalog file lists, in order. Read from the text
## rather than loaded, because loading fails once a listed file is deleted.
static func listed_paths(text: String, field: String) -> Array[String]:
	var by_id := {}
	var ext := RegEx.create_from_string("^\\[ext_resource [^\\]]*path=\"([^\"]+)\" id=\"([^\"]+)\"")
	var ref := RegEx.create_from_string("ExtResource\\(\"([^\"]+)\"\\)")
	var out: Array[String] = []
	for line in text.split("\n"):
		var m := ext.search(line)
		if m != null:
			by_id[m.get_string(2)] = m.get_string(1)
		elif line.begins_with(field + " = "):
			var refs := ref.search_all(line)
			for i in range(1, refs.size()):  # the first is the array's script type
				out.append(by_id.get(refs[i].get_string(1), ""))
	return out


## The catalog's new order: what was listed before and still exists, in the
## same order, then any new files in `on_disk`'s order.
static func merge_order(before: Array[String], on_disk: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for path in before:
		if on_disk.has(path) and not out.has(path):
			out.append(path)
	for path in on_disk:
		if not out.has(path):
			out.append(path)
	return out


## Every .tres in a folder, sorted, as res:// paths.
static func files_in(dir: String) -> Array[String]:
	var out: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			out.append(dir.path_join(file))
	out.sort()
	return out
