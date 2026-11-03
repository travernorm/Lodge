class_name RiverFeature
extends Resource
## One thing on the riverbed or bank: a boulder, a log, an eddy, a gravel bar.
## A Stretch lists its features as data (Stretch.features), and the river field
## runs them in order without knowing any kind by name (REQ-0004 C3). A new
## kind is a new script in scripts/river/features/ that overrides the hooks it
## needs; the rest do nothing.
##
## Everything is in metres. Features are shared data, so the hooks never write
## to the feature: anything worked out per build goes in the value prepare()
## returns, which the field hands back to swirl().
##
## How the field uses them, per wet cell, after laying the channel:
##   v = shape_flow(...) for every feature in order (obstacles bend the current)
##   v = v * product of calm(...) + sum of swirl(...)

## Called once per build, after the channel is laid. Returns a number the field
## keeps for this feature and passes to swirl() (an eddy's turning direction).
func prepare(_field: RiverField) -> float:
	return 0.0


## True where the feature is solid (no water, no fish, the fly can't land).
func blocks(_p: Vector2) -> bool:
	return false


## Bends the current `v` (m/s) at `p`. Called in list order.
func shape_flow(_p: Vector2, v: Vector2) -> Vector2:
	return v


## How much of the main current is left at `p` (0..1). Multiplied together.
func calm(_p: Vector2) -> float:
	return 1.0


## Flow (m/s) the feature adds at `p`, on top of the calmed current. `state` is
## what prepare() returned.
func swirl(_p: Vector2, _state: float) -> Vector2:
	return Vector2.ZERO


## Points (m) that must be in the river for the feature to make sense. The data
## test checks each stretch's features against them.
func river_points() -> PackedVector2Array:
	return PackedVector2Array()


## The outline (m) a view can draw for a kind with no art of its own. Empty
## means nothing to draw (an eddy shows in the water itself).
func footprint() -> PackedVector2Array:
	return PackedVector2Array()
