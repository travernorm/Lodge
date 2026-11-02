class_name WorldScale
extends RefCounted
## The one place metres turn into screen pixels (REQ-0001).
##
## Rules and data work in metres and metres per second. Only drawing code and
## the stream scene's layout convert, through these helpers. At 8 px per metre
## one 320x200 screen covers 40 m by 25 m.
##
## Never instantiated: use WorldScale.PX_PER_M and the static helpers.

const PX_PER_M := 8.0


static func to_px(metres: float) -> float:
	return metres * PX_PER_M


static func to_m(pixels: float) -> float:
	return pixels / PX_PER_M


static func vec_to_px(metres: Vector2) -> Vector2:
	return metres * PX_PER_M


static func vec_to_m(pixels: Vector2) -> Vector2:
	return pixels / PX_PER_M
