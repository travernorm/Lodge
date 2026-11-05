class_name ChunkPainter
extends Node
## Paints the pictures for a part of a river (REQ-0014): the ground (grass,
## gravel, cut banks on the outside of bends, point bars on the inside, and
## water in depth bands where no WaterView paints it) and the two images a
## WaterView bakes from the field. A view helper: reads a RiverField, writes
## nothing else.
##
## For a whole stretch, run() paints it at once (RiverView). For a chunk of a
## section, the streamer calls step() a few rows at a time until it is done,
## so painting never stalls a frame. Pixels here, through WorldScale.

const COL_GRASS := Color("4b6b3a")
const COL_TUFT := Color("5f8446")
const COL_GRAVEL := Color("8a7e62")
const COL_CUT_BANK := Color("5b3e26")
const COL_WATER := Color("3f6e7a")
const COL_POOL := Color("2c5260")
const COL_DEEP := Color("244550")
const COL_RIFFLE := Color("5e8f96")
const COL_SHALLOW := Color("6f9188")
## The old flat water: a colour per depth band, where each band starts, and a 2x2 dither.
const BANDS: Array[Color] = [COL_SHALLOW, COL_RIFFLE, COL_WATER, COL_POOL, COL_DEEP]
const CUTS: Array[float] = [0.1, 0.38, 0.62, 0.86]
const DITHER: Array[float] = [-0.03, 0.01, 0.03, -0.01]

## The ground picture, the WaterView's field and edge images, and the
## BankView's image (when it has a look), once done.
var ground: ImageTexture
var field_img: Image
var edge_img: Image
var bank_img: Image

var _river: RiverField
var _clear := false
var _clear_land := false
var _bank_look: BankLook
## What to paint (px, whole pixels) and where the field's grid starts (px).
var _area := Rect2i()
var _origin := Vector2i.ZERO
var _rng := RandomNumberGenerator.new()
var _stages: Array = []
var _stage := 0
var _at := 0
# Scratch.
var _field_data := PackedByteArray()
var _bank := PackedFloat32Array()
var _rock := PackedFloat32Array()
var _scale := Vector2i.ONE
var _depth := PackedFloat32Array()
var _wet := PackedFloat32Array()
var _shore := PackedFloat32Array()
var _bend := PackedFloat32Array()
var _ground := PackedByteArray()


## `area` is the part of the world to paint (m); `clear_water` leaves the
## water see-through for a WaterView underneath, `clear_land` the land for a
## BankView. `tuft_seed` scatters the grass tufts. With a `bank_look`, it also
## bakes the BankView's image.
func _init(river: RiverField, area: Rect2, clear_water: bool, clear_land := false,
		tuft_seed := 1979, bank_look: BankLook = null) -> void:
	_river = river
	_clear = clear_water
	_clear_land = clear_land
	_bank_look = bank_look
	_area = Rect2i(WorldScale.vec_to_px(area.position).round(), WorldScale.vec_to_px(area.size).round())
	_origin = Vector2i(WorldScale.vec_to_px(Vector2(river.left, river.top)).round())
	_rng.seed = tuft_seed
	_field_data.resize(river.cols * river.rows * 4)
	_bank.resize(river.cols * river.rows)
	_rock.resize(river.cols * river.rows)
	_rock.fill(WaterView.EDGE_RANGE)
	_ground.resize(_area.size.x * _area.size.y * 4)
	_stages = [
		[_field_row, river.rows],
		[_edge_row, river.rows],
		[_prepare_ground, 1],
		[_prepare_layer, 4],
		[_ground_row, _area.size.y],
		[_finish, 1],
	]
	if bank_look != null:
		_stages.insert(2, [_bank_image, 1])


## Paints up to `units` rows. True when everything is painted.
func step(units: int) -> bool:
	while _stage < _stages.size() and units > 0:
		var stage: Array = _stages[_stage]
		if _at < stage[1]:
			(stage[0] as Callable).call(_at)
			_at += 1
			units -= 1
		if _at >= stage[1]:
			_stage += 1
			_at = 0
	return done()


func done() -> bool:
	return _stage >= _stages.size()


func run() -> void:
	step(1 << 30)


func _bank_image(_unit: int) -> void:
	bank_img = BankView.data_image(_river, _bank_look)


func _field_row(j: int) -> void:
	WaterView.field_row(_river, _field_data, j)


