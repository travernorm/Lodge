class_name FlyView
extends Node2D
## Draws one fly: the tied-on fly on the water, or its picture in the fly box.
## Its owner (the cast or fishing node) calls show_fly() each frame it wants the
## fly seen, and clear() otherwise. Reads data, changes none (a layer 4 view).
##
## Flies with art (FlyPattern.sprite_sheet) draw one of its 8 views, picked by
## the way the fly faces. On the water a fly faces the angler: the hook eye, its
## head, points back up the line at the rod tip. A fly with no art yet draws as
## a few coloured pixels.
##
## The sheets are drawn smaller than they were painted, so this node samples
## them with mipmaps (each sheet is imported with mipmaps on) to keep the
## detail from breaking up into noise.

## Views in a sheet, left to right, as the fly's head points on screen.
enum Facing { SOUTH, SOUTH_EAST, EAST, NORTH_EAST, NORTH, NORTH_WEST, WEST, SOUTH_WEST }
const VIEWS := 8

## How big a fly on the water is drawn: one view (one square cell of its
## sheet, trimmed close around the fly) in screen pixels.
const WATER_PX := 10.0

## How big one view is drawn, in screen pixels.
@export var size_px := WATER_PX
## Pixel size of the coloured-pixel stand-in for a fly with no art.
@export var fallback_scale := 1.0

var _fly: FlyPattern
var _facing := Facing.SOUTH


func _init(p_size_px := WATER_PX, p_fallback_scale := 1.0) -> void:
	size_px = p_size_px
	fallback_scale = p_fallback_scale
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## Makes a FlyView and adds it under `parent`, which owns it from then on.
static func add_to(parent: Node, p_size_px := WATER_PX, p_fallback_scale := 1.0) -> FlyView:
	var view := FlyView.new(p_size_px, p_fallback_scale)
	parent.add_child(view)
	return view


## Shows `fly` centred at `at` (in the owner's space), its head pointing along
## `toward` (screen direction; DOWN faces the bottom of the screen).
func show_fly(fly: FlyPattern, at: Vector2, toward := Vector2.DOWN) -> void:
	var facing := facing_for(toward)
	if fly == _fly and facing == _facing and at.floor() == position and visible:
		return
	_fly = fly
	_facing = facing
	position = at.floor()
	visible = fly != null
	queue_redraw()


func clear() -> void:
	visible = false


## Which view to draw for a head pointing along `toward` (screen space, y down).
static func facing_for(toward: Vector2) -> Facing:
	if toward.length() < 0.001:
		return Facing.SOUTH
	# SOUTH is +y (angle PI/2); each later view turns 45 degrees anticlockwise on screen.
	var steps := roundi((PI / 2.0 - toward.angle()) / (PI / 4.0))
	return posmod(steps, VIEWS) as Facing


## The part of `sheet` holding one view: square cells in a row.
static func frame_rect(sheet: Texture2D, facing: Facing) -> Rect2:
	var cell := float(sheet.get_height())
	return Rect2(cell * int(facing), 0.0, cell, cell)


func _draw() -> void:
	if _fly == null:
		return
	if _fly.sprite_sheet != null:
		var half := Vector2(size_px, size_px) * 0.5
		draw_texture_rect_region(_fly.sprite_sheet, Rect2(-half, half * 2.0), frame_rect(_fly.sprite_sheet, _facing))
		return
	var s := fallback_scale
	draw_rect(Rect2(Vector2(-1, 0) * s, Vector2(3, 1) * s), _fly.hackle_color)
	draw_rect(Rect2(Vector2(0, 1) * s, Vector2(2, 1) * s), _fly.body_color)
	draw_rect(Rect2(Vector2(0, -1) * s, Vector2(1, 1) * s), _fly.wing_color)
