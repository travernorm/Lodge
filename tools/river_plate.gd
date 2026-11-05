extends RefCounted
## Preview plates for river sheets (REQ-0014 step 1): a top-down map of one
## section, built from the real river field, with every marker from the sheet
## labelled by its distance so Traver can answer "at 340 m, move the log".
## Not game art; a review drawing only.

const PixelFont := preload("res://tools/pixel_font.gd")
const Sheets := preload("res://tools/river_sheets.gd")

const PX_PER_M := 3
const LAND := Color("5f7f45")
const BANK := Color("b9a77f")
const SHALLOW := Color("8fc3c9")
const DEEP := Color("1f4f7a")
const ROCK := Color("6e6a64")
const LOG := Color("6b4a2b")
const GRASS := Color("86ad55")
const EDDY := Color("e8f4f4")
const TICK := Color("ffffff")
const BUILT := Color("fff2b3")
const PLANNED := Color("ff8a7a")


## Draws `section` (a Plan.sections entry) to an Image.
static func draw(section: Dictionary) -> Image:
	var st: Stretch = section.stretch
	var r = section.river
	var field := RiverField.new()
	field.build_stretch(st)
	var size := Vector2i((st.size_m * PX_PER_M).ceil())
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var inv := 1.0 / PX_PER_M
	for y in size.y:
		for x in size.x:
			var p := Vector2(x + 0.5, y + 0.5) * inv
			var c := LAND
			if field.is_water(p):
				c = SHALLOW.lerp(DEEP, clampf(field.depth_at(p), 0.0, 1.0))
			elif field.depth_at(p) <= 0.0 and _near_water(field, p):
				c = BANK
			img.set_pixel(x, y, c)
	var origin: Vector2 = section.origin
	for f in st.features:
		_draw_feature(img, f)
	_draw_ticks(img, r, section, origin)
	_draw_markers(img, r, section, origin)
	var title := "%s - %s  %d TO %d M" % [r.name, section.name, section.from, section.to]
	PixelFont.draw(img, Vector2i(6, 6), title, TICK, 2)
	_scale_bar(img, Vector2i(6, 22))
	return img


static func _near_water(field: RiverField, p: Vector2) -> bool:
	for o in [Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
		if field.is_water(p + o):
			return true
	return false


static func _px(p: Vector2) -> Vector2i:
	return Vector2i((p * PX_PER_M).round())


static func _draw_feature(img: Image, f: RiverFeature) -> void:
	if f is Boulder:
		_disc(img, f.centre, f.radius, ROCK)
	elif f is FallenLog:
		_line(img, f.a, f.b, LOG, 2)
	elif f is Eddy:
		_ring(img, f.centre, f.radius, EDDY)
	elif f is GravelBar:
		_disc(img, f.centre, f.radius, BANK)
	elif f is GrassPatch:
		for a in 24:
			var q: Vector2 = f.centre + Vector2.from_angle(a * TAU / 24.0) * f.radii
			_disc(img, q, 0.4, GRASS)


## A tick across the river and its distance every 50 m.
static func _draw_ticks(img: Image, r, section: Dictionary, origin: Vector2) -> void:
	var hw: float = r.width_m * 0.5
	var s := ceilf(section.from / 50.0) * 50.0
	while s <= section.to:
		var c: Vector2 = r.point_at(s) - origin
		var left: Vector2 = r.left_at(s)
		_line(img, c - left * (hw + 1.0), c - left * (hw + 3.0), TICK, 1)
		var at := _px(c - left * (hw + 5.0))
		PixelFont.draw(img, at - Vector2i(0, 2), "%d" % s, TICK, 2)
		s += 50.0


## Every marker that is a spot (not a run of water or a bend), labelled with
## its kind and distance on the bank beside it. Planned kinds in red.
static func _draw_markers(img: Image, r, section: Dictionary, origin: Vector2) -> void:
	var hw: float = r.width_m * 0.5
	var flip := 1.0
	for m in r.markers:
		if m.at < section.from or m.at >= section.to or m.kind in ["bend", "end", "section"]:
			continue
		var c: Vector2 = r.point_at(m.at) - origin
		var left: Vector2 = r.left_at(m.at)
		var color := PLANNED if m.kind in Sheets.PLANNED else BUILT
		var label := "%s %d" % [m.kind.replace("_", " "), m.at]
		if m.kind == "water":
			label = "%s %d" % [m.value.replace("_", " "), m.at]
		if m.kind in Sheets.PLANNED:
			_diamond(img, c, 2.0, color)
		var side := 1.0 if m.side == "left" else (-1.0 if m.side == "right" else flip)
		flip = -flip
		var at := _px(c + left * side * (hw + 4.0 + PixelFont.width(label, 2) / (2.0 * PX_PER_M) * absf(left.x)))
		var w := PixelFont.width(label, 2)
		at.x -= w / 2
		at.x = clampi(at.x, 2, img.get_width() - w - 2)
		PixelFont.draw(img, at, label, color, 2)


static func _scale_bar(img: Image, at: Vector2i) -> void:
	img.fill_rect(Rect2i(at, Vector2i(10 * PX_PER_M, 2)), TICK)
	PixelFont.draw(img, at + Vector2i(10 * PX_PER_M + 4, -2), "10 M", TICK, 1)


static func _disc(img: Image, c: Vector2, rad: float, color: Color) -> void:
	var a := _px(c - Vector2.ONE * rad)
	var b := _px(c + Vector2.ONE * rad)
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			if Vector2(x, y).distance_to(c * PX_PER_M) <= rad * PX_PER_M and _in(img, x, y):
				img.set_pixel(x, y, color)


static func _ring(img: Image, c: Vector2, rad: float, color: Color) -> void:
	for a in 48:
		var q := _px(c + Vector2.from_angle(a * TAU / 48.0) * rad)
		if _in(img, q.x, q.y):
			img.set_pixel(q.x, q.y, color)


static func _diamond(img: Image, c: Vector2, rad: float, color: Color) -> void:
	var p := _px(c)
	var k := roundi(rad * PX_PER_M)
	for dy in range(-k, k + 1):
		for dx in range(-k, k + 1):
			if absi(dx) + absi(dy) <= k and _in(img, p.x + dx, p.y + dy):
				img.set_pixel(p.x + dx, p.y + dy, color)


static func _line(img: Image, a: Vector2, b: Vector2, color: Color, thick: int) -> void:
	var n := maxi(ceili(a.distance_to(b) * PX_PER_M), 1)
	for i in n + 1:
		var q := _px(a.lerp(b, float(i) / n))
		img.fill_rect(Rect2i(q - Vector2i.ONE * (thick / 2), Vector2i.ONE * thick)
			.intersection(Rect2i(Vector2i.ZERO, img.get_size())), color)


static func _in(img: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height()
