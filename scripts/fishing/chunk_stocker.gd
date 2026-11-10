class_name ChunkStocker
extends RefCounted
## Stocks a streamed section chunk by chunk (REQ-0014). A section is too long
## to scan whole, so each chunk gets its fish when it comes into reach: a
## FishGenerator over that chunk's own area, seeded by the day and the chunk,
## so the same day always gives the same fish in a chunk however the angler
## walks. Fish caught today (the CaughtLog) stay gone when a chunk comes back.
## Metres.
##
## The fishing controller owns it: add() and remove() as chunks come and go,
## plans_for() and all_plans() to stock them.

var stretch: Stretch
var calendar: Calendar
## The chunks in reach: Vector2i -> [RiverField, area (Rect2, m)].
var _chunks := {}
## The fish landed today, which are not stocked again.
var caught: CaughtLog


func _init(p_stretch: Stretch, p_calendar: Calendar, p_caught: CaughtLog) -> void:
	stretch = p_stretch
	calendar = p_calendar
	caught = p_caught


func add(key: Vector2i, field: RiverField, area: Rect2) -> void:
	_chunks[key] = [field, area]


func remove(key: Vector2i) -> void:
	_chunks.erase(key)


func area_of(key: Vector2i) -> Rect2:
	return _chunks[key][1] if _chunks.has(key) else Rect2()


## The fish in one chunk for the day `c` and its seed, less those caught.
func plans_for(key: Vector2i, c: Conditions, day_seed: int) -> Array[FishPlan]:
	var out: Array[FishPlan] = []
	if not _chunks.has(key):
		return out
	var gen := FishGenerator.new(stretch, _chunks[key][0], calendar, null, _chunks[key][1])
	for plan in gen.generate(c, FishGenerator.seeded(hash([day_seed, key]))):
		if not caught.has(stretch, plan.lie, day_seed):
			out.append(plan)
	return out


## Every chunk in reach, for a new day.
func all_plans(c: Conditions, day_seed: int) -> Array[FishPlan]:
	var out: Array[FishPlan] = []
	for key: Vector2i in _chunks.keys():
		out.append_array(plans_for(key, c, day_seed))
	return out
