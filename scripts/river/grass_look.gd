@tool
class_name GrassLook
extends Resource
## How the tall grass looks and moves (REQ-0012). GrassView draws the clumps
## that GrassField grows in each GrassPatch, bent by the wind and the angler.
## Traver tunes it in the Inspector, like the water look.
##
## Art: `clumps` are Traver's clump sprites, drawn with their bottom middle on
## the clump's root. With none set, a plain placeholder clump of blades in
## `base_tint` and `tip_tint` stands in.

## Clump sprites; each clump picks one. Empty = placeholder blades.
@export var clumps: Array[Texture2D] = []
## Optional sprite for a clump that has been walked flat (variant B).
@export var flat_clump: Texture2D
## Placeholder blades: colour at the root and at the tip.
@export var base_tint := Color("244027")
@export var tip_tint := Color("8db63e")

@export_group("Size")
## Clump height and width (m); the placeholder uses these, sprites their own size.
@export_range(0.2, 3.0) var height_m := 1.2
@export_range(0.2, 3.0) var width_m := 0.9
## Multiplies every patch's density.
@export_range(0.1, 3.0) var density := 1.0

@export_group("Angler")
## How the grass reacts as the angler walks through (the feel experiment).
@export var push := GrassField.Push.LEAN
## How close (m) the angler must be to move a clump.
@export_range(0.2, 4.0) var push_radius_m := 1.2
## How far a clump right next to the angler leans (1 = its top moves a full height).
@export_range(0.0, 1.5) var push_lean := 0.8
## Seconds for a bent clump to swing back upright.
@export_range(0.1, 4.0) var spring_seconds := 0.8
## 0 = wobbles a long time, 1 = no overshoot.
@export_range(0.05, 1.0) var damping := 0.3
## Variant B: seconds a walked-over clump stays flat before it stands up.
@export_range(0.0, 10.0) var trail_seconds := 2.0
## Variant B: how flat a walked-over clump lies (1 = flat on the ground).
@export_range(0.0, 1.0) var flatten := 0.65
## Variant C: how hard a clump shivers as the angler brushes past.
@export_range(0.0, 3.0) var rustle := 1.0

@export_group("Wind")
## Wind per Calendar.Weather (Sunny, Overcast, Rain, Snow, Storm), 0 to 1.
@export var wind_by_weather := PackedFloat32Array([0.12, 0.22, 0.45, 0.3, 1.0])
## How far the strongest wind leans a clump (same scale as push_lean).
@export_range(0.0, 1.5) var wind_lean := 0.7
## Distance between gust bands (m) and how fast they roll downwind (m/s).
@export_range(1.0, 40.0) var gust_size_m := 9.0
@export_range(0.0, 20.0) var gust_speed_mps := 5.0
## Seconds for the wind to build from calm to a full storm.
@export_range(0.1, 20.0) var wind_ease_seconds := 3.0
