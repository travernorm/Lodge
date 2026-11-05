extends RefCounted
## River sheets (REQ-0014 step 1): a river written as distance markers, turned
## into one Stretch per named section. tools/import_river.gd runs it; this
## file holds the reading, checking and building so tests can run it without
## writing to disk. See docs/TOOLING.md, "River sheets".
##
## content/rivers.csv: one row per river.
##   id, name, width_m, start_heading_deg (0 flows right, 90 flows down the
##   screen), fish_per_100m, spring_fed (yes/no), spawn (redband:0.6;brook:0.2),
##   hatches_like (a stretch id whose hatch table this river shares),
##   grass_bank_m (tall grass this far back from the water), notes.
## content/river_markers.csv: one row per thing along a river.
##   river, at_m (metres downstream from the river's top), length_m (for things
##   that run along the river), kind, side (left, right or mid, facing
##   downstream), offset_m, size_m, value, note.
##
## Built kinds (KINDS): section, end, bend, water, boulder, log, eddy,
## gravel_bar, grass, angler_start. Planned kinds (PLANNED) are drawn on the
## preview plate and reported, and are built by REQ-0014 step 3.

const Sheets := preload("res://tools/content_sheets.gd")
const SHEET_DIR := "res://content"
const OUT_DIR := "res://data/stretches"
const RIVERS := "rivers.csv"
const MARKERS := "river_markers.csv"

const KINDS := ["section", "end", "bend", "water", "boulder", "log", "eddy", "gravel_bar", "grass", "angler_start"]
const PLANNED := ["waterfall", "bridge", "cabin", "ford", "trail", "inflow", "boat_launch", "width", "reach_break"]
const SIDES := ["left", "right", "mid"]
## Thalweg depth (0..1) for each kind of water.
const WATER_DEPTH := {"riffle": 0.3, "run": 0.5, "pocket": 0.45, "pool": 0.95, "tail_out": 0.35, "plunge": 1.0}
const BASE_DEPTH := 0.45
## Land kept around the river on every side of a section's map (m).
const BANK_ROOM := 16.0
## How far the river runs straight off the map past each end of a section (m).
const LEAD := 60.0
## Spacing of the centreline points written to the stretch (m).
const POINT_STEP := 10.0
const STEP := 1.0  # metres per step when tracing the river


## A river as read from its sheets.
class River:
	var id := ""
	var name := ""
	var width_m := 16.0
	var heading := 0.0  # degrees
	var fish_per_100m := 2.7
	var spring_fed := false
	var spawn := ""
	var hatches_like := ""
	var grass_bank_m := 0.0
	var markers: Array[Dictionary] = []  # {row, at, length, kind, side, offset, size, value, note}
	var length_m := 0.0

	## Heading (radians, screen y down) at every STEP of the river, 0..length.
	var headings := PackedFloat32Array()
	var points := PackedVector2Array()

	func point_at(s: float) -> Vector2:
		if s <= 0.0:
			return points[0] + _dir(headings[0]) * s
		var last := points.size() - 1
		if s >= last * STEP:
			return points[last] + _dir(headings[last]) * (s - last * STEP)
		var i := floori(s / STEP)
		return points[i].lerp(points[i + 1], s / STEP - i)

	func dir_at(s: float) -> Vector2:
		return _dir(headings[clampi(roundi(s / STEP), 0, headings.size() - 1)])

	## River left, facing downstream.
	func left_at(s: float) -> Vector2:
		var d := dir_at(s)
		return Vector2(d.y, -d.x)

	static func _dir(h: float) -> Vector2:
		return Vector2(cos(h), sin(h))


## What an import would do. Built by plan(), written by apply().
class Plan:
	var errors := PackedStringArray()
	var notes := PackedStringArray()  # planned kinds, not built yet
	var rivers: Array = []  # of River
	## {path, stretch: Stretch, river: River, from, to, name}
	var sections: Array[Dictionary] = []


static func plan(dir := SHEET_DIR) -> Plan:
	var p := Plan.new()
	var rivers := _read_rivers(dir.path_join(RIVERS), p)
	_read_markers(dir.path_join(MARKERS), rivers, p)
	for r: River in rivers.values():
		_trace(r, p)
		p.rivers.append(r)
	if p.errors.is_empty():
		for r: River in p.rivers:
			_plan_sections(r, p)
	return p


## Writes every section's stretch. The plan must have no errors.
static func apply(p: Plan) -> Error:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for s in p.sections:
		var err := ResourceSaver.save(s.stretch, s.path)
		if err != OK:
			return err
	return OK


# ---- Reading ---------------------------------------------------------------

