class_name CastPose
extends RefCounted
## Where the rod points at each moment of a cast, for the cast look versions
## (CastLook). Pure sums: give it the cast's state and how far through its
## stroke it is, get back the rod's tilt, its bend and its direction on screen.
## The cast controller asks it each frame; AnglerView draws the result.

## No pose: the right stick (or the drift) aims the rod.
const NONE := INF


## The rod's tilt in degrees from straight up (positive toward the target) at
## `progress` (0..1, past 1 when held late) through the current stroke, or NONE.
## `flight` is 0..1 through the fly's flight.
static func tilt(look: CastLook, state: CastModel.State, progress: float, flight: float) -> float:
	var t := _eased(look, progress)
	var late := maxf(progress - 1.0, 0.0)
	match state:
		CastModel.State.BACK:
			return lerpf(look.forward_stop_deg, look.back_stop_deg, t) - look.late_drift_deg * minf(late, 1.0)
		CastModel.State.GAP, CastModel.State.BACK_TO_FORWARD:
			return look.back_stop_deg
		CastModel.State.FORWARD:
			return lerpf(look.back_stop_deg, look.forward_stop_deg, t)
		CastModel.State.FORWARD_TO_BACK:
			return look.forward_stop_deg
		CastModel.State.FLIGHT:
			return lerpf(look.forward_stop_deg, look.follow_through_deg, clampf(flight, 0.0, 1.0))
	return NONE


## The tilt version B shows: the nearest of the look's fixed angles.
static func snapped(look: CastLook, deg: float) -> float:
	if deg == NONE or look.snap_angles_deg.is_empty():
		return deg
	var best := look.snap_angles_deg[0]
	for a in look.snap_angles_deg:
		if absf(a - deg) < absf(best - deg):
			best = a
	return best


## How far (degrees of tilt) the rod's tip lags behind its butt: the rod loads
## in the middle of a stroke and bends against the way it moves, so the tip's
## tilt is tilt() minus this.
static func bend(look: CastLook, state: CastModel.State, progress: float) -> float:
	var load := sin(PI * clampf(progress, 0.0, 1.0)) * look.max_bend_deg
	match state:
		CastModel.State.FORWARD:
			return load
		CastModel.State.BACK:
			return -load
	return 0.0


## The rod on screen for a tilt: a vector up to 1 long (times the rod's length),
## shorter where it points toward or away from the camera. `aim` is the cast's
## direction on screen, `rod_side` the angler's rod-hand side.
static func on_screen(look: CastLook, deg: float, aim: Vector2, rod_side: Vector2) -> Vector2:
	var a := deg_to_rad(deg)
	var up := cos(a)
	var v := aim * sin(a) + Vector2.UP * up * look.height_show + rod_side * up * look.side_lean
	return v.limit_length(1.0)


static func _eased(look: CastLook, progress: float) -> float:
	return ease(clampf(progress, 0.0, 1.0), look.stroke_ease)
