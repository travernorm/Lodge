class_name TieredCastRules
extends CastRules
## "Count the false casts": one steady tempo, and distance comes in clear steps.
##
##   no false casts   -> Short
##   one false cast   -> Middle
##   two or more      -> Long
##
## A false cast only climbs a step if it was clean enough. Timing quality still
## matters on delivery: a sloppy final cast falls short of its step.

## Seconds to hold every stroke, whatever the line length.
@export var tempo := 0.42
## Fraction of the tempo counted as perfect / okay either side of it.
@export var perfect_fraction := 0.15
@export var ok_fraction := 0.38
## Line out (px) at each step: Short, Middle, Long.
@export var step_lengths := PackedFloat32Array([36.0, 66.0, 100.0])
## A false cast must average at least this quality to climb a step.
@export var climb_quality := 0.55
## Fraction of the step's length a poor delivery still reaches.
@export var worst_reach := 0.7

var _step := 0


func start_line(_model: CastModel) -> float:
	_step = 0
	return step_lengths[0]


func stroke_ideal(_model: CastModel) -> float:
	return tempo


func perfect_window(_model: CastModel) -> float:
	return tempo * perfect_fraction


func ok_window(_model: CastModel) -> float:
	return tempo * ok_fraction


func after_false_cast(model: CastModel, q: float) -> String:
	# Re-sync from line_out in case the cast started from a pick-up.
	_step = _step_for(model.line_out)
	if q < climb_quality:
		return "Sloppy false cast. Still %s." % CastRules.distance_label(step_lengths[_step])
	if _step >= step_lengths.size() - 1:
		return "Holding at Long"
	_step += 1
	model.line_out = step_lengths[_step]
	return "Step up: %s" % CastRules.distance_label(step_lengths[_step])


func delivery_reach(model: CastModel, q: float) -> float:
	return model.line_out * lerpf(worst_reach, 1.0, q)


func _step_for(line: float) -> int:
	var best := 0
	for i in step_lengths.size():
		if line >= step_lengths[i] - 0.5:
			best = i
	return best
