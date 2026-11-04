extends RefCounted
## Content sheets: one spreadsheet (CSV) per kind in content/, one row per
## data file. tools/import_content.gd turns rows into .tres files; this file
## holds the reading, checking and writing so tests can run it without a disk
## write. See docs/TOOLING.md, "Content sheets".
##
## Nothing here names a kind's fields. The columns are the exported fields of
## the kind's script, read from Godot's property list, so a new field on
## FishSpecies is a new column with no edit here, and its @export_range is
## the range the sheet is checked against.
##
## Cells:
## * numbers and text as typed; colours as html (8a8a8a); an enum or flags
##   field by its inspector names (Dry, or Dry;Nymph).
## * a link to another file by its id (pmd); a list of links as ids joined
##   with ";" (pmd;baetis).
## * a list of entries as key:number pairs: a DietEntry by insect id
##   (pmd:1;caddis:0.5), a HabitatEntry by water type (Pool:1;Tail Out:0.6).
## * a file that isn't content, like a fly's art, by its path
##   (res://assets/flies/parachute_adams.png).
## * an empty cell keeps what the file has, or the default for a new row.

const BUILD := preload("res://tools/build_catalog.gd")
const SHEET_DIR := "res://content"
## Import order: a sheet may only link to kinds listed before it.
const KINDS: Array[String] = ["insects", "flies", "rods", "fish"]
const LIST_SEP := ";"
const PAIR_SEP := ":"
const ID_RULE := "^[a-z0-9_]+$"


## What an import would do. Built by plan(), written by apply().
class Plan:
	var errors := PackedStringArray()
	## {path, res, new: bool, fields: PackedStringArray}, in KINDS order.
	var writes: Array[Dictionary] = []
	## Data files that a sheet has no row for. Never deleted, only reported.
	var unlisted := PackedStringArray()

	func in_sync() -> bool:
		return errors.is_empty() and writes.is_empty() and unlisted.is_empty()

	func summary() -> String:
		var lines := PackedStringArray()
		for w in writes:
			var what: String = "new" if w.new else ", ".join(w.fields)
			lines.append("  %s (%s)" % [w.path, what])
		for path in unlisted:
			lines.append("  %s has no row in its sheet (left as it is)" % path)
		return "\n".join(lines)


static func sheet_path(dir: String, kind: String) -> String:
	return dir.path_join(kind + ".csv")


static func file_for(kind: String, id: String) -> String:
	return String(BUILD.FOLDERS[kind]).path_join(id + ".tres")


## The data files of a kind in catalog order (the order the game shows them).
static func files(kind: String) -> Array[String]:
	var listed: Array[String] = BUILD.listed_paths(FileAccess.get_file_as_string(Catalog.PATH), kind)
	return BUILD.merge_order(listed, BUILD.files_in(BUILD.FOLDERS[kind]))


## The class name each catalog kind holds, from Catalog's typed lists.
static func kind_classes() -> Dictionary:
	var out := {}
	for p in Catalog.new().get_property_list():
		if p.type == TYPE_ARRAY and BUILD.FOLDERS.has(p.name):
			out[p.name] = _element_class(p)
	return out


static func kind_of_class(cls: String) -> String:
	var classes := kind_classes()
	for kind in classes:
		if classes[kind] == cls:
			return kind
	return ""


static func script_of(cls: String) -> Script:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == cls:
			return load(c["path"])
	return null


static func script_for(kind: String) -> Script:
	return script_of(kind_classes()[kind])


## A kind's columns: every saved, exported field of its script, in order.
static func columns(script: Script) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var need := PROPERTY_USAGE_SCRIPT_VARIABLE | PROPERTY_USAGE_STORAGE
	for p in script.new().get_property_list():
		if p.usage & need == need:
			out.append(p)
	return out


# ---- Export: data files -> sheets ------------------------------------------