func _edge_row(j: int) -> void:
	WaterView.edge_row(_river, _bank, _rock, j)


## The field's per-cell layers scaled up to whole pixels (bilinear), so each
## ground pixel can be classified. Each cell is the same number of pixels
## everywhere, so neighbouring chunks line up.
func _prepare_ground(_unit: int) -> void:
	field_img = Image.create_from_data(_river.cols, _river.rows, false, Image.FORMAT_RGBA8, _field_data)
	edge_img = WaterView.edge_image_from(_river, _bank, _rock)
	_field_data = PackedByteArray()
	var cell_px := roundi(RiverField.CELL * WorldScale.PX_PER_M)
	_scale = Vector2i(_river.cols, _river.rows) * cell_px


## One layer per step: depth, wet, shore, bend.
func _prepare_layer(n: int) -> void:
	match n:
		0: _depth = _layer(_river.depth, 1.0)
		1: _wet = _layer(PackedFloat32Array(Array(_river.wet)), 1.0)
		2: _shore = _layer(_river.shore, 20.0)
		3: _bend = _layer(_river.bend, 1.0)


## The index into the scaled-up layers of picture pixel (x, y).
func _grid(x: int, y: int) -> int:
	var gx := clampi(_area.position.x - _origin.x + x, 0, _scale.x - 1)
	var gy := clampi(_area.position.y - _origin.y + y, 0, _scale.y - 1)
	return gy * _scale.x + gx


func _ground_row(y: int) -> void:
	for x in _area.size.x:
		var g := _grid(x, y)
		var col := COL_GRASS
		if _wet[g] >= 0.5 and _clear:
			col = Color.TRANSPARENT  # the WaterView paints it, underneath
		elif _wet[g] < 0.5 and _clear_land:
			col = Color.TRANSPARENT  # the BankView paints it, underneath
		elif _wet[g] >= 0.5:
			var d := _depth[g] + DITHER[(y % 2) * 2 + (x % 2)]
			var band := 0
			while band < CUTS.size() and d > CUTS[band]:
				band += 1
			col = BANDS[band]
		else:
			var shore := _shore[g]
			var b := _bend[g]
			if b > 0.25 and shore < 0.5 + 0.5 * b:
				col = COL_CUT_BANK  # undercut earth on the outside of a bend
			elif shore < 0.75 + 3.0 * maxf(-b, 0.0):
				col = COL_GRAVEL  # the inside of a bend widens into a point bar
			elif _rng.randf() < 0.025:
				col = COL_TUFT
		var idx := (y * _area.size.x + x) * 4
		_ground[idx] = col.r8
		_ground[idx + 1] = col.g8
		_ground[idx + 2] = col.b8
		_ground[idx + 3] = col.a8


## Gravel bars on the bank, then the picture.
func _finish(_unit: int) -> void:
	var img := Image.create_from_data(_area.size.x, _area.size.y, false, Image.FORMAT_RGBA8, _ground)
	var pos := Vector2(_area.position)
	for f in [] if _clear_land else _river.features:
		if not f is GravelBar:
			continue
		var c := WorldScale.vec_to_px((f as GravelBar).centre) - pos
		var r := WorldScale.to_px((f as GravelBar).radius)
		for y in range(maxi(0, int(c.y - r)), mini(_area.size.y, int(c.y + r) + 1)):
			for x in range(maxi(0, int(c.x - r)), mini(_area.size.x, int(c.x + r) + 1)):
				if Vector2(x, y).distance_to(c) <= r and _wet[_grid(x, y)] < 0.5:
					img.set_pixel(x, y, COL_GRAVEL)
	ground = ImageTexture.create_from_image(img)
	_ground = PackedByteArray()
	_depth = PackedFloat32Array()
	_wet = PackedFloat32Array()
	_shore = PackedFloat32Array()
	_bend = PackedFloat32Array()


## One per-cell layer as pixels, clamped to +-limit first (shore holds INF).
func _layer(layer: PackedFloat32Array, limit: float) -> PackedFloat32Array:
	var vals := PackedFloat32Array()
	vals.resize(layer.size())
	for i in layer.size():
		vals[i] = clampf(layer[i], -limit, limit)
	var img := Image.create_from_data(_river.cols, _river.rows, false, Image.FORMAT_RF, vals.to_byte_array())
	img.resize(_scale.x, _scale.y, Image.INTERPOLATE_BILINEAR)
	return img.get_data().to_float32_array()
