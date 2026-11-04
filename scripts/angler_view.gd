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
## The views were painted at 48 px and are drawn at half size, sampled with
## mipmaps (the sheet is imported with mipmaps on) so the detail stays clean.

## How big one view (one square cell of the sheet) is drawn, in screen pixels.
## 24 = half the painted 48 px, which makes him about 23 px tall.
const DRAW_PX := 24.0
const COL_ROD := Color("e8d8a8")

## The angler's views. Point this at a new sheet in the same layout to swap the art.
@export var sheet: Texture2D = preload("res://assets/angler/idle.png")

var _facing := FlyView.Facing.NORTH
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
## `tip`. All in the owner's space.
func show_angler(feet: Vector2, toward: Vector2, hand: Vector2, tip: Vector2) -> void:
	position = feet.floor()
	_facing = FlyView.facing_for(toward)
	_hand = hand.floor() - position
	_tip = tip.floor() - position
	queue_redraw()


## Which view shows, for tests and the debug overlay.
func facing() -> FlyView.Facing:
	return _facing


## Where one view is drawn, around the feet: centred across, standing on them.
static func body_rect() -> Rect2:
	return Rect2(-DRAW_PX * 0.5, -DRAW_PX, DRAW_PX, DRAW_PX)


func _draw() -> void:
	if sheet != null:
		draw_texture_rect_region(sheet, body_rect(), FlyView.frame_rect(sheet, _facing))
	draw_line(_hand, _tip, COL_ROD, 1.0)
