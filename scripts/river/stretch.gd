class_name Stretch
extends Resource
## One stretch of river, as data (ARCHITECTURE.md step F, REQ-0002).
##
## The river is drawn along a centreline that can wind in any direction. The
## river field (scripts/river/river_field.gd) turns this into current, depth,
## seams and trout lies: deep, fast water swings to the outside of every bend
## (the cut bank), and the inside shallows into a gravel point bar.
##
## Everything is in metres. The world's origin is the stretch's top-left corner.

## Size of the playable world (m). One screen is 40 m by 25 m.
@export var size_m := Vector2(120, 75)
## Where the river runs, upstream first (m). It can start and end off the map.
@export var centreline := PackedVector2Array()
## Half the river's width (m): 8 m is a 16 m river, bank to bank.
@export var half_width := 8.0
## How deep the thalweg is along the river: x = distance along it (0 at the
## top of the centreline, 1 at the bottom), y = depth (1 = deepest). Linear
## between keys.
@export var depth_keys := PackedVector2Array([Vector2(0, 0.5), Vector2(1, 0.5)])
## How hard bends push the thalweg toward the outside bank. 1 is natural.
@export var bend_shift := 1.0
## Boulders: x, y = centre, z = radius (m).
@export var rocks: Array[Vector3] = []
## Fallen logs: x, y = one end, z, w = the other end (m). They slow the water
## beside them.
@export var logs: Array[Vector4] = []
## Eddies: x, y = centre, z = radius (m), w = strength (peak swirl speed as a
## fraction of RiverField.WATER_SPEED). The water in them circulates back
## upstream along the bank.
@export var eddies: Array[Vector4] = []
## Extra gravel on the bank: x, y = centre, z = radius (m).
@export var gravel: Array[Vector3] = []
## Where the angler starts (m), on dry land.
@export var angler_start := Vector2(10, 5)
## The spawn table: which species live here and how many. Each fish takes its
## own lie from the river field.
@export var spawn: Array[SpawnEntry] = []


## One species per fish, in spawn-table order: each entry repeated `count`
## times.
func stocked() -> Array[FishSpecies]:
	var out: Array[FishSpecies] = []
	for entry in spawn:
		if entry == null or entry.species == null:
			continue
		for i in entry.count:
			out.append(entry.species)
	return out


## Thalweg depth (0..1) at fraction `u` along the river.
func depth_at_fraction(u: float) -> float:
	if depth_keys.is_empty():
		return 0.5
	if u <= depth_keys[0].x:
		return depth_keys[0].y
	for i in range(1, depth_keys.size()):
		var b := depth_keys[i]
		if u <= b.x:
			var a := depth_keys[i - 1]
			return lerpf(a.y, b.y, (u - a.x) / maxf(b.x - a.x, 0.0001))
	return depth_keys[-1].y
