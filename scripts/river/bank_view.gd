@tool
class_name BankView
extends Node2D
## Paints the land of a stretch with a BankLook (REQ-0013): the wet line,
## gravel, point bars, sand, the cut bank face on the outside of bends, and the
## plain ground the grass grows on. The stream scene calls setup() with its
## RiverField; this view bakes, per field cell, how far it is from the water and
## how far the face and the gravel reach there (BankZones), and a shader picks
## the ground per pixel. Drawn behind the stream scene, after the water, so logs
## and the angler stay on top; its RiverView leaves the land clear.
##
## In the editor it builds its own field from preview_stretch, so the bank shows
## in the viewport and changes live as the look is edited.

const SHADER := preload("res://shaders/bank.gdshader")
## Ranges (m) the baked texture holds: distance from the water, face height,
## and the gravel reach past a point (which can be negative).
const SHORE_RANGE := 8.0
const FACE_RANGE := 4.0
const REACH_LOW := -2.0
const REACH_RANGE := 8.0

@export var look: BankLook:
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
var _river: RiverField


func _ready() -> void:
	show_behind_parent = true
	_mat.shader = SHADER
	material = _mat
	_apply_look()
	if Engine.is_editor_hint():
		_build_preview()


## Whether this view paints the land (it has a look).
func is_active() -> bool:
	return look != null


## Called by the stream scene once its river is built.
func setup(river: RiverField) -> void:
	_river = river
	_size = Vector2(river.width, river.bottom - river.top) * WorldScale.PX_PER_M
	_mat.set_shader_parameter(&"field_cells", Vector2(river.cols, river.rows))
	_mat.set_shader_parameter(&"cell_px", RiverField.CELL * WorldScale.PX_PER_M)
	_bake()


## The bank as an image, one texel per field cell: R = metres from the water,
## G = cut bank face height, B = how far gravel reaches past this point, each
## mapped to 0..1 by the ranges above; A = wet.
static func data_image(river: RiverField, look: BankLook) -> Image:
	var n := river.cols * river.rows
	var inside := _inside_bars(river)
	var data := PackedByteArray()
	data.resize(n * 4)
	for idx in n:
		var shore := clampf(river.shore[idx], 0.0, SHORE_RANGE) if not river.shore.is_empty() else SHORE_RANGE
		var b := river.bend[idx] if not river.bend.is_empty() else 0.0
		var gravel := BankZones.with_bar(BankZones.gravel_m(b, look), shore, inside[idx])
		data[idx * 4] = roundi(shore / SHORE_RANGE * 255.0)
		data[idx * 4 + 1] = clampi(roundi(BankZones.face_m(b, look) / FACE_RANGE * 255.0), 0, 255)
		data[idx * 4 + 2] = clampi(roundi((gravel - shore - REACH_LOW) / REACH_RANGE * 255.0), 0, 255)
		data[idx * 4 + 3] = 255 if river.wet.is_empty() or river.wet[idx] == 1 else 0
	return Image.create_from_data(river.cols, river.rows, false, Image.FORMAT_RGBA8, data)


## Per cell, how far inside the nearest gravel bar it is (m; 0 = outside).
static func _inside_bars(river: RiverField) -> PackedFloat32Array:
	var inside := PackedFloat32Array()
	inside.resize(river.cols * river.rows)
	for f in river.features:
		var g := f as GravelBar
		if g == null:
			continue
		var lo := ((g.centre - Vector2(g.radius, g.radius + river.top)) / RiverField.CELL).floor()
		var hi := ((g.centre + Vector2(g.radius, g.radius - river.top)) / RiverField.CELL).ceil()
		for j in range(maxi(0, int(lo.y)), mini(river.rows, int(hi.y) + 1)):
			for i in range(maxi(0, int(lo.x)), mini(river.cols, int(hi.x) + 1)):
				var idx := j * river.cols + i
				inside[idx] = maxf(inside[idx], g.radius - river.cell_pos(i, j).distance_to(g.centre))
	return inside


func _draw() -> void:
	if is_active() and _size != Vector2.ZERO:
		draw_rect(Rect2(Vector2.ZERO, _size), Color.WHITE)


func _bake() -> void:
	if _river == null or look == null:
		return
	_mat.set_shader_parameter(&"data", ImageTexture.create_from_image(data_image(_river, look)))
	queue_redraw()


func _apply_look() -> void:
	if look == null:
		queue_redraw()
		return
	var px := WorldScale.PX_PER_M
	for p in [[&"face_tex", look.cut_bank], [&"wet_tex", look.wet_stones],
			[&"gravel_tex", look.gravel], [&"sand_tex", look.sand],
			[&"has_wet", look.wet_stones != null], [&"has_gravel", look.gravel != null],
			[&"has_sand", look.sand != null],
			[&"wet_tint", look.wet_tint], [&"gravel_tint", look.gravel_tint],
			[&"sand_tint", look.sand_tint], [&"ground_tint", look.ground_tint],
			[&"tuft_tint", look.tuft_tint], [&"tuft_density", look.tuft_density],
			[&"pebble_density", look.pebble_density], [&"pebble_px", maxf(3.0, roundf(look.pebble_size_m * px))],
			[&"wet_m", look.wet_width_m], [&"sand_m", look.sand_width_m],
			[&"face_height_m", look.face_height_m], [&"lip_m", look.lip_m], [&"min_face_m", look.min_face_m],
			[&"edge_noise_m", look.edge_noise_m], [&"edge_noise_px", look.edge_noise_size_m * px],
			[&"px_per_m", px], [&"shore_range", SHORE_RANGE], [&"face_range", FACE_RANGE],
			[&"reach_low", REACH_LOW], [&"reach_range", REACH_RANGE]]:
		_mat.set_shader_parameter(p[0], p[1])
	_bake()  # widths come from the look, so a change re-bakes (a fraction of a second)
	queue_redraw()


func _build_preview() -> void:
	if preview_stretch == null:
		return
	var river := RiverField.new()
	river.build_stretch(preview_stretch)
	setup(river)
