class_name CastRules
extends Resource
## A "chassis" for the cast: the rules that turn your bumper rhythm into line
## and distance. CastModel runs the R/L state machine (back cast, overlap,
## forward cast, false casts, delivery) and asks its rules four questions:
##
##   start_line()        how much line is out when a cast starts
##   stroke_ideal()      how long the next stroke should be held
##   score_stroke()      how good a finished stroke was (0..1)
##   after_false_cast()  how a false cast changes the line out
##   delivery_reach()    how far the fly goes when you let go
##
## Subclasses in scripts/casting/rules/ swap these out so different rhythms can
## be tried side by side. Their numbers live in data/cast_rules/*.tres.
## This base class plays like the original "Classic" rules, driven by CastTuning.

## Shown in practice mode when you switch rules.
@export var display_name := "Classic"
@export_multiline var description := ""

## Distances (px from the rod tip) that split Short / Middle / Long.
const SHORT_MAX := 48.0
const MIDDLE_MAX := 82.0


func start_line(model: CastModel) -> float:
	return model.tuning.line_start


func stroke_ideal(model: CastModel) -> float:
	var t := model.tuning
	return t.base_stroke_time + model.line_out * t.stroke_time_per_px


## +/- seconds counted as perfect and okay for the stroke being held now.
func perfect_window(model: CastModel) -> float:
	return model.tuning.perfect_window


func ok_window(model: CastModel) -> float:
	return model.tuning.ok_window


## Quality 0..1 of a stroke that lasted `elapsed` seconds against model.phase_ideal.
## Returns [quality, message]. An empty message means nothing worth saying.
func score_stroke(model: CastModel, elapsed: float, stroke_name: String) -> Array:
	var error := elapsed - model.phase_ideal
	var q := timing_quality(error, perfect_window(model), ok_window(model))
	var msg := ""
	if q < 1.0:
		msg = ("Early on the %s cast" if error < 0.0 else "Late on the %s cast") % stroke_name
	return [q, msg]


## Called after each false cast with the average quality of that cycle.
## Returns a message, or "" for none.
func after_false_cast(model: CastModel, q: float) -> String:
	var t := model.tuning
	if q < t.line_gain_threshold:
		return "Sloppy false cast. No line gained."
	var gain := lerpf(t.line_gain_min, t.line_gain_max, inverse_lerp(t.line_gain_threshold, 1.0, q))
	model.line_out = minf(model.line_out + gain, t.line_max)
	return "Tight loop" if q >= 0.95 else ""


## px the fly travels from the rod tip on delivery, given the cast's quality.
func delivery_reach(model: CastModel, q: float) -> float:
	return model.line_out * lerpf(model.tuning.short_cast_factor, 1.0, q)


## Short / Middle / Long, for practice mode and coaching.
static func distance_label(reach: float) -> String:
	if reach <= SHORT_MAX:
		return "Short"
	if reach <= MIDDLE_MAX:
		return "Middle"
	return "Long"


## Maps a timing error (seconds) to 0..1 with a perfect band and an okay band.
static func timing_quality(error: float, perfect: float, ok: float) -> float:
	var a := absf(error)
	if a <= perfect:
		return 1.0
	if a <= ok:
		return lerpf(1.0, 0.6, (a - perfect) / (ok - perfect))
	return clampf(lerpf(0.6, 0.15, (a - ok) / (ok * 0.5)), 0.15, 0.6)
