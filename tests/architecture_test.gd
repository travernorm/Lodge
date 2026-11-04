extends SceneTree
## Architecture checks. Reads the source as text and fails when a change breaks
## a rule in docs/ARCHITECTURE.md. Every check names its rule (R1, R2 ...), so a
## failure points straight at the paragraph that explains it.
##   godot --headless --path . --script res://tests/architecture_test.gd
##
## THE DEBT LEDGER. Code that breaks a rule today is listed below with a cap.
## * A cap may only go DOWN. When a refactor pays debt back, lower the cap or
##   delete the entry in the same PR. The test prints a note when it can.
## * Raising a cap, or adding an entry, needs Traver's explicit OK in the PR,
##   and the PR's Architecture section says why.
## * ALLOWED entries are by design, not debt, and are explained in the doc.
## ARCHITECTURE.md section 9 mirrors this ledger in words.

const SCRIPT_ROOT := "res://scripts"
const DATA_ROOT := "res://data"
const DOC := "res://docs/ARCHITECTURE.md"
const DATA_TEST := "res://tests/data_test.gd"
const PROJECT := "res://project.godot"

## R9: a script past this many lines gets split along the layer lines.
const MAX_LINES := 400
## A note is printed when a capped file is this far under its cap.
const SLACK := 20

## R7: the only autoloads. Adding one is a decision for Traver (Clock and
## SaveGame are planned).
const AUTOLOADS := ["Controls"]

## R1: a script whose base class resolves to one of these is a model or data
## script (layers 1 and 2), and must stay pure.
const PURE_BASES := ["RefCounted", "Resource", "Object"]

## R1: what a pure script must never do. [label, regex]
const FORBIDDEN := [
	["tree access", "\\bget_(node|node_or_null|tree|parent|viewport)\\s*\\("],
	["input", "\\b(Input|Controls)\\."],
	["drawing", "\\b(draw_\\w+|queue_redraw)\\s*\\("],
	["node callback", "func\\s+_(ready|process|physics_process|draw|input|unhandled_input|enter_tree|exit_tree)\\s*\\("],
	["pixels", "to_px\\s*\\("],
	["wall clock", "\\b(Time|OS)\\."],
]

## R3: a node reaching into another node instead of being wired by its owner.
## Using groups (get_tree().get_first_node_in_group) for optional, read-only
## lookups like the debug overlay is fine and isn't counted.
const REACH := [
	"\\bget_parent\\s*\\(",                          # climbing to the parent
	"\\w\\.get_node(_or_null)?\\s*\\(",              # fetching another node's children
	"get_node(_or_null)?\\s*\\(\\s*\\^?\"\\.\\.",    # a path that climbs ("../")
	"\\.(get|set)\\s*\\(\\s*&\"",                    # untyped property access by name
]

## R8: randomness must come from a RandomNumberGenerator someone seeds and
## passes in, never a global roll or a fresh randomize().
const UNSEEDED := "(^|[^.\\w])(randi|randf|randf_range|randi_range|randfn|randomize)\\s*\\(|\\.randomize\\s*\\("

## R4: shared data is read-only at runtime. A text check for assigning to a
## field of a variable named like a data resource.
const DATA_WRITE := "\\b(species|sp|pattern|tuning|stretch|take_rules|insect|rod)\\.[a-z_]+\\s*[-+*/]?=(?!=)"

## R5: links between data files are typed resource references, not untyped
## Dictionary or Array exports full of ids.
const LOOSE_EXPORT := "@export.*\\bvar\\s+\\w+\\s*(:\\s*(Dictionary|Array)\\s*(=|$)|:=\\s*(\\{|\\[))"

## R5: content is found through the catalog (data/catalog.tres), never named
## in code, so a new file joins the game by itself (REQ-0004). Fish come from
## each stretch's spawn table.
const CONTENT_PATH := "res://data/(tackle/flies|tackle/rods|insects|fish)/"

# --- Ledger ---------------------------------------------------------------

## By design, not debt.
const ALLOWED_PURE := {
	"res://scripts/world_scale.gd": ["pixels"],  # it is the conversion
}
## R1 debt: pure scripts that still break a rule. [labels]
const DEBT_PURE := {}
## R3 debt: REACH matches per file. Step B (FishingSession) empties this.
const DEBT_REACH := {
	"res://scripts/fishing/fishing_controller.gd": 4,  # F2: get_parent, get_node("Cast"), .get(&"river"), .get(&"stretch")
	"res://scripts/casting/cast_controller.gd": 2,  # F2: get_parent, get_node("Fishing")
	"res://scripts/casting/cast_practice.gd": 3,  # F2: get_parent, get_node("Cast"), get_node("Fishing")
}
## R8 debt: unseeded randomness per file. Step G (one seeded RNG) empties this.
const DEBT_UNSEEDED := {
	"res://scripts/casting/cast_model.gd": 1,  # F9
}
## R5 debt: loosely typed data exports per file. Empty since REQ-0004 C2
## made the diet typed (DietEntry). Adding an entry needs Traver's OK.
const DEBT_LOOSE := {}
## R9 debt: line caps above MAX_LINES. Steps A and A2 bring them down.
const DEBT_LINES := {
	"res://scripts/fishing/fishing_controller.gd": 614,  # F1: step A (stocking moved to FishGenerator, REQ-0007)
	"res://scripts/river/river_field.gd": 623,  # F11: builder and query in one (603 after REQ-0004 C3)
	"res://scripts/stream_scene.gd": 451,  # F1: step A2 (angler drawing moved to AnglerView)
}

