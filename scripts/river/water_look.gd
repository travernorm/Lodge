@tool
class_name WaterLook
extends Resource
## How the river's water is painted: three textures (deep, mid, white water)
## and the numbers that decide which one shows where. WaterView paints them
## onto the river from the RiverField, so the deep texture always sits on the
## real deep water and the white water on the real fast water.
##
## Edit a look in the Inspector (data/looks/*.tres). Drag a PNG into a texture
## slot to swap it. Textures repeat, so make them seamless. Changes show live in
## the editor viewport when scenes/main.tscn is open.

## Slow, deep water: pools, the outside of bends, the slot behind a boulder.
@export var deep: Texture2D:
	set(v):
		deep = v
		emit_changed()
## Everything between deep and white.
@export var mid: Texture2D:
	set(v):
		mid = v
		emit_changed()
## Fast water: riffles and the tongue of a run.
@export var white: Texture2D:
	set(v):
		white = v
		emit_changed()

@export_group("Tints")
## Each texture is multiplied by its tint. White leaves it as drawn.
@export var deep_tint := Color.WHITE:
	set(v):
		deep_tint = v
		emit_changed()
@export var mid_tint := Color.WHITE:
	set(v):
		mid_tint = v
		emit_changed()
@export var white_tint := Color.WHITE:
	set(v):
		white_tint = v
		emit_changed()
## Colour mixed in where the water thins out toward the bank.
@export var shallow_tint := Color("7cc0dc"):
	set(v):
		shallow_tint = v
		emit_changed()

@export_group("Palette")
## Water colour by depth: the left end is the edge, the right end the deepest
## water. Empty = the textures keep their own colours (the first look).
@export var palette: Gradient:
	set(v):
		if palette != null and palette.changed.is_connected(emit_changed):
			palette.changed.disconnect(emit_changed)
		palette = v
		if palette != null:
			palette.changed.connect(emit_changed)
		emit_changed()
## With a palette: how much the textures' light and dark pattern shows on top
## of the palette colour. 0 = flat palette, 1 = the full pattern.
@export_range(0.0, 2.0, 0.01) var texture_detail := 1.0:
	set(v):
		texture_detail = v
		emit_changed()
## How much the darker parts of the white water let the water below show
## through. 0 = solid white water (the first look), 1 = only the bright crests.
@export_range(0.0, 1.0, 0.01) var wash_clear := 0.0:
	set(v):
		wash_clear = v
		emit_changed()

@export_group("Where each texture shows")
## Depth (0 = dry, 1 = deepest in the stretch) where deep water takes over.
@export_range(0.0, 1.0, 0.01) var deep_start := 0.6:
	set(v):
		deep_start = v
		emit_changed()
## How gradual the change from mid to deep is. 0 = a hard line.
@export_range(0.0, 0.5, 0.01) var deep_softness := 0.18:
	set(v):
		deep_softness = v
		emit_changed()
## Speed (fraction of the fastest water) where white water takes over.
@export_range(0.0, 1.5, 0.01) var white_start := 0.7:
	set(v):
		white_start = v
		emit_changed()
@export_range(0.0, 0.5, 0.01) var white_softness := 0.12:
	set(v):
		white_softness = v
		emit_changed()
## Depth below which the shallow tint fades in.
@export_range(0.0, 0.5, 0.01) var shallow_depth := 0.12:
	set(v):
		shallow_depth = v
		emit_changed()
## How strong the shallow tint is at the very edge. 0 = off.
@export_range(0.0, 1.0, 0.01) var shallow_amount := 0.35:
	set(v):
		shallow_amount = v
		emit_changed()

@export_group("Riverbed")
## Depth where the bed (sand and stones) has faded from view. Clear water
## shows the bed further out.
@export_range(0.0, 1.0, 0.01) var bed_depth := 0.35:
	set(v):
		bed_depth = v
		emit_changed()
## Sand seen through the shallows.
@export var sand_tint := Color("d8cc9c"):
	set(v):
		sand_tint = v
		emit_changed()
## 0 = no sand.
@export_range(0.0, 1.0, 0.01) var sand_amount := 0.0:
	set(v):
		sand_amount = v
		emit_changed()
## Stones on the bed are the water colour times this tint.
@export var stone_tint := Color("6f8f99"):
	set(v):
		stone_tint = v
		emit_changed()
## 0 = no stones.
@export_range(0.0, 1.0, 0.01) var stone_amount := 0.0:
	set(v):
		stone_amount = v
		emit_changed()
## Typical stone spacing, in metres. Stones are up to about half this wide.
@export_range(0.25, 5.0, 0.05) var stone_size_m := 1.0:
	set(v):
		stone_size_m = v
		emit_changed()
## Share of the bed that has a stone. 0 = none, 1 = cobbles everywhere.
@export_range(0.0, 1.0, 0.01) var stone_density := 0.5:
	set(v):
		stone_density = v
		emit_changed()

@export_group("Foam")
## Colour of the foam lines along the banks and around rocks.
@export var foam_tint := Color("e6f4f8"):
	set(v):
		foam_tint = v
		emit_changed()
## Foam where the water meets the bank. 0 = off.
@export_range(0.0, 1.0, 0.01) var bank_foam := 0.0:
	set(v):
		bank_foam = v
		emit_changed()
## Width of the bright bank line, in metres. A soft glow runs about three
## times further out.
@export_range(0.0, 2.0, 0.05) var bank_foam_width_m := 0.35:
	set(v):
		bank_foam_width_m = v
		emit_changed()
## Foam ringing boulders and logs. 0 = off.
@export_range(0.0, 1.0, 0.01) var rock_foam := 0.0:
	set(v):
		rock_foam = v
		emit_changed()
@export_range(0.0, 2.0, 0.05) var rock_foam_width_m := 0.3:
	set(v):
		rock_foam_width_m = v
		emit_changed()
## How quickly the foam lines surge in and out, in waves per second.
@export_range(0.0, 3.0, 0.05) var foam_surge := 0.6:
	set(v):
		foam_surge = v
		emit_changed()

@export_group("Edges")
## How much the borders between textures wobble. 0 = smooth contour lines.
@export_range(0.0, 0.5, 0.01) var edge_noise := 0.12:
	set(v):
		edge_noise = v
		emit_changed()
## Size of the wobble, in metres.
@export_range(0.25, 20.0, 0.25) var edge_noise_size_m := 3.0:
	set(v):
		edge_noise_size_m = v
		emit_changed()
## On: borders and motion use a pixel checkerboard (crisp pixel art).
## Off: textures blend smoothly.
@export var dither := false:
	set(v):
		dither = v
		emit_changed()

@export_group("Motion")
## How fast the textures travel with the current. 0 = still, 1 = at the
## water's real speed.
@export_range(0.0, 2.0, 0.01) var motion := 0.35:
	set(v):
		motion = v
		emit_changed()
## Seconds before the moving texture quietly resets. Longer = smoother but
## the texture stretches more in fast water.
@export_range(0.5, 10.0, 0.1) var motion_cycle := 3.0:
	set(v):
		motion_cycle = v
		emit_changed()


## Whether every texture slot is filled.
func is_complete() -> bool:
	return deep != null and mid != null and white != null
