@tool
class_name GrassPatch
extends RiverFeature
## Tall grass on the bank (REQ-0012): an oval of land where clumps grow. It
## doesn't change the water, and grass never grows on water or right at its
## edge, so a patch can overlap the bank loosely. GrassView draws it with the
## scene's GrassLook; the clumps themselves come from GrassField.

@export var centre := Vector2.ZERO
## Half the patch's width and height (m).
@export var radii := Vector2(4, 2)
## Clumps per square metre, before the look's density.
@export_range(0.1, 4.0) var density := 1.0


static func make(p_centre: Vector2, p_radii: Vector2, p_density := 1.0) -> GrassPatch:
	var g := GrassPatch.new()
	g.centre = p_centre
	g.radii = p_radii
	g.density = p_density
	return g


func contains(p: Vector2) -> bool:
	var d := (p - centre) / Vector2(maxf(radii.x, 0.01), maxf(radii.y, 0.01))
	return d.length_squared() <= 1.0


func bounds() -> Rect2:
	return Rect2(centre - radii, radii * 2.0)
