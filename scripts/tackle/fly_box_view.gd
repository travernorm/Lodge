class_name FlyBoxView
extends Node2D
## The fly box corner of the HUD, bottom left: a picture of the tied-on fly
## (side on, from its art) with its name beside it, and the rod above. Its owner (the
## fishing node) calls show_box() each frame; it reads the Tackle, changes
## nothing (a layer 4 view).

## The fly's picture: one view of its sheet drawn this big, in screen pixels.
const ICON_PX := 32.0
const MARGIN := 4.0
const COL_PANEL := Color(0, 0, 0, 0.55)
const COL_TEXT := Color("f4efe0")
const COL_DIM := Color(0.96, 0.94, 0.88, 0.6)

var _tackle: Tackle
var _view := Vector2(320, 200)
var _icon: FlyView


func _init() -> void:
	_icon = FlyView.add_to(self, ICON_PX, 3.0)


## Draws the box for `tackle` on a screen of `view` pixels whose top left is
## at `origin` in the owner's space.
func show_box(tackle: Tackle, origin: Vector2, view: Vector2) -> void:
	_tackle = tackle
	_view = view
	position = origin.floor()
	queue_redraw()


func _draw() -> void:
	if _tackle == null:
		return
	var font := ThemeDB.fallback_font
	var fly := _tackle.fly()
	var fly_name := fly.display_name if fly != null else "No fly for this rod"
	var icon := Rect2(MARGIN, _view.y - MARGIN - ICON_PX, ICON_PX, ICON_PX)
	draw_rect(icon, COL_PANEL)
	_icon.show_fly(fly, icon.get_center(), Vector2.LEFT)
	var x := icon.end.x + 2.0
	var name_w := font.get_string_size(fly_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var box := Rect2(x, icon.end.y - 13.0, name_w + 6.0, 13.0)
	draw_rect(box, COL_PANEL)
	draw_string(font, box.position + Vector2(3, 10), fly_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_TEXT)
	if _tackle.rod() != null:
		draw_string(font, icon.position + Vector2(0, -3), "%s  (Y fly, L2 rod)" % _tackle.rod().display_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_DIM)
