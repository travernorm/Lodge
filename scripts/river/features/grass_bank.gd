@tool
class_name GrassBank
extends GrassPatch
## Tall grass along the whole river (REQ-0012): every bit of land within
## `width_m` of the water, on both banks, minus the gravel. One entry dresses
## a stretch's banks; GrassPatch ovals add meadows beyond it. Its centre and
## radii are unused.

## How far back from the water the grass reaches (m).
@export_range(1.0, 40.0) var width_m := 10.0


static func along(p_width: float, p_density := 1.0) -> GrassBank:
	var g := GrassBank.new()
	g.width_m = p_width
	g.density = p_density
	return g


func area(world: Rect2) -> Rect2:
	return world


func grows_at(_p: Vector2, from_water: float) -> bool:
	return from_water <= width_m
