class_name FlyRod
extends Resource
## One fly rod. Each rod is a .tres file in data/tackle/rods/, so a new rod is
## data, not code (REQ-0005). A rod shapes the cast and the fight:
##   fly_types        which flies it can throw (the fly box hides the rest)
##   max_line_m       the most line it carries, which sets the longest cast
##   forgiveness      how wide the timing windows are (1 is the baseline)
##   rated_length_in  the biggest fish it fights at full strength

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
## Rod weight, as anglers say it ("a 4-weight"). Shown, not used in the rules.
@export_range(1, 12) var weight := 5
## Which fly types it throws. Bit n is FlyPattern.Type n.
@export_flags("Dry", "Nymph", "Streamer") var fly_types := 1
## The most line (m) it can carry in the air. Replaces the casting rule set's
## own longest line, so it sets how far you can cast.
@export_range(4.0, 17.5) var max_line_m := 12.5
## Multiplies the timing windows (perfect and okay) and the good overlap band.
## Above 1 is forgiving; below 1 punishes sloppy timing.
@export_range(0.5, 2.0) var forgiveness := 1.0
## Fish up to this length (inches) fight as normal. Longer ones load the rod
## and snap the tippet sooner (FightModel.rod_load()).
@export var rated_length_in := 20.0

const TYPE_NAMES := ["dries", "nymphs", "streamers"]


## Whether this rod can throw `fly`.
func throws(fly: FlyPattern) -> bool:
	return fly != null and (fly_types & (1 << int(fly.fly_type))) != 0


## "dries, nymphs": the fly types it throws, for messages.
func types_text() -> String:
	var names := PackedStringArray()
	for i in TYPE_NAMES.size():
		if fly_types & (1 << i):
			names.append(TYPE_NAMES[i])
	return ", ".join(names)


## How it casts, in a word.
func feel_text() -> String:
	if forgiveness >= 1.15:
		return "forgiving"
	if forgiveness <= 0.85:
		return "fast"
	return "steady"


## One line for the rod message: what it throws, how far, how it feels, how big.
func stats_text() -> String:
	return "%s: %s, %d m, %s, fish to %d in" % [display_name, types_text(), floori(max_line_m), feel_text(), roundi(rated_length_in)]