static func _rows(path: String, p: Plan) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		p.errors.append("%s is missing" % path.get_file())
		return out
	var rows := Sheets.read_csv(path)
	if rows.is_empty():
		return out
	var header := rows[0]
	for n in range(1, rows.size()):
		var row := rows[n]
		if row.size() == 0 or (row.size() == 1 and row[0].strip_edges() == ""):
			continue
		var d := {"_row": n + 1}
		for c in header.size():
			d[header[c].strip_edges()] = row[c].strip_edges() if c < row.size() else ""
		out.append(d)
	return out


static func _read_rivers(path: String, p: Plan) -> Dictionary:
	var out := {}
	for d in _rows(path, p):
		var where := "rivers.csv row %d" % d._row
		var r := River.new()
		r.id = d.get("id", "")
		if not RegEx.create_from_string(Sheets.ID_RULE).search(r.id):
			p.errors.append("%s: id '%s' must be lower case letters, digits and _" % [where, r.id])
			continue
		if out.has(r.id):
			p.errors.append("%s: river '%s' appears twice" % [where, r.id])
			continue
		r.name = d.get("name", r.id)
		r.width_m = _num(d, "width_m", 16.0, where, p, 2.0, 200.0)
		r.heading = _num(d, "start_heading_deg", 0.0, where, p, -360.0, 360.0)
		r.fish_per_100m = _num(d, "fish_per_100m", 2.7, where, p, 0.1, 20.0)
		r.spring_fed = String(d.get("spring_fed", "")).to_lower() in ["yes", "true", "1"]
		r.spawn = d.get("spawn", "")
		r.hatches_like = d.get("hatches_like", "")
		r.grass_bank_m = _num(d, "grass_bank_m", 0.0, where, p, 0.0, 40.0)
		_check_spawn(r, where, p)
		if r.hatches_like != "" and not ResourceLoader.exists(_stretch_path(r.hatches_like)):
			p.errors.append("%s: hatches_like: no stretch '%s' in %s" % [where, r.hatches_like, OUT_DIR])
		out[r.id] = r
	return out


static func _read_markers(path: String, rivers: Dictionary, p: Plan) -> void:
	for d in _rows(path, p):
		var where := "river_markers.csv row %d" % d._row
		var rid: String = d.get("river", "")
		if not rivers.has(rid):
			p.errors.append("%s: no river '%s' in rivers.csv" % [where, rid])
			continue
		var kind: String = String(d.get("kind", "")).to_lower()
		where += " (%s %s)" % [kind, d.get("at_m", "")]
		if not (kind in KINDS or kind in PLANNED):
			p.errors.append("%s: unknown kind '%s' (known: %s)" % [where, kind, ", ".join(KINDS + PLANNED)])
			continue
		var m := {"row": where, "kind": kind, "note": d.get("note", ""), "title": d.get("value", ""),
			"value": String(d.get("value", "")).to_lower(),
			"at": _num(d, "at_m", NAN, where, p, 0.0, 100000.0),
			"length": _num(d, "length_m", 0.0, where, p, 0.0, 100000.0),
			"offset": _num(d, "offset_m", -1.0, where, p, 0.0, 200.0),
			"size": _num(d, "size_m", 0.0, where, p, 0.0, 200.0),
			"side": String(d.get("side", "")).to_lower()}
		if is_nan(m.at):
			p.errors.append("%s: at_m is required" % where)
			continue
		if m.side != "" and not m.side in SIDES:
			p.errors.append("%s: side must be left, right or mid" % where)
		_check_value(m, where, p)
		if kind in PLANNED:
			p.notes.append("%s: drawn on the plate; built in REQ-0014 step 3" % where)
		rivers[rid].markers.append(m)
	for r: River in rivers.values():
		r.markers.sort_custom(func(a, b): return a.at < b.at)


static func _check_value(m: Dictionary, where: String, p: Plan) -> void:
	match m.kind:
		"bend":
			if _bend_angle(m.value) == 0.0 or m.length <= 0.0:
				p.errors.append("%s: a bend needs length_m and a value like 'left 60' or 'right 90'" % where)
		"water":
			if not WATER_DEPTH.has(m.value.replace("-", "_").replace(" ", "_")) or m.length <= 0.0:
				p.errors.append("%s: water needs length_m and one of %s" % [where, ", ".join(WATER_DEPTH.keys())])
		"section":
			if m.value == "":
				p.errors.append("%s: a section needs a name in value (Upper Fall)" % where)
		"boulder", "eddy", "gravel_bar", "grass", "log", "angler_start":
			if m.side == "":
				p.errors.append("%s: side is required (left, right or mid)" % where)


