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
