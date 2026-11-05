class_name RiverStreamer
extends Node2D
## Streams a long section (REQ-0014): keeps the chunks of the SectionField
## around the camera built and painted, a little work per frame, and forgets
## far ones. It draws each chunk's ground picture itself and tells the stream
## scene when a chunk is ready to show or gone (signals up), so the scene can
## hand it to the water and grass views.
##
## The stream scene owns it, calls setup() once and update() every frame with
## the part of the world on screen. Pixels on screen; the field is in metres.

## A chunk is built and painted: `field` is its RiverField, `area` its own
## part of the world (m), `painter` holds its water and bank images.
signal chunk_shown(key: Vector2i, field: RiverField, area: Rect2, painter: ChunkPainter)
## A chunk was forgotten.
signal chunk_hidden(key: Vector2i)

## Time per frame (microseconds) for building and painting chunks. The Deck
## draws a frame in 16.7 ms; the game itself uses a few.
const BUDGET_USEC := 4000
## Rows of work between clock checks.
const ROWS_PER_CHECK := 2
## Chunks are built this far (m) past the screen, so they are ready before
## the camera gets there (walking speed is 7.5 m/s), and kept until this far.
const AHEAD_M := 30.0
const KEEP_M := 60.0

var _section: SectionField
var _clear := false
## The BankView's look, when it paints the land (the ground leaves it clear).
var _bank_look: BankLook
## Chunks being painted: Vector2i -> ChunkPainter.
var _painting := {}
## Chunks on show: Vector2i -> [ground texture, area (px)].
var _shown := {}


## `clear_water`: a WaterView paints the water, so the ground leaves it clear;
## `bank_look`: a BankView paints the land with it, likewise. Builds and paints
## the chunks on screen now, so the first frame is whole.
func setup(section: SectionField, clear_water: bool, bank_look: BankLook, view: Rect2) -> void:
	_section = section
	_clear = clear_water
	_bank_look = bank_look
	var view_m := _to_m(view)
	section.want(view_m)
	while section.busy():
		section.step(1 << 30)
	_start_painting()
	for key: Vector2i in _painting.keys():
		(_painting[key] as ChunkPainter).run()
		_show(key)
	update(view)


## One frame: wants the chunks around `view` (px), forgets far ones, and
## builds and paints for up to BUDGET_USEC.
func update(view: Rect2) -> void:
	var view_m := _to_m(view)
	_section.want(view_m.grow(AHEAD_M))
	for key in _section.drop_outside(view_m.grow(KEEP_M)):
		if _painting.has(key):
			(_painting[key] as ChunkPainter).free()
			_painting.erase(key)
		if _shown.has(key):
			_shown.erase(key)
			chunk_hidden.emit(key)
			queue_redraw()
	_start_painting()
	var until := Time.get_ticks_usec() + BUDGET_USEC
	while Time.get_ticks_usec() < until:
		if not _painting.is_empty():
			var key := _nearest(_painting.keys(), view_m.get_center())
			if (_painting[key] as ChunkPainter).step(ROWS_PER_CHECK):
				_show(key)
		elif _section.busy():
			if _section.step(ROWS_PER_CHECK) != SectionField.NONE:
				_start_painting()
		else:
			break


## Chunks on show, for tests and the debug overlay.
func shown_keys() -> Array:
	return _shown.keys()


func _draw() -> void:
	for entry: Array in _shown.values():
		draw_texture(entry[0], (entry[1] as Rect2).position)


## Every built chunk not shown or being painted starts painting (chunks a
## query built at once, too).
func _start_painting() -> void:
	for key: Vector2i in _section.built_keys():
		if not _shown.has(key) and not _painting.has(key):
			var area := _section.chunk_rect(key)
			_painting[key] = ChunkPainter.new(_section.chunk(key), area, _clear, _bank_look != null, hash(key), _bank_look)


func _show(key: Vector2i) -> void:
	var painter: ChunkPainter = _painting[key]
	_painting.erase(key)
	var area := _section.chunk_rect(key)
	_shown[key] = [painter.ground, Rect2(WorldScale.vec_to_px(area.position), WorldScale.vec_to_px(area.size))]
	chunk_shown.emit(key, _section.chunk(key), area, painter)
	painter.free()
	queue_redraw()


## Painters never join the tree, so free the ones still working.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for p: ChunkPainter in _painting.values():
			p.free()
		_painting.clear()


func _nearest(keys: Array, to: Vector2) -> Vector2i:
	var best: Vector2i = keys[0]
	for key: Vector2i in keys:
		if _section.chunk_rect(key).get_center().distance_squared_to(to) \
				< _section.chunk_rect(best).get_center().distance_squared_to(to):
			best = key
	return best


func _to_m(r: Rect2) -> Rect2:
	return Rect2(WorldScale.vec_to_m(r.position), WorldScale.vec_to_m(r.size))
