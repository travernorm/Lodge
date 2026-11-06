class_name CaughtLog
extends RefCounted
## The fish landed today, by section and lie (REQ-0014), so a fish once caught
## stays gone for the day: when its chunk comes back, and when the angler
## leaves the section and returns. A new day forgets them. The fishing
## controller owns it and hands it on to the next section's. Metres.

var _seed := 0
## [section, lie cell] -> true, for day _seed.
var _lies := {}


## The fish holding `lie` (m) in `section` on day `day_seed` was landed.
func mark(section: Stretch, lie: Vector2, day_seed: int) -> void:
	if day_seed != _seed:
		_lies.clear()
		_seed = day_seed
	_lies[[section, _cell(lie)]] = true


func has(section: Stretch, lie: Vector2, day_seed: int) -> bool:
	return day_seed == _seed and _lies.has([section, _cell(lie)])


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i((p / RiverField.CELL).round())
