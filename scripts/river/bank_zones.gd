class_name BankZones
extends RefCounted
## Where each kind of shoreline goes (REQ-0013). Rules only: BankView bakes
## these widths into a texture per field cell and its shader does the same
## comparison as zone() per pixel, with a ragged-edge wobble added.

enum Zone { GROUND, WET, GRAVEL, SAND, FACE }


## How tall the cut bank face is here (m): none on a straight bank or the
## inside of a bend, full height on a tight outside bend.
static func face_m(bend: float, look: BankLook) -> float:
	if look.cut_bank == null:
		return 0.0
	return look.face_height_m * smoothstep(look.cut_bend_start, maxf(look.cut_bend_full, look.cut_bend_start + 0.01), bend)


## How far from the water (m) gravel reaches here: a strip along a straight
## bank, widening into a point bar on the inside of a bend.
static func gravel_m(bend: float, look: BankLook) -> float:
	return look.gravel_width_m + look.point_bar_m * maxf(-bend, 0.0)


## Gravel reach (m) with a gravel bar: inside the bar, gravel reaches past
## this point by how far the point is inside the bar's edge.
static func with_bar(gravel: float, shore: float, inside_bar_m: float) -> float:
	return maxf(gravel, shore + inside_bar_m) if inside_bar_m > 0.0 else gravel


## Which ground a land point shows: `shore` = metres from the water, `face` and
## `gravel` = the widths here. The face wins, then wet, gravel, sand, ground.
static func zone(shore: float, face: float, gravel: float, look: BankLook) -> Zone:
	if face >= look.min_face_m and shore < face:
		return Zone.FACE
	if shore < look.wet_width_m:
		return Zone.WET
	if shore < gravel - look.sand_width_m:
		return Zone.GRAVEL
	if shore < gravel:
		return Zone.SAND
	return Zone.GROUND
