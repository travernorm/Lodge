class_name AnglerView
extends Node2D
## Draws the angler: Traver's 8-view sprite of the man in waders, turned the
## way the angler faces, and the rod from hand to tip. Its owner (the stream
## scene) calls show_angler() each time it draws. Reads, changes nothing (a
## layer 4 view).
##
## The sheet (`assets/angler/idle.png`) is one row of 8 square views in the
## same order as the fly sheets: S, SE, E, NE, N, NW, W, SW, the way the angler
## faces on screen. Facing the water across the test screen shows his back.
##
## While he moves he walks: `assets/angler/walk.png` holds one row of frames per
## direction (rows in the same S..SW order), and he faces the way he is going.
## The frames step with the distance walked, not the clock, so his feet keep
## pace with the ground at any speed. When he stops he turns back to the water
## and stands in his idle view.
##
## The views were painted at 48 px and are drawn at half size, sampled with
## mipmaps (the sheet is imported with mipmaps on) so the detail stays clean.

## How big one view (one square cell of the sheet) is drawn, in screen pixels.
## 24 = half the painted 48 px, which makes him about 23 px tall.
const DRAW_PX := 24.0
const COL_ROD := Color("e8d8a8")
## How far he walks (screen px) in one full cycle of the walk frames (two steps).
const WALK_CYCLE_PX := 32.0

## The angler's views. Point this at a new sheet in the same layout to swap the art.
@export var sheet: Texture2D = preload("res://assets/angler/idle.png")
## His walk: one row of square frames per view, in the same order as `sheet`.
@export var walk_sheet: Texture2D = preload("res://assets/angler/walk.png")

var _facing := FlyView.Facing.NORTH
var _feet := Vector2.ZERO
var _shown := false
var _walked := 0.0  # px since he started walking; 0 while standing
var _hand := Vector2.ZERO
var _tip := Vector2.ZERO


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## Makes an AnglerView and adds it under `parent`, drawn before the parent's
## other children so the line and the fly show over the angler.
static func add_to(parent: Node) -> AnglerView:
	var view := AnglerView.new()
	parent.add_child(view)
	parent.move_child(view, 0)
	return view


## Shows the angler standing at `feet`, facing along `toward` (screen
## direction; UP faces the top of the screen), holding the rod from `hand` to
## `tip`. All in the owner's space. If his feet moved since the last call he
## walks that way; otherwise he stands facing `toward`.
func show_angler(feet: Vector2, toward: Vector2, hand: Vector2, tip: Vector2) -> void:
	var step := feet - _feet if _shown else Vector2.ZERO
	_feet = feet
	_shown = true
	if step.length() > 0.001:
		_walked += step.length()
		_facing = FlyView.facing_for(step)
	else:
		_walked = 0.0
		_facing = FlyView.facing_for(toward)
	position = feet.floor()
	_hand = hand.floor() - position
	_tip = tip.floor() - position
	queue_redraw()


## Which view shows, for tests and the debug overlay.
func facing() -> FlyView.Facing:
	return _facing


func is_walking() -> bool:
	return _walked > 0.0


## Which walk frame shows (0 to frames - 1), or -1 while he stands.
func walk_frame() -> int:
	if not is_walking() or walk_sheet == null:
		return -1
	var frames := walk_frames(walk_sheet)
	return int(_walked / WALK_CYCLE_PX * frames) % frames


## How many frames a walk sheet holds: square cells, one row per view.
static func walk_frames(walk: Texture2D) -> int:
	return maxi(1, roundi(walk.get_width() / (walk.get_height() / float(FlyView.VIEWS))))


## The part of a walk sheet holding one frame of one view.
static func walk_rect(walk: Texture2D, facing: FlyView.Facing, frame: int) -> Rect2:
	var cell := walk.get_height() / float(FlyView.VIEWS)
	return Rect2(cell * frame, cell * int(facing), cell, cell)


## Where one view is drawn, around the feet: centred across, standing on them.
static func body_rect() -> Rect2:
	return Rect2(-DRAW_PX * 0.5, -DRAW_PX, DRAW_PX, DRAW_PX)


func _draw() -> void:
	var frame := walk_frame()
	if frame >= 0:
		draw_texture_rect_region(walk_sheet, body_rect(), walk_rect(walk_sheet, _facing, frame))
	elif sheet != null:
		draw_texture_rect_region(sheet, body_rect(), FlyView.frame_rect(sheet, _facing))
	draw_line(_hand, _tip, COL_ROD, 1.0)
