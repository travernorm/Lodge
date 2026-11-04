@tool
class_name WaterView
extends Node2D
## Paints the river's water with a WaterLook. The stream scene calls setup()
## with its RiverField; this view bakes the field into a small texture (one
## texel per 0.25 m cell: current, depth, wet) and a shader picks the deep, mid
## or white texture per pixel from it. It draws behind the stream scene, which
## leaves its water pixels clear when this view is active.
##
## In the editor it builds its own field from preview_stretch, so the water
## shows in the viewport and changes live as the look is edited.

const SHADER := preload("res://shaders/water.gdshader")

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


## Called by the stream scene once its river is built.
func setup(river: RiverField) -> void:
	_size = Vector2(river.width, river.bottom - river.top) * WorldScale.PX_PER_M
	_mat.set_shader_parameter(&"field", ImageTexture.create_from_image(field_image(river)))
	_mat.set_shader_parameter(&"field_cells", Vector2(river.cols, river.rows))
	_mat.set_shader_parameter(&"cell_px", RiverField.CELL * WorldScale.PX_PER_M)
	_mat.set_shader_parameter(&"flow_range", flow_range())
	_mat.set_shader_parameter(&"water_speed", RiverField.WATER_SPEED)
	_mat.set_shader_parameter(&"px_per_m", WorldScale.PX_PER_M)
	queue_redraw()


## Rain dimples on the water, 0 to 1 (REQ-0009 version C). main.tscn connects
## the weather view's rain_on_water here.
func set_rain(amount: float) -> void:
	_mat.set_shader_parameter(&"rain", clampf(amount, 0.0, 1.0))


## Largest current the field texture can hold (m/s).
static func flow_range() -> float:
	return RiverField.WATER_SPEED * 1.5


## The field as an image, one texel per cell: R, G = current (m/s) mapped from
## -flow_range..flow_range to 0..1, B = depth, A = wet.
static func field_image(river: RiverField) -> Image:
	var data := PackedByteArray()
	data.resize(river.cols * river.rows * 4)
	var k := 0.5 / flow_range()
	var has_wet := not river.wet.is_empty()
	for idx in river.cols * river.rows:
		var v := river.velocity[idx]
		data[idx * 4] = clampi(roundi((0.5 + v.x * k) * 255.0), 0, 255)
		data[idx * 4 + 1] = clampi(roundi((0.5 + v.y * k) * 255.0), 0, 255)
		data[idx * 4 + 2] = clampi(roundi(river.depth[idx] * 255.0), 0, 255)
		data[idx * 4 + 3] = 255 if (not has_wet or river.wet[idx] == 1) else 0
	return Image.create_from_data(river.cols, river.rows, false, Image.FORMAT_RGBA8, data)


func _draw() -> void:
	if is_active() and _size != Vector2.ZERO:
		draw_rect(Rect2(Vector2.ZERO, _size), Color.WHITE)


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
			[&"dither", look.dither], [&"motion", look.motion], [&"motion_cycle", look.motion_cycle]]:
		_mat.set_shader_parameter(p[0], p[1])
	queue_redraw()


func _build_preview() -> void:
	if preview_stretch == null:
		return
	var river := RiverField.new()
	river.build_stretch(preview_stretch)
	setup(river)
