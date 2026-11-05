extends SceneTree
## Headless tests for stocking a streamed section chunk by chunk (REQ-0014,
## ChunkStocker): the same day gives the same fish in a chunk whatever order
## the chunks come in, fish caught today stay gone, the count follows the
## stretch's fish_per_100m where the water has lies (a chunk of plain water
## with none holds no fish), and the Upper Fall scene has fish in the chunks on
## screen and none in chunks it dropped.
##   godot --headless --path . --script res://tests/chunk_stock_test.gd

const UPPER_FALL := "res://data/stretches/fall_river_upper_fall.tres"
const SCENE := "res://scenes/upper_fall.tscn"
## Chunks along the river to stock.
const CHUNKS := 8
## Days for the average count.
const DAYS := 200

var _failures := 0
var _calendar: Calendar = load("res://data/calendar.tres")
var _climate: Climate = load("res://data/climates/central_oregon.tres")
var _stretch: Stretch = load(UPPER_FALL)
var _section := SectionField.new()
var _keys: Array[Vector2i] = []


func _initialize() -> void:
	_section.setup(_stretch)
	for p in _section.centre:
		var key := _section.key_of(p)
		if not key in _keys and _keys.size() < CHUNKS:
			_keys.append(key)
	_test_walk_order()
	_test_caught_stay_gone()
	_test_count()
	_test_scene_stocks.call_deferred()


func _summer_dusk() -> Conditions:
	return Conditions.at(_calendar, _climate, Calendar.Season.SUMMER, 12, Calendar.Slot.DUSK,
		Calendar.Weather.OVERCAST, 80, _stretch.spring_fed)


func _stocker(keys: Array[Vector2i]) -> ChunkStocker:
	var s := ChunkStocker.new(_stretch, _calendar)
	for key in keys:
		s.add(key, _section.chunk(key), _section.chunk_rect(key))
	return s


## Each plan as text, sorted, to compare two stockings.
func _describe(plans: Array[FishPlan]) -> Array:
	var out := plans.map(func(p: FishPlan) -> String:
		return "%s %.2f,%.2f %.2f" % [p.species.id, p.lie.x, p.lie.y, p.length_in])
	out.sort()
	return out


func _test_walk_order() -> void:
	var c := _summer_dusk()
	var down := _stocker(_keys)
	var reversed := _keys.duplicate()
	reversed.reverse()
	var up := _stocker(reversed)
	var a := _describe(down.all_plans(c, 1234))
	var b := _describe(up.all_plans(c, 1234))
	_check(not a.is_empty(), "the chunks hold fish (%d)" % a.size())
	_check(a == b, "the same day gives the same fish, walking down or up")
	var key := _keys[CHUNKS / 2]
	var once := _describe(down.plans_for(key, c, 1234))
	down.remove(key)
	down.add(key, _section.chunk(key), _section.chunk_rect(key))
	_check(once == _describe(down.plans_for(key, c, 1234)), "a chunk that comes back has the same fish")
	_check(a != _describe(down.all_plans(c, 99)), "another day gives other fish")
	var area := _section.chunk_rect(key)
	_check(down.plans_for(key, c, 1234).all(func(p: FishPlan) -> bool: return area.has_point(p.lie)),
		"a chunk's fish hold lies inside it")


func _test_caught_stay_gone() -> void:
	var c := _summer_dusk()
	var s := _stocker(_keys)
	var key := _keys[0]
	for k in _keys:
		if not s.plans_for(k, c, 7).is_empty():
			key = k
			break
	var before := s.plans_for(key, c, 7)
	if before.is_empty():
		_check(false, "a chunk to catch a fish in")
		return
	s.mark_caught(before[0].lie, 7)
	var after := s.plans_for(key, c, 7)
	_check(after.size() == before.size() - 1, "a caught fish stays gone that day")
	s.remove(key)
	s.add(key, _section.chunk(key), _section.chunk_rect(key))
	_check(s.plans_for(key, c, 7).size() == before.size() - 1, "and when its chunk comes back")
	_check(_describe(s.plans_for(key, c, 8)) == _describe(_stocker(_keys).plans_for(key, c, 8)),
		"a new day stocks it afresh")


func _test_count() -> void:
	var c := _summer_dusk()
	var holding: Array[Vector2i] = []
	for key in _keys:
		if FishGenerator.new(_stretch, _section.chunk(key), _calendar, null, _section.chunk_rect(key)).lie_cells() > 0:
			holding.append(key)
	var s := _stocker(holding)
	var length := 0.0
	for p in _section.centre:
		if holding.any(func(k: Vector2i) -> bool: return _section.chunk_rect(k).has_point(p)):
			length += RiverField.CHANNEL_STEP
	var want := _stretch.fish_per_100m * length / 100.0
	var total := 0
	for day in DAYS:
		total += s.all_plans(c, 1000 + day).size()
	var mean := float(total) / DAYS
	_check(holding.size() >= 3 and absf(mean - want) < 0.15 * want, "fish follow fish_per_100m: %.1f a day, want %.1f" % [mean, want])


func _test_scene_stocks() -> void:
	var main: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var fishing: Node = main.get_node(^"Fishing")
	var river: SectionField = main.river
	var streamer: RiverStreamer = main.get(&"_streamer")
	var fish: Array[Fish] = fishing.fish
	_check(not fish.is_empty(), "the Upper Fall has fish at load (%d)" % fish.size())
	var shown := streamer.shown_keys()
	_check(fish.all(func(f: Fish) -> bool: return river.key_of(f.lie) in shown),
		"every fish is in a chunk on show")
	var key: Vector2i = shown[0]
	var area := river.chunk_rect(key)
	fishing.drop_chunk(key)
	_check(fishing.fish.all(func(f: Fish) -> bool: return not area.has_point(f.lie)), "a dropped chunk's fish go")
	main.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if _failures == 0:
		print("Chunk stock tests passed.")
		quit(0)
	else:
		printerr("%d chunk stock test(s) failed." % _failures)
		quit(1)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		printerr("  FAIL ", what)
