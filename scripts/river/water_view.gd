@tool
class_name WaterView
extends Node2D
## Paints the river's water with a WaterLook. The stream scene calls setup()
## with its RiverField; this view bakes the field into a small texture (one
## texel per 0.25 m cell: current, depth, wet) and a shader picks the deep, mid
## or white texture per pixel from it. A second baked texture holds how far each
## cell is from the bank and from the nearest rock, for the foam lines. It draws behind the stream scene, which
## leaves its water pixels clear when this view is active.
##
## In the editor it builds its own field from preview_stretch, so the water
## shows in the viewport and changes live as the look is edited.

const SHADER := preload("res://shaders/water.gdshader")
## Furthest distance (m) from a bank or rock the edge texture can hold.
const EDGE_RANGE := 3.0

## The look to paint. Empty = the stream scene draws its old flat bands.
@export var look: WaterLook:
	set(v):
		if look != null and look.changed.is_connected(_apply_look):
			look.changed.disconnect(_apply_look)
		look = v
		if look != null:
			look.changed.connect(_apply_look)
		_apply_look()
## Editor only: the stretch to preview. The game uses the stream scene's river.
@export var preview_stretch: Stretch:
	set(v):
		preview_stretch = v
		if Engine.is_editor_hint() and is_inside_tree():
			_build_preview()

var _mat := ShaderMaterial.new()
var _size := Vector2.ZERO
## The part of the world it paints (px) for a whole field.
var _area := Rect2()
## Chunks of a section it paints, by key: Vector2i -> Node2D.
var _chunks := {}
var _palette_tex := GradientTexture1D.new()


func _ready() -> void:
	show_behind_parent = true
	_mat.shader = SHADER
	material = _mat
	_apply_look()
	if Engine.is_editor_hint():
		_build_preview()


## Whether this view paints the water (a complete look is set).
func is_active() -> bool:
	return look != null and look.is_complete()


## Called by the stream scene once its river is built (a whole field).
func setup(river: RiverField) -> void:
	_size = Vector2(river.width, river.bottom - river.top) * WorldScale.PX_PER_M
	_area = Rect2(WorldScale.vec_to_px(Vector2(river.left, river.top)), _size)
	_set_field(_mat, river, field_image(river), edge_image(river))
	queue_redraw()


## Streaming (REQ-0014): paints one chunk of a section, `area` (px) being the
## chunk's own part of the world, from images a ChunkPainter made. Each chunk
## draws on a child of its own with a copy of the material.
func add_chunk(key: Vector2i, river: RiverField, area: Rect2, field_img: Image, edge_img: Image) -> void:
	drop_chunk(key)
	var part := Node2D.new()
	var mat := _mat.duplicate() as ShaderMaterial
	_set_field(mat, river, field_img, edge_img)
	part.material = mat
	part.draw.connect(func() -> void:
		if is_active():
			part.draw_rect(area, Color.WHITE))
	add_child(part)
	_chunks[key] = part


func drop_chunk(key: Vector2i) -> void:
	if _chunks.has(key):
		(_chunks[key] as Node).queue_free()
		_chunks.erase(key)


func _set_field(mat: ShaderMaterial, river: RiverField, field_img: Image, edge_img: Image) -> void:
	mat.set_shader_parameter(&"field_origin", WorldScale.vec_to_px(Vector2(river.left, river.top)))
	mat.set_shader_parameter(&"field", ImageTexture.create_from_image(field_img))
	mat.set_shader_parameter(&"edges", ImageTexture.create_from_image(edge_img))
	mat.set_shader_parameter(&"edge_range", EDGE_RANGE)
	mat.set_shader_parameter(&"field_cells", Vector2(river.cols, river.rows))
	mat.set_shader_parameter(&"cell_px", RiverField.CELL * WorldScale.PX_PER_M)
	mat.set_shader_parameter(&"flow_range", flow_range())
	mat.set_shader_parameter(&"water_speed", RiverField.WATER_SPEED)
	mat.set_shader_parameter(&"px_per_m", WorldScale.PX_PER_M)


## Sets a shader value on the main material and every chunk's copy.
func _set_param(name: StringName, value: Variant) -> void:
	_mat.set_shader_parameter(name, value)
	for part: Node2D in _chunks.values():
		(part.material as ShaderMaterial).set_shader_parameter(name, value)
		part.queue_redraw()


## Rain dimples on the water, 0 to 1 (REQ-0009 version C). main.tscn connects
## the weather view's rain_on_water here.
func set_rain(amount: float) -> void:
	_set_param(&"rain", clampf(amount, 0.0, 1.0))


## Largest current the field texture can hold (m/s).
static func flow_range() -> float:
	return RiverField.WATER_SPEED * 1.5


## The field as an image, one texel per cell: R, G = current (m/s) mapped from
## -flow_range..flow_range to 0..1, B = depth, A = wet.
static func field_image(river: RiverField) -> Image:
	var data := PackedByteArray()
	data.resize(river.cols * river.rows * 4)
	for j in river.rows:
		field_row(river, data, j)
	return Image.create_from_data(river.cols, river.rows, false, Image.FORMAT_RGBA8, data)