var _failures := 0
var _notes: Array[String] = []


func _initialize() -> void:
	var scripts := _scripts_under(SCRIPT_ROOT)
	_check(scripts.size() > 0, "found scripts under %s" % SCRIPT_ROOT)
	var sources := {}
	for path in scripts:
		sources[path] = _code_lines(path)
	var bases := _base_classes(sources)
	_test_pure_layers(sources, bases)
	_test_reach(sources, bases)
	_test_unseeded(sources)
	_test_data_writes(sources)
	_test_loose_exports(sources, bases)
	_test_content_from_catalog(sources)
	_test_sizes(scripts)
	_test_autoloads()
	_test_documented(scripts)
	_test_data_folders()
	_test_ledger_paths(scripts)
	for note in _notes:
		print("  note  ", note)
	if _failures == 0:
		print("Architecture tests passed.")
		quit(0)
	else:
		printerr("%d architecture check(s) failed. See docs/ARCHITECTURE.md for the rule each one cites." % _failures)
		quit(1)


# --- Checks ---------------------------------------------------------------

## R1: models and data never touch the tree, input, drawing, pixels or the clock.
func _test_pure_layers(sources: Dictionary, bases: Dictionary) -> void:
	for path in sources:
		if not _is_pure(path, bases):
			continue
		var allowed: Array = ALLOWED_PURE.get(path, []) + DEBT_PURE.get(path, [])
		var used := {}
		for rule in FORBIDDEN:
			var hits := _count(sources[path], rule[1])
			if hits > 0:
				used[rule[0]] = true
			if hits > 0 and not allowed.has(rule[0]):
				_check(false, "R1 %s: a model or data script must not use %s (%d place(s))" % [_short(path), rule[0], hits])
		for label in DEBT_PURE.get(path, []):
			if not used.has(label):
				_notes.append("R1 debt paid: remove \"%s\" for %s from DEBT_PURE" % [label, _short(path)])
	_check(true, "R1 models and data stay pure")


## R3: nodes don't climb the tree or reach into siblings.
func _test_reach(sources: Dictionary, bases: Dictionary) -> void:
	for path in sources:
		if _is_pure(path, bases):
			continue
		var hits := 0
		for pattern in REACH:
			hits += _count(sources[path], pattern)
		_ratchet("R3", path, hits, DEBT_REACH, "reach(es) into other nodes")
	_check(true, "R3 no new reaching into other nodes")


## R8: no unseeded randomness.
func _test_unseeded(sources: Dictionary) -> void:
	for path in sources:
		_ratchet("R8", path, _count(sources[path], UNSEEDED), DEBT_UNSEEDED, "unseeded random call(s)")
	_check(true, "R8 no new unseeded randomness")


## R4: nothing writes to shared data at runtime.
func _test_data_writes(sources: Dictionary) -> void:
	for path in sources:
		var hits := _count(sources[path], DATA_WRITE)
		_check(hits == 0, "R4 %s doesn't write to shared data (%d write(s))" % [_short(path), hits])


## R5: data classes link to each other with typed references.
func _test_loose_exports(sources: Dictionary, bases: Dictionary) -> void:
	for path in sources:
		if not _is_pure(path, bases):
			continue
		_ratchet("R5", path, _count(sources[path], LOOSE_EXPORT), DEBT_LOOSE, "untyped Dictionary/Array export(s)")
	_check(true, "R5 no new untyped data exports")


## R5: no script names a content file; it asks the catalog.
func _test_content_from_catalog(sources: Dictionary) -> void:
	for path in sources:
		var hits := _count(sources[path], CONTENT_PATH)
		_check(hits == 0, "R5 %s names %d content file(s); look them up in the Catalog instead" % [_short(path), hits])


## R9: scripts stay small enough to read in one sitting.
func _test_sizes(scripts: PackedStringArray) -> void:
	for path in scripts:
		var n := FileAccess.get_file_as_string(path).split("\n").size()
		var cap: int = DEBT_LINES.get(path, MAX_LINES)
		_check(n <= cap, "R9 %s is %d lines (cap %d)" % [_short(path), n, cap])
		if DEBT_LINES.has(path) and n <= MAX_LINES:
			_notes.append("R9 debt paid: %s is %d lines, remove it from DEBT_LINES" % [_short(path), n])
		elif DEBT_LINES.has(path) and n < cap - SLACK:
			_notes.append("R9 %s is %d lines: lower its DEBT_LINES cap to %d" % [_short(path), n, n + SLACK])


