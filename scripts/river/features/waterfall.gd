@tool
class_name Waterfall
extends RiverFeature
## A waterfall across the river (REQ-0014): the lip runs bank to bank, the
## water falls over it into white water and a plunge pool below. Everything
## from the falling sheet upstream (the cliff, the river above it) is solid:
## no walking, no fly landing and no fish there. The plunge pool's depth comes
## from the river's depth keys; the white water is drawn by the river view.
## Placeholder art until Traver's falls arrive.

## How far (m) below the lip the falling sheet lands: solid down to here.
const FALL_M := 1.5
## How far (m) the cliff reaches past each end of the lip, and upstream.
const CLIFF_SIDE_M := 30.0
const CLIFF_UP_M := 200.0

## The lip's ends (m), each on a bank, and which way the river runs over it.
@export var a := Vector2.ZERO
@export var b := Vector2(1, 0)
@export var down := Vector2.DOWN
## How far (m) the white water reaches below the lip.
@export_range(1.0, 40.0) var foam_m := 8.0


## The falling water, the cliff and the river above.
func blocks(p: Vector2) -> bool:
	var rel := p - a.lerp(b, 0.5)
	var along := rel.dot(down)
	var across := absf(rel.dot(Vector2(-down.y, down.x)))
	return along < FALL_M and along > -CLIFF_UP_M and across < a.distance_to(b) * 0.5 + CLIFF_SIDE_M


## Only its solid part matters to the water: the field reads that through
## blocks(), so it never changes the current itself.
func reach() -> Rect2:
	return Rect2()


## The white water just below the falling sheet is in the river.
func river_points() -> PackedVector2Array:
	return PackedVector2Array([a.lerp(b, 0.5) + down * (FALL_M + 1.0)])


## The white water below the lip, for the view and the plate.
func footprint() -> PackedVector2Array:
	return PackedVector2Array([a, b, b + down * foam_m, a + down * foam_m])