## Writes every kind's sheet from today's data files. Overwrites the sheets.
static func export_sheets(dir: String) -> Error:
	DirAccess.make_dir_recursive_absolute(dir)
	for kind in KINDS:
		var cols := columns(script_for(kind))
		var f := FileAccess.open(sheet_path(dir, kind), FileAccess.WRITE)
		if f == null:
			return FileAccess.get_open_error()
		var header := PackedStringArray()
		for c in cols:
			header.append(c.name)
		f.store_csv_line(header)
		for path in files(kind):
			var res: Resource = load(path)
			var row := PackedStringArray()
			for c in cols:
				row.append(encode(res.get(c.name), c))
			f.store_csv_line(row)
	return OK


## A field's value as sheet text.
static func encode(value: Variant, prop: Dictionary) -> String:
	match prop.type:
		TYPE_COLOR:
			var c: Color = value
			return c.to_html(c.a < 1.0)
		TYPE_INT:
			if prop.hint == PROPERTY_HINT_ENUM:
				for pair in _names(prop):
					if pair[1] == value:
						return pair[0]
			if prop.hint == PROPERTY_HINT_FLAGS:
				var on := PackedStringArray()
				for pair in _names(prop):
					if int(value) & pair[1]:
						on.append(pair[0])
				return LIST_SEP.join(on)
			return str(value)
		TYPE_OBJECT:
			if value == null:
				return ""
			return String(value.get(&"id")) if &"id" in value else String(value.resource_path)
		TYPE_ARRAY:
			var items := PackedStringArray()
			for item in value:
				items.append(_encode_item(item))
			return LIST_SEP.join(items)
	return str(value)


static func _encode_item(item: Resource) -> String:
	if item == null:
		return ""
	if &"id" in item:
		return String(item.get(&"id"))
	var pair := _entry_fields(item.get_script())
	return "%s%s%s" % [encode(item.get(pair[0].name), pair[0]), PAIR_SEP, str(item.get(pair[1].name))]


# ---- Import: sheets -> data files ------------------------------------------

## Reads every sheet in `dir` and works out what an import would change,
## checking every cell. Writes nothing.
static func plan(dir: String) -> Plan:
	var p := Plan.new()
	var registry := {}  # kind -> {id: the resource that file will hold}
	for kind in KINDS:
		var path := sheet_path(dir, kind)
		if FileAccess.file_exists(path):
			_plan_sheet(kind, read_csv(path), path.get_file(), p, registry)
	return p


## Writes a plan's files, then rebuilds the catalog if any are new.
static func apply(p: Plan) -> Error:
	if not p.errors.is_empty():
		return ERR_INVALID_DATA
	var added := false
	for w in p.writes:  # paths first, so files link to each other, not embed
		w.res.take_over_path(w.path)
		added = added or w.new
	for w in p.writes:
		var err := ResourceSaver.save(w.res, w.path)
		if err != OK:
			printerr("Couldn't write %s (error %d)" % [w.path, err])
			return err
	return BUILD.build() if added else OK