static func _check_spawn(r: River, where: String, p: Plan) -> void:
	if r.spawn == "":
		p.errors.append("%s: spawn is required (redband:0.6;brook:0.2)" % where)
	for pair in r.spawn.split(";", false):
		var kv := pair.split(":")
		if kv.size() != 2 or not kv[1].is_valid_float() or float(kv[1]) <= 0.0 or float(kv[1]) > 1.0:
			p.errors.append("%s: spawn '%s' should be fish:abundance, abundance in (0, 1]" % [where, pair])
		elif not ResourceLoader.exists("res://data/fish/%s.tres" % kv[0].strip_edges()):
			p.errors.append("%s: spawn: no fish '%s' in data/fish" % [where, kv[0]])


static func _num(d: Dictionary, key: String, fallback: float, where: String, p: Plan,
		lo: float, hi: float) -> float:
	var s: String = d.get(key, "")
	if s == "":
		return fallback
	if not s.is_valid_float():
		p.errors.append("%s: %s '%s' isn't a number" % [where, key, s])
		return fallback
	var v := float(s)
	if v < lo or v > hi:
		p.errors.append("%s: %s %s is outside %s to %s" % [where, key, s, lo, hi])
	return v


## Degrees a bend turns: left is negative (screen y points down).
static func _bend_angle(value: String) -> float:
	var parts := value.split(" ", false)
	if parts.size() != 2 or not parts[1].is_valid_float() or not parts[0] in ["left", "right"]:
		return 0.0
	return float(parts[1]) * (-1.0 if parts[0] == "left" else 1.0)


# ---- Building --------------------------------------------------------------

## Walks the river from its top, turning through each bend.
static func _trace(r: River, p: Plan) -> void:
	var end_at := 0.0
	var has_end := false
	for m in r.markers:
		if m.kind == "end":
			end_at = m.at
			has_end = true
	if not has_end:
		for m in r.markers:
			end_at = maxf(end_at, m.at + m.length)
	r.length_m = end_at
	var n := maxi(int(ceilf(end_at / STEP)), 1) + 1
	r.headings.resize(n)
	r.points.resize(n)
	var h := deg_to_rad(r.heading)
	var pos := Vector2.ZERO
	for i in n:
		var s := i * STEP
		r.headings[i] = h
		r.points[i] = pos
		for m in r.markers:
			if m.kind == "bend" and s >= m.at and s < m.at + m.length:
				h += deg_to_rad(_bend_angle(m.value)) * STEP / m.length
		pos += River._dir(h) * STEP
	for m in r.markers:
		if m.at > end_at + 0.001:
			p.errors.append("%s: past the river's end at %d m" % [m.row, end_at])


static func _plan_sections(r: River, p: Plan) -> void:
	var starts: Array[Dictionary] = []
	for m in r.markers:
		if m.kind == "section":
			starts.append(m)
	if starts.is_empty():
		p.notes.append("%s: no section markers, so nothing to build" % r.id)
		return
	for k in starts.size():
		var from: float = starts[k].at
		var to: float = starts[k + 1].at if k + 1 < starts.size() else r.length_m
		var title: String = starts[k].title
		var path := _stretch_path("%s_%s" % [r.id, slug(title)])
		p.sections.append({"path": path, "river": r, "from": from, "to": to, "name": title,
			"stretch": build_section(r, from, to), "origin": section_box(r, from, to).position})


## "Upper Fall" -> upper_fall.
static func slug(title: String) -> String:
	var out := ""
	for ch in title.to_lower().strip_edges():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.trim_prefix("_").trim_suffix("_")


static func _stretch_path(id: String) -> String:
	return OUT_DIR.path_join(id + ".tres")


## One section of a river as a Stretch, in its own map with its top-left at 0.
static func build_section(r: River, from: float, to: float) -> Stretch:
	var hw := r.width_m * 0.5
	var box := section_box(r, from, to)
	var origin := box.position
	var st := Stretch.new()
	st.size_m = box.size
	var s := from
	st.half_width = hw
	var line := PackedVector2Array()
	s = from - LEAD
	while s <= to + LEAD:
		line.append((_lead_point(r, from, to, s) - origin).snapped(Vector2(0.01, 0.01)))
		s += POINT_STEP
	st.centreline = line
	st.depth_keys = _depth_keys(r, from - LEAD, to + LEAD)
	st.fish_per_100m = r.fish_per_100m
	st.spring_fed = r.spring_fed
	st.streamed = true
	st.spawn = _spawn(r)
	if r.hatches_like != "":
		var like: Stretch = load(_stretch_path(r.hatches_like))
		var hatches: Array[HatchEntry] = []
		for h in like.hatches:
			hatches.append(h.duplicate())  # shallow: keeps links to data/insects
		st.hatches = hatches
	var feats: Array[RiverFeature] = []
	st.angler_start = r.point_at(from + 8.0) - r.left_at(from + 8.0) * (hw + 3.0) - origin
	for m in r.markers:
		if m.at < from or m.at >= to or not m.kind in KINDS:
			continue
		var f := _feature(r, m, hw, origin)
		if f != null:
			feats.append(f)
		if m.kind == "angler_start":
			st.angler_start = _place(r, m, hw, origin, true)
	if r.grass_bank_m > 0.0:
		feats.append(GrassBank.along(r.grass_bank_m))
	st.features = feats
	return st


