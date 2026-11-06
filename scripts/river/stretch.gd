@tool
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

## The section's name, shown when the angler arrives (REQ-0014): "Upper Fall".
@export var display_name := ""
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
## What's on the bed and banks, in order: boulders, fallen logs, eddies,
## gravel bars ... (RiverFeature, one script per kind in
## scripts/river/features/). A new feature here is one more entry.
@export var features: Array[RiverFeature] = []
## Where the angler starts (m), on dry land.
@export var angler_start := Vector2(10, 5)
## The spawn table (REQ-0007): which species live here, how common each is,
## and when. FishGenerator picks each fish from it.
@export var spawn: Array[SpawnEntry] = []
## How rich the water is: fish per 100 m of river, measured along the
## centreline inside the map.
@export_range(0.1, 20.0) var fish_per_100m := 2.7
## The insects in this water, and when each one hatches.
@export var hatches: Array[HatchEntry] = []
## Build the river in chunks around the camera (REQ-0014, SectionField)
## instead of all at load: for long sections like the Upper Fall. The river
## importer sets it for every section it writes.
@export var streamed := false
## Spring-fed water stays in the 40s and 50s all year instead of following
## the air (REQ-0007).
@export var spring_fed := false


## How many fish the stretch holds: fish_per_100m over the river's length.
func fish_count() -> int:
	return roundi(fish_per_100m * river_length_m() / 100.0)


## Length (m) of the centreline inside the map.
func river_length_m() -> float:
	var bounds := Rect2(Vector2.ZERO, size_m)
	var total := 0.0
	for i in range(1, centreline.size()):
		var a := centreline[i - 1]
		var b := centreline[i]
		var steps := maxi(ceili(a.distance_to(b) / 0.5), 1)
		for k in steps:
			var mid := a.lerp(b, (k + 0.5) / steps)
			if bounds.has_point(mid):
				total += a.distance_to(b) / steps
	return total


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
