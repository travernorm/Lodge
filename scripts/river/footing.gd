class_name Footing
extends RefCounted
## Where the angler can stand (REQ-0014): on dry land, or on something that
## carries him over the water, like a bridge deck; never in the water (wading
## comes with REQ-0015) and never on anything solid (a boulder, a cliff above
## a waterfall). Metres.


static func can_stand(river: RiverField, p: Vector2) -> bool:
	if on_deck(river, p):
		return true
	return not river.is_solid(p) and not river.is_water(p)


## True on a feature that carries him (a bridge deck).
static func on_deck(river: RiverField, p: Vector2) -> bool:
	for f in river.features:
		if f.carries(p):
			return true
	return false
