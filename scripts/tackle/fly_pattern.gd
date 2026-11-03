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
## The fly's art: 8 square views in one row, its head (the hook eye) pointing
## S, SE, E, NE, N, NW, W, SW on screen (assets/flies/). FlyView draws it.
## Empty, the fly draws as a few pixels in the colours above.
@export var sprite_sheet: Texture2D


## What it imitates, as the families for the tie-on message: "mayfly",
## "caddis", "attractor". Each family once, in order.
func kinds_text() -> String:
	var kinds := PackedStringArray()
	for insect in imitates:
		if insect != null and insect.kind != "" and not kinds.has(insect.kind):
			kinds.append(insect.kind)
	return ", ".join(kinds)