## The section's map in river coordinates (m): the river plus BANK_ROOM of
## land, snapped to whole metres. Its top-left is the map's origin.
static func section_box(r: River, from: float, to: float) -> Rect2:
	var box := Rect2(r.point_at(from), Vector2.ZERO)
	var s := from
	while s <= to:
		box = box.expand(r.point_at(s))
		s += STEP
	box = box.grow(r.width_m * 0.5 + BANK_ROOM)
	var origin := box.position.floor()
	return Rect2(origin, (box.end - origin).ceil())


## Inside the section the real river; past its ends, straight on.
static func _lead_point(r: River, from: float, to: float, s: float) -> Vector2:
	if s < from:
		return r.point_at(from) - r.dir_at(from) * (from - s)
	if s > to:
		return r.point_at(to) + r.dir_at(to) * (s - to)
	return r.point_at(s)


static func _depth_keys(r: River, a: float, b: float) -> PackedVector2Array:
	var keys := {0.0: BASE_DEPTH, 1.0: BASE_DEPTH}
	var span := b - a
	for m in r.markers:
		if m.kind != "water" or m.at + m.length < a or m.at > b:
			continue
		var d: float = WATER_DEPTH[m.value.replace("-", "_").replace(" ", "_")]
		for t in [0.2, 0.5, 0.8]:
			var u: float = (m.at + m.length * t - a) / span
			if u > 0.0 and u < 1.0:
				keys[snappedf(u, 0.001)] = d
	var us := keys.keys()
	us.sort()
	var out := PackedVector2Array()
	for u in us:
		out.append(Vector2(u, keys[u]))
	return out


static func _spawn(r: River) -> Array[SpawnEntry]:
	var out: Array[SpawnEntry] = []
	for pair in r.spawn.split(";", false):
		var kv := pair.split(":")
		var e := SpawnEntry.new()
		e.species = load("res://data/fish/%s.tres" % kv[0].strip_edges())
		e.abundance = float(kv[1])
		out.append(e)
	return out


## Where a marker sits (m, in the section's map). In the water it is offset_m
## in from its bank; on land (`land`), offset_m back from the water.
static func _place(r: River, m: Dictionary, hw: float, origin: Vector2, land := false) -> Vector2:
	var c := r.point_at(m.at)
	if m.side == "mid" or m.side == "":
		return c - origin
	var out := r.left_at(m.at) * (1.0 if m.side == "left" else -1.0)
	var off: float = m.offset if m.offset >= 0.0 else (3.0 if land else 1.5)
	return c + out * (hw + off if land else hw - off) - origin


static func _feature(r: River, m: Dictionary, hw: float, origin: Vector2) -> RiverFeature:
	match m.kind:
		"boulder":
			return Boulder.make(_place(r, m, hw, origin), m.size if m.size > 0.0 else 0.8)
		"eddy":
			var e := Eddy.new()
			e.centre = _place(r, m, hw, origin)
			e.radius = m.size if m.size > 0.0 else 3.0
			if m.value.is_valid_float():
				e.strength = clampf(float(m.value), 0.0, 2.0)
			return e
		"gravel_bar":
			var g := GravelBar.new()
			g.centre = _place(r, m, hw, origin)
			g.radius = m.size if m.size > 0.0 else 3.0
			return g
		"grass":
			var size: float = m.size if m.size > 0.0 else 6.0
			return GrassPatch.make(_place(r, m, hw, origin, true), Vector2(size, size * 0.5),
				clampf(float(m.value), 0.1, 4.0) if m.value.is_valid_float() else 1.0)
		"log":
			# Lies from the bank, angled 35 degrees downstream into the current.
			var bank := m.duplicate()
			bank.offset = 0.5
			var a := _place(r, bank, hw, origin)
			var inward := -r.left_at(m.at) * (1.0 if m.side == "left" else -1.0)
			var l := FallenLog.new()
			l.a = a
			l.b = a + (inward * cos(deg_to_rad(35.0)) + r.dir_at(m.at) * sin(deg_to_rad(35.0))) \
				* (m.size if m.size > 0.0 else 6.0)
			return l
	return null
