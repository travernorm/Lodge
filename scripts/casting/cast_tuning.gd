class_name CastTuning
extends Resource
## Tunables for the bumper casting rhythm. Open res://data/cast_tuning.tres in the
## Godot inspector to tweak the feel without touching code.
##
## A stroke's ideal length grows with the line that's out, like a real cast:
##   ideal = base_stroke_time + line_out * stroke_time_per_m
##
## Distances are in metres (REQ-0001).

@export_group("Line")
## Line out (m) when a fresh cast starts: roughly rod tip plus leader.
@export var line_start := 3.0
## Most line (m) you can carry in the air.
@export var line_max := 14.75
## Line (m) added by a false cast that only just held together.
@export var line_gain_min := 0.5
## Line (m) added by a clean false cast.
@export var line_gain_max := 2.0
## False casts averaging below this quality add no line.
@export var line_gain_threshold := 0.4

@export_group("Stroke timing")
@export var base_stroke_time := 0.25
## Extra seconds per metre of line out.
@export var stroke_time_per_m := 0.028
## +/- seconds around the ideal that count as perfect.
@export var perfect_window := 0.06
## +/- seconds around the ideal that still count as okay.
@export var ok_window := 0.16
## Seconds past the ideal before the line falls: it ticks the grass on the back
## cast, or slaps the water on the forward cast.
@export var drop_time := 0.4

@export_group("Bumper overlap")
## Overlap (seconds of both bumpers held) that feels right.
@export var overlap_good_min := 0.02
@export var overlap_good_max := 0.2
## Overlap this long throws a tailing loop. Twice this tangles the leader.
@export var tailing_overlap := 0.35
## Seconds you may let go of one bumper before pressing the other.
@export var gap_grace := 0.08

@export_group("Delivery")
## Fraction of the line that reaches out on the worst delivery.
@export var short_cast_factor := 0.55
## How far the left stick can swing the cast either side of straight across.
@export var max_aim_degrees := 50.0
## Random sideways error on a poor cast.
@export var max_scatter_degrees := 10.0
## Seconds the fly is in the air after you release L.
@export var flight_time := 0.22
## Average quality needed for each presentation.
@export var delicate_quality := 0.85
@export var fair_quality := 0.55
