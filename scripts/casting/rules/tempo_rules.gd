class_name TempoCastRules
extends CastRules
## "Find your tempo": your first back cast sets the beat, and every stroke after
## is judged on how well it matches that beat, not on a fixed clock. Any tempo
## inside the allowed range works, so you can cast fast and snappy or slow and
## lazy. Each consistent false cast adds line; a broken rhythm adds little.
##
## The beat slowly follows your good strokes, the way a real caster settles in.

@export var min_tempo := 0.25
@export var max_tempo := 0.75
## Used for the meter before your first stroke sets the beat.
@export var default_tempo := 0.42
## Fraction of your tempo counted as perfect / okay either side of it.
@export var perfect_fraction := 0.12
@export var ok_fraction := 0.3
@export var line_start := 26.0
@export var line_max := 118.0
## Line a perfectly consistent false cast adds.
@export var line_gain := 18.0
## How much of each good stroke's length blends into the beat (0 = fixed beat).
@export var follow := 0.25
@export var worst_reach := 0.6

## The current beat in seconds, or 0 before the first stroke sets it.
var beat := 0.0


func start_line(_model: CastModel) -> float:
	beat = 0.0
	return line_start


func stroke_ideal(_model: CastModel) -> float:
	return beat if beat > 0.0 else default_tempo


func perfect_window(model: CastModel) -> float:
	return stroke_ideal(model) * perfect_fraction


func ok_window(model: CastModel) -> float:
	return stroke_ideal(model) * ok_fraction


func score_stroke(model: CastModel, elapsed: float, stroke_name: String) -> Array:
	if beat <= 0.0:
		# The first back cast sets the beat. It only has to be in range.
		if elapsed < min_tempo:
			beat = min_tempo
			return [0.5, "Rushed the first back cast. Let the line straighten."]
		if elapsed > max_tempo:
			beat = max_tempo
			return [0.5, "First back cast dragged on too long."]
		beat = elapsed
		return [1.0, "Tempo set: %d ms" % roundi(elapsed * 1000.0)]
	var result := super.score_stroke(model, elapsed, stroke_name)
	if result[0] >= 1.0:
		beat = clampf(lerpf(beat, elapsed, follow), min_tempo, max_tempo)
	elif result[1] != "":
		result[1] = ("Rushed the %s cast. Keep the beat." if elapsed < beat else "Lagged on the %s cast. Keep the beat.") % stroke_name
	return result


func after_false_cast(model: CastModel, q: float) -> String:
	model.line_out = minf(model.line_out + line_gain * q * q, line_max)
	return "In rhythm" if q >= 0.95 else ""


func delivery_reach(model: CastModel, q: float) -> float:
	return model.line_out * lerpf(worst_reach, 1.0, q)
