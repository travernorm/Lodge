class_name FlyPattern
extends Resource
## One fly in the fly box. Each pattern is a .tres file in data/tackle/flies/, so new
## flies are data, not code. Flies and rods are both tackle (REQ-0005).

## How the fly fishes. A rod lists the types it can throw (FlyRod.fly_types).
## Only dries fish differently today; nymph and streamer fishing come later.
enum Type { DRY, NYMPH, STREAMER }

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var body_color := Color("8a8a8a")
@export var wing_color := Color("ffffff")
@export var hackle_color := Color("8a6a4a")
@export var fly_type := Type.DRY
## The bugs this fly passes for (data/insects/). A generalist lists several,
## a specific pattern one, and an attractor lists `attractor`.
@export var imitates: Array[Insect] = []


## What it imitates, as the families for the tie-on message: "mayfly",
## "caddis", "attractor". Each family once, in order.
func kinds_text() -> String:
	var kinds := PackedStringArray()
	for insect in imitates:
		if insect != null and insect.kind != "" and not kinds.has(insect.kind):
			kinds.append(insect.kind)
	return ", ".join(kinds)


## Draws the fly as a few pixels. scale 1 is the in-world size; the HUD uses 2.
func draw_at(canvas: CanvasItem, p: Vector2, scale := 1.0) -> void:
	var q := p.floor()
	var s := scale
	canvas.draw_rect(Rect2(q + Vector2(-1, 0) * s, Vector2(3, 1) * s), hackle_color)
	canvas.draw_rect(Rect2(q + Vector2(0, 1) * s, Vector2(2, 1) * s), body_color)
	canvas.draw_rect(Rect2(q + Vector2(0, -1) * s, Vector2(1, 1) * s), wing_color)
