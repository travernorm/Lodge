extends SceneTree
## Headless tests: a landed fish is out of the water for the rest of the
## session, while one that breaks off comes back to its lie.
##   godot --headless --path . --script res://tests/caught_fish_test.gd

const DT := 1.0 / 60.0

var _failures := 0
var _rng := RandomNumberGenerator.new()
var _redband: FishSpecies = load("res://data/fish/redband.tres")


func _initialize() -> void:
	_rng.seed = 11
	_test_landed_fish_stays_out()
	_test_broken_off_fish_comes_back()
	_finish.call_deferred()


func _finish() -> void:
	await _test_caught_fish_frees_its_lie()
	if _failures == 0:
		print("Caught fish tests passed.")
		quit(0)
	else:
		printerr("%d caught fish test(s) failed." % _failures)
		quit(1)


func _test_landed_fish_stays_out() -> void:
	var f := _hooked_fish()
	f.leave(true)
	_check(f.state == Fish.State.CAUGHT, "landed: the fish is caught")
	_check(not f.is_present(), "landed: it isn't drawn in the water")
	var events := []
	for i in roundi((Fish.GONE_TIME * 5.0) / DT):
		var e := f.update(DT, f.lie, true)
		if e != &"":
			events.append(e)
	_check(f.state == Fish.State.CAUGHT, "landed: still caught long after a break-off would have returned")
	_check(events.is_empty(), "landed: no dimples or rises from it (%s)" % [events])
	_check(not f.watch_pass(f.lie, 0.0, 2.0, DT) and not f.watch_pass(f.lie, 0.0, 2.0, 1.0),
		"landed: a fly drifted over its lie gets no roll")
	_check(f.try_set() == Fish.SetResult.NO_FISH, "landed: striking at it finds no fish")


func _test_broken_off_fish_comes_back() -> void:
	var f := _hooked_fish()
	f.leave()
	_check(f.state == Fish.State.GONE and not f.is_present(), "broke off: gone for a moment")
	for i in roundi((Fish.GONE_TIME + 0.5) / DT):
		f.update(DT, f.lie, false)
	_check(f.state == Fish.State.HOLDING and f.is_present(), "broke off: a trout takes the lie again")


## The fishing controller doesn't keep other trout off a caught fish's lie.
func _test_caught_fish_frees_its_lie() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	var fishing: Node = main.get_node(^"Fishing")
	_check(fishing.fish.size() >= 2, "lies: the stretch is stocked with at least two trout")
	if fishing.fish.size() >= 2:
		var a: Fish = fishing.fish[0]
		var b: Fish = fishing.fish[1]
		_check(a.lie in fishing._lies_except(b), "lies: a trout in the water keeps its lie")
		a.leave(true)
		_check(not a.lie in fishing._lies_except(b), "lies: a caught trout's lie is free")
	main.free()


func _hooked_fish() -> Fish:
	var f := Fish.new(_redband, _rng)
	f.state = Fish.State.HOOKED
	return f


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		printerr("  FAIL  ", label)
		_failures += 1
