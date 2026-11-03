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
## Line out (m) at each step: Short, Middle, Long. With a rod, the last step
## is the rod's longest line instead, and no step goes past it (REQ-0005).
@export var step_lengths := PackedFloat32Array([4.5, 8.25, 12.5])
## A false cast must average at least this quality to climb a step.
@export var climb_quality := 0.55
## Fraction of the step's length a poor delivery still reaches.
@export var worst_reach := 0.7

var _step := 0


func start_line(model: CastModel) -> float:
	_step = 0
	return lengths(model)[0]


func stroke_ideal(model: CastModel) -> float:
	return tempo + _step_for(model, model.line_out) * tempo_per_step


func perfect_window(model: CastModel) -> float:
	return stroke_ideal(model) * perfect_fraction


func ok_window(model: CastModel) -> float:
	return stroke_ideal(model) * ok_fraction


func after_false_cast(model: CastModel, q: float) -> String:
	# Re-sync from line_out in case something else changed it mid-cast.
	var steps := lengths(model)
	_step = _step_for(model, model.line_out)
	if q < climb_quality:
		return "Sloppy false cast. Still %s." % CastRules.distance_label(steps[_step])
	if _step >= steps.size() - 1:
		return "Holding at %s" % CastRules.distance_label(steps[_step])
	_step += 1
	model.line_out = steps[_step]
	var label := CastRules.distance_label(steps[_step])
	if _step == steps.size() - 1 and label != CastRules.distance_label(step_lengths[_step]):
		return "Step up: %s. That's all this rod carries." % label
	return "Step up: %s" % label


func delivery_reach(model: CastModel, q: float) -> float:
	return model.line_out * lerpf(worst_reach, 1.0, q)


## Line out (m) at each step for this cast: step_lengths, with the last step
## set by the rod's longest line and no step past it.
func lengths(model: CastModel) -> PackedFloat32Array:
	var out := step_lengths.duplicate()
	var last := out.size() - 1
	var cap := model.max_line(out[last])
	for i in out.size():
		out[i] = minf(out[i], cap)
	out[last] = cap
	return out


func _step_for(model: CastModel, line: float) -> int:
	var steps := lengths(model)
	var best := 0
	for i in steps.size():
		if line >= steps[i] - 0.0625:
			best = i
	return best
