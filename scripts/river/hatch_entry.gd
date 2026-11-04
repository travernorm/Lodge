class_name HatchEntry
extends Resource
## One line of a stretch's hatch table (Stretch.hatches, REQ-0007): a bug that
## lives in this water, when it comes off and how thick. The insect itself
## says nothing about any place, so the same bug can hatch differently on
## every river (R12). FishGenerator decides which entries are on today.

@export var insect: Insect
## When in the year it hatches. Empty means all year.
@export var window: SeasonWindow
## The time slots it comes off in.
@export_flags("Dawn", "Morning", "Noon", "Afternoon", "Dusk", "Night") var slots := 0b111111
## The weathers it hatches in (Overcast only, for a blue-winged olive).
@export_flags("Sunny", "Overcast", "Rain", "Snow", "Storm") var weathers := 0b11111
## How thick the hatch is, 0 to 1.
@export_range(0.0, 1.0) var strength := 0.5


## True when this hatch is coming off in `c`.
func is_on(c: Conditions) -> bool:
	return insect != null and SeasonWindow.allows(window, c.season, c.day) \
		and (slots & (1 << c.slot)) != 0 and (weathers & (1 << c.weather)) != 0
