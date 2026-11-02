class_name TieredCastRules
extends CastRules
## "Count the false casts": a steady beat, and distance comes in clear steps.
## Each step up stretches the beat slightly, since more line takes longer to unroll.
##
##   no false casts   -> Short
##   one false cast   -> Middle
##   two or more      -> Long
##
## A false cast only climbs a step if it was clean enough. Timing quality still
## matters on delivery: a sloppy final cast falls short of its step.

## Seconds to hold each stroke at the Short step.
@export var tempo := 0.42
## Seconds the beat stretches for each step up, so a longer line has a
## slightly slower rhythm (0.42 Short, 0.47 Middle, 0.52 Long by default).
@export var tempo_per_step := 0.05
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


func stroke_ideal(model: CastModel) -> float:
	return tempo + _step_for(model.line_out) * tempo_per_step


func perfect_window(model: CastModel) -> float:
	return stroke_ideal(model) * perfect_fraction


func ok_window(model: CastModel) -> float:
	return stroke_ideal(model) * ok_fraction


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