## R7: the autoload list is exactly the agreed one.
func _test_autoloads() -> void:
	var found: Array[String] = []
	var in_section := false
	for line in FileAccess.get_file_as_string(PROJECT).split("\n"):
		var t := line.strip_edges()
		if t.begins_with("["):
			in_section = t == "[autoload]"
			continue
		if in_section and "=" in t:
			found.append(t.get_slice("=", 0).strip_edges())
	for name in found:
		_check(AUTOLOADS.has(name), "R7 autoload %s is on the agreed list" % name)
	for name in AUTOLOADS:
		_check(found.has(name), "R7 autoload %s is registered in project.godot" % name)


## R10: every script is in the class index of ARCHITECTURE.md, so a new class
## can't arrive without a place on the map.
func _test_documented(scripts: PackedStringArray) -> void:
	var doc := FileAccess.get_file_as_string(DOC)
	_check(doc.length() > 0, "R10 %s is readable" % DOC)
	for path in scripts:
		_check(("`%s`" % path.trim_prefix("res://")) in doc, "R10 %s is listed in ARCHITECTURE.md's class index" % path.trim_prefix("res://"))


## R10: every data folder is on the map and covered by the data contract test.
func _test_data_folders() -> void:
	var doc := FileAccess.get_file_as_string(DOC)
	var contract := FileAccess.get_file_as_string(DATA_TEST)
	for dir in DirAccess.get_directories_at(DATA_ROOT):
		_check(("data/%s/" % dir) in doc, "R10 data/%s/ is described in ARCHITECTURE.md" % dir)
		_check(("%s/%s" % [DATA_ROOT, dir]) in contract, "R10 data/%s/ is loaded by tests/data_test.gd" % dir)


## The ledger itself: every entry points at a file that exists.
func _test_ledger_paths(scripts: PackedStringArray) -> void:
	for ledger in [ALLOWED_PURE, DEBT_PURE, DEBT_REACH, DEBT_UNSEEDED, DEBT_LOOSE, DEBT_LINES]:
		for path in ledger:
			if not scripts.has(path):
				_check(false, "ledger entry %s points at a script that no longer exists; delete it" % path)


# --- Helpers --------------------------------------------------------------

## A ledger check: no entry means a cap of 0. Over the cap fails; under it
## prints a note to lower the cap.
func _ratchet(rule: String, path: String, hits: int, ledger: Dictionary, what: String) -> void:
	var cap: int = ledger.get(path, 0)
	if hits > cap:
		_check(false, "%s %s has %d %s, cap %d. Fix it, or get Traver's OK to raise the cap" % [rule, _short(path), hits, what, cap])
	elif hits < cap:
		_notes.append("%s debt paid: %s has %d %s, lower its cap from %d" % [rule, _short(path), hits, what, cap])


## Every .gd file under a folder, recursively, as res:// paths.
func _scripts_under(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts_under(dir.path_join(sub)))
	return out


## The file's lines with comments removed, so prose about a rule doesn't trip it.
func _code_lines(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		out.append(_strip_comment(line))
	return out


func _strip_comment(line: String) -> String:
	var quote := ""
	for i in line.length():
		var c := line[i]
		if quote != "":
			if c == "\\":
				continue
			if c == quote and (i == 0 or line[i - 1] != "\\"):
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
	return line


## {path: [class_name or "", extends]} for every script.
func _base_classes(sources: Dictionary) -> Dictionary:
	var out := {}
	for path in sources:
		var name := ""
		var base := ""
		for line in sources[path]:
			var t: String = line.strip_edges()
			if t.begins_with("class_name "):
				name = t.trim_prefix("class_name ").get_slice(" ", 0).strip_edges()
			elif t.begins_with("extends "):
				base = t.trim_prefix("extends ").strip_edges()
			if name != "" and base != "":
				break
		out[path] = [name, base]
	return out


## True for a model or data script: its base classes end in a pure base.
func _is_pure(path: String, bases: Dictionary) -> bool:
	var by_name := {}
	for p in bases:
		if bases[p][0] != "":
			by_name[bases[p][0]] = bases[p][1]
	var base: String = bases[path][1]
	for _i in 10:
		if PURE_BASES.has(base):
			return true
		if not by_name.has(base):
			return false
		base = by_name[base]
	return false


func _count(lines: PackedStringArray, pattern: String) -> int:
	var re := RegEx.create_from_string(pattern)
	var n := 0
	for line in lines:
		n += re.search_all(line).size()
	return n


func _short(path: String) -> String:
	return path.trim_prefix("res://")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