## One row of field_image() into `data` (cols * rows * 4 bytes).
static func field_row(river: RiverField, data: PackedByteArray, j: int) -> void:
	var k := 0.5 / flow_range()
	var has_wet := not river.wet.is_empty()
	for idx in range(j * river.cols, (j + 1) * river.cols):
		var v := river.velocity[idx]
		data[idx * 4] = clampi(roundi((0.5 + v.x * k) * 255.0), 0, 255)
		data[idx * 4 + 1] = clampi(roundi((0.5 + v.y * k) * 255.0), 0, 255)
		data[idx * 4 + 2] = clampi(roundi(river.depth[idx] * 255.0), 0, 255)
		data[idx * 4 + 3] = 255 if (not has_wet or river.wet[idx] == 1) else 0


## How far each cell is from the edges, one texel per cell: R = from the bank,
## G = from the nearest boulder or log, both in metres mapped 0..EDGE_RANGE to
## 0..1.
static func edge_image(river: RiverField) -> Image:
	var n := river.cols * river.rows
	var bank := PackedFloat32Array()
	var rock := PackedFloat32Array()
	bank.resize(n)
	rock.resize(n)
	rock.fill(EDGE_RANGE)
	for j in river.rows:
		edge_row(river, bank, rock, j)
	return edge_image_from(river, bank, rock)


## One row of edge_image(): the bank distance for the row, and each rock cell
## in it stamps its distance onto its neighbours in `rock`.
static func edge_row(river: RiverField, bank: PackedFloat32Array, rock: PackedFloat32Array, j: int) -> void:
	var reach := ceili(EDGE_RANGE / RiverField.CELL)
	for i in river.cols:
		var idx := j * river.cols + i
		var p := river.cell_pos(i, j)
		if river.shore.is_empty():
			bank[idx] = minf(p.y - river.top, river.bottom - p.y)
		else:
			bank[idx] = -river.shore[idx]
		if (river.wet.is_empty() or river.wet[idx] == 1) and river.is_solid(p):
			for dj in range(-reach, reach + 1):
				for di in range(-reach, reach + 1):
					var ii := i + di
					var jj := j + dj
					if ii < 0 or jj < 0 or ii >= river.cols or jj >= river.rows:
						continue
					var d := Vector2(di, dj).length() * RiverField.CELL
					var k := jj * river.cols + ii
					rock[k] = minf(rock[k], d)


static func edge_image_from(river: RiverField, bank: PackedFloat32Array, rock: PackedFloat32Array) -> Image:
	var n := river.cols * river.rows
	var data := PackedByteArray()
	data.resize(n * 4)
	for idx in n:
		data[idx * 4] = clampi(roundi(bank[idx] / EDGE_RANGE * 255.0), 0, 255)
		data[idx * 4 + 1] = clampi(roundi(rock[idx] / EDGE_RANGE * 255.0), 0, 255)
		data[idx * 4 + 3] = 255
	return Image.create_from_data(river.cols, river.rows, false, Image.FORMAT_RGBA8, data)


## A texture's average colour, so the shader can keep its light and dark
## pattern while the palette sets the colour. White when there is no texture.
static func mean_colour(tex: Texture2D) -> Color:
	if tex == null:
		return Color.WHITE
	var img := tex.get_image()
	if img == null or img.is_empty():
		return Color.WHITE
	if img.is_compressed():
		img.decompress()
	img = img.duplicate()
	img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var c := img.get_pixel(0, 0)
	return Color(maxf(c.r, 0.02), maxf(c.g, 0.02), maxf(c.b, 0.02))


func _draw() -> void:
	if is_active() and _size != Vector2.ZERO:
		draw_rect(_area, Color.WHITE)


func _apply_look() -> void:
	if look == null:
		queue_redraw()
		return
	var px := WorldScale.PX_PER_M
	for p in [[&"deep_tex", look.deep], [&"mid_tex", look.mid], [&"white_tex", look.white],
			[&"deep_tint", look.deep_tint], [&"mid_tint", look.mid_tint],
			[&"white_tint", look.white_tint], [&"shallow_tint", look.shallow_tint],
			[&"deep_start", look.deep_start], [&"deep_softness", look.deep_softness],
			[&"white_start", look.white_start], [&"white_softness", look.white_softness],
			[&"shallow_depth", look.shallow_depth], [&"shallow_amount", look.shallow_amount],
			[&"edge_noise", look.edge_noise], [&"edge_noise_px", look.edge_noise_size_m * px],
			[&"dither", look.dither], [&"motion", look.motion], [&"motion_cycle", look.motion_cycle],
			[&"use_palette", look.palette != null], [&"texture_detail", look.texture_detail],
			[&"wash_clear", look.wash_clear],
			[&"deep_mean", mean_colour(look.deep)], [&"mid_mean", mean_colour(look.mid)],
			[&"bed_depth", look.bed_depth], [&"sand_tint", look.sand_tint],
			[&"sand_amount", look.sand_amount], [&"stone_tint", look.stone_tint],
			[&"stone_amount", look.stone_amount], [&"stone_px", look.stone_size_m * px],
			[&"stone_density", look.stone_density], [&"foam_tint", look.foam_tint],
			[&"bank_foam", look.bank_foam], [&"bank_foam_w", look.bank_foam_width_m],
			[&"rock_foam", look.rock_foam], [&"rock_foam_w", look.rock_foam_width_m],
			[&"foam_surge", look.foam_surge]]:
		_set_param(p[0], p[1])
	if look.palette != null:
		_palette_tex.gradient = look.palette
		_set_param(&"palette", _palette_tex)
	queue_redraw()


func _build_preview() -> void:
	if preview_stretch == null:
		return
	var river := RiverField.new()
	river.build_stretch(preview_stretch)
	setup(river)