static func read_csv(path: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var f := FileAccess.open(path, FileAccess.READ)
	while f != null and not f.eof_reached():
		var row := f.get_csv_line()
		if rows.is_empty() and row.size() > 0:
			row[0] = row[0].trim_prefix("﻿")  # spreadsheet apps add a BOM
		rows.append(row)
	return rows


static func _plan_sheet(kind: String, rows: Array[PackedStringArray], file: String,
		p: Plan, registry: Dictionary) -> void:
	var script := script_for(kind)
	var props := {}
	for c in columns(script):
		props[c.name] = c
	var header := PackedStringArray()
	for col in (rows[0] if not rows.is_empty() else PackedStringArray()):
		header.append(col.strip_edges())
	if not header.has("id"):
		p.errors.append("%s: no id column" % file)
		return
	for col in header:
		if not props.has(col):
			p.errors.append("%s: unknown column '%s' (the fields are %s)" % [file, col, ", ".join(props.keys())])
	if not p.errors.is_empty():
		return
	var ids := {}
	registry[kind] = ids
	for r in range(1, rows.size()):
		if "".join(rows[r]).strip_edges() == "":
			continue
		var cells := {}
		for i in header.size():
			cells[header[i]] = rows[r][i].strip_edges() if i < rows[r].size() else ""
		var id: String = cells["id"]
		var where := "%s row %d (%s)" % [file, r + 1, id]
		if not RegEx.create_from_string(ID_RULE).search(id):
			p.errors.append("%s: id must be lower case letters, digits and _" % where)
			continue
		if ids.has(id):
			p.errors.append("%s: id is used twice" % where)
			continue
		var path := file_for(kind, id)
		var original: Resource = load(path) if ResourceLoader.exists(path) else null
		var work: Resource = original.duplicate() if original else script.new()
		var fields := PackedStringArray()
		var before := p.errors.size()
		for col in header:
			if cells[col] == "":
				continue
			var errs := p.errors.size()
			var value: Variant = decode(cells[col], props[col], "%s, %s" % [where, col], p.errors, registry)
			if p.errors.size() == errs and encode(work.get(col), props[col]) != encode(value, props[col]):
				work.set(col, value)
				fields.append(col)
		ids[id] = original if original and fields.is_empty() else work
		if p.errors.size() == before and ids[id] == work:
			p.writes.append({path = path, res = work, new = original == null, fields = fields})
	for path in BUILD.files_in(BUILD.FOLDERS[kind]):
		if not ids.has(path.get_file().get_basename()):
			p.unlisted.append(path)


## Sheet text as a field's value. Appends to `errors` and returns null when
## the text doesn't fit the field.
static func decode(text: String, prop: Dictionary, where: String,
		errors: PackedStringArray, registry: Dictionary) -> Variant:
	match prop.type:
		TYPE_STRING_NAME:
			return StringName(text)
		TYPE_STRING:
			return text
		TYPE_BOOL:
			if text.to_lower() in ["true", "yes", "1"]:
				return true
			if text.to_lower() in ["false", "no", "0"]:
				return false
		TYPE_COLOR:
			if Color.html_is_valid(text):
				return Color.html(text)
			errors.append("%s: '%s' isn't an html colour like 8a8a8a" % [where, text])
			return null
		TYPE_INT:
			if prop.hint == PROPERTY_HINT_ENUM or prop.hint == PROPERTY_HINT_FLAGS:
				return _decode_names(text, prop, where, errors)
			if text.is_valid_int():
				return _in_range(text.to_int(), prop, where, errors)
		TYPE_FLOAT:
			if text.is_valid_float():
				return _in_range(text.to_float(), prop, where, errors)
		TYPE_OBJECT:
			return _resolve(_element_class(prop), text, where, errors, registry)
		TYPE_ARRAY:
			return _decode_list(text, prop, where, errors, registry)
	var wanted := {TYPE_INT: "a whole number", TYPE_FLOAT: "a number", TYPE_BOOL: "yes or no"}
	errors.append("%s: '%s' isn't %s" % [where, text, wanted.get(prop.type, type_string(prop.type))])
	return null


static func _decode_list(text: String, prop: Dictionary, where: String,
		errors: PackedStringArray, registry: Dictionary) -> Variant:
	var cls := _element_class(prop)
	var script := script_of(cls)
	var out := Array([], TYPE_OBJECT, &"Resource", script)
	var linked := kind_of_class(cls) != ""
	for part in text.split(LIST_SEP, false):
		part = part.strip_edges()
		if linked:
			out.append(_resolve(cls, part, where, errors, registry))
			continue
		var pair := _entry_fields(script)
		if pair.is_empty():
			errors.append("%s: can't fill a list of %s from a sheet" % [where, cls])
			return null
		var entry: Resource = script.new()
		var key := part.get_slice(PAIR_SEP, 0).strip_edges()
		entry.set(pair[0].name, _resolve(_element_class(pair[0]), key, where, errors, registry) \
			if pair[0].type == TYPE_OBJECT else decode(key, pair[0], where, errors, registry))
		if part.contains(PAIR_SEP):
			entry.set(pair[1].name, decode(part.get_slice(PAIR_SEP, 1).strip_edges(), pair[1], "%s, %s" % [where, pair[1].name], errors, registry))
		out.append(entry)
	return out


## The file with this id: one being imported in this run, or one on disk.
static func _resolve(cls: String, id: String, where: String,
		errors: PackedStringArray, registry: Dictionary) -> Resource:
	var kind := kind_of_class(cls)
	if kind == "" and id.begins_with("res://"):
		var file: Resource = load(id) if ResourceLoader.exists(id) else null
		if file != null and file.is_class(cls):
			return file
		errors.append("%s: no %s at '%s'" % [where, cls, id])
		return null
	if registry.has(kind) and registry[kind].has(id):
		return registry[kind][id]
	if kind != "" and RegEx.create_from_string(ID_RULE).search(id) and ResourceLoader.exists(file_for(kind, id)):
		return load(file_for(kind, id))
	var known := PackedStringArray()
	if kind != "":
		for path in BUILD.files_in(BUILD.FOLDERS[kind]):
			known.append(path.get_file().get_basename())
		if registry.has(kind):
			for k in registry[kind]:
				if not known.has(k):
					known.append(k)
	errors.append("%s: no %s '%s' (known: %s)" % [where, cls, id, ", ".join(known)])
	return null


static func _in_range(value: Variant, prop: Dictionary, where: String, errors: PackedStringArray) -> Variant:
	if prop.hint != PROPERTY_HINT_RANGE:
		return value
	var bounds := String(prop.hint_string).split(",")
	var lo := bounds[0].to_float()
	var hi := bounds[1].to_float()
	var open_hi: bool = prop.hint_string.contains("or_greater")
	var open_lo: bool = prop.hint_string.contains("or_less")
	if (value < lo and not open_lo) or (value > hi and not open_hi):
		errors.append("%s: %s is outside %s to %s" % [where, str(value), bounds[0], bounds[1]])
	return value


static func _decode_names(text: String, prop: Dictionary, where: String, errors: PackedStringArray) -> Variant:
	var total := 0
	var parts := text.split(LIST_SEP, false) if prop.hint == PROPERTY_HINT_FLAGS else PackedStringArray([text])
	for part in parts:
		var found := false
		for pair in _names(prop):
			if _same_name(pair[0], part):
				total |= pair[1]
				found = true
		if not found:
			var names := PackedStringArray()
			for pair in _names(prop):
				names.append(pair[0])
			errors.append("%s: '%s' isn't one of %s" % [where, part, ", ".join(names)])
	return total


## Names match ignoring case, spaces and underscores ("Tail Out" = tail_out).
static func _same_name(a: String, b: String) -> bool:
	return a.strip_edges().to_lower().replace(" ", "_") == b.strip_edges().to_lower().replace(" ", "_")


## An enum or flags field's [name, value] pairs, from its hint ("Dry:0,Nymph:1").
static func _names(prop: Dictionary) -> Array:
	var out := []
	var parts := String(prop.hint_string).split(",")
	for i in parts.size():
		var bits := parts[i].split(":")
		var fallback := (1 << i) if prop.hint == PROPERTY_HINT_FLAGS else i
		out.append([bits[0], bits[1].to_int() if bits.size() > 1 else fallback])
	return out


## The class a link or a typed list holds ("24/17:Insect" or "Insect").
static func _element_class(prop: Dictionary) -> String:
	return String(prop.hint_string).get_slice(":", String(prop.hint_string).count(":"))


## An entry resource's key field and number field: a link (DietEntry: insect,
## weight) or an enum (HabitatEntry: type, weight).
static func _entry_fields(script: Script) -> Array[Dictionary]:
	var link := {}
	var number := {}
	for c in columns(script):
		var is_key: bool = c.type == TYPE_OBJECT or (c.type == TYPE_INT and c.hint == PROPERTY_HINT_ENUM)
		if is_key and link.is_empty():
			link = c
		elif (c.type == TYPE_FLOAT or c.type == TYPE_INT) and number.is_empty():
			number = c
	if link.is_empty() or number.is_empty():
		return []
	return [link, number]
