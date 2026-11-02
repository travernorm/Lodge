extends SceneTree
## Headless tests for drift, mending, rises, hook sets and fights.
##   godot --headless --path . --script res://tests/fishing_test.gd

const DT := 1.0 / 60.0

var _failures := 0
var _rng := RandomNumberGenerator.new()
var _cutthroat: FishSpecies = load("res://data/fish/cutthroat.tres")
var _redband: FishSpecies = load("res://data/fish/redband.tres")
var _brook: FishSpecies = load("res://data/fish/brook.tres")


func _initialize() -> void:
	_rng.seed = 42
	_test_data_loads()
	_test_loop_is_a_mend()
	_test_wiggle_is_not_a_mend()
	_test_flick_sets()
	_test_slow_push_is_not_a_flick()
	_test_uniform_current_starts_drag_free()
	_test_faster_belly_drags()
	_test_mend_buys_a_drag_free_drift()
	_test_early_mend_jolts_fly()
	_test_bite_chance_by_distance_and_presentation()
	_test_bite_rate_matches_the_odds()
	_test_bite_becomes_a_take()
	_test_picking_up_cancels_a_bite()
	_test_dimples_show_where_the_fish_is()
	_test_fish_hold_in_good_lies()
	_test_set_timing()
	_test_full_pressure_snaps_a_strong_fish()
	_test_no_pressure_throws_hook()
	_test_steady_pressure_lands_fish()
	_test_holding_on_lands_the_starter_trout()
	if _failures == 0:
		print("Fishing tests passed.")
		quit(0)
	else:
		printerr("%d fishing test(s) failed." % _failures)
		quit(1)


# --- Data ------------------------------------------------------------------

func _test_data_loads() -> void:
	for path in ["res://data/flies/parachute_adams.tres", "res://data/flies/elk_hair_caddis.tres", "res://data/flies/royal_wulff.tres"]:
		var fly := load(path) as FlyPattern
		_check(fly != null and fly.display_name != "", "data: %s loads" % path.get_file())
	for sp in [_cutthroat, _redband, _brook]:
		_check(sp != null and sp.bite_chance > 0.0 and sp.bite_range_m > Fish.CLOSE_RANGE, "data: %s has bite odds" % sp.id)
		_check(sp.set_min < sp.set_max, "data: %s set window is valid" % sp.id)


# --- Stick gestures --------------------------------------------------------

func _test_loop_is_a_mend() -> void:
	var g := StickGestures.new()
	var t := 0.0
	var looped := false
	for i in 25:  # a half-circle sweep over ~0.4 s, starting from the right
		t += DT
		g.update(t, Vector2.from_angle(-PI * float(i) / 24.0))
		looped = looped or g.looped
	_check(looped, "gesture: half-circle sweep is a mend")


func _test_wiggle_is_not_a_mend() -> void:
	var g := StickGestures.new()
	var t := 0.0
	var looped := false
	for i in 60:
		t += DT
		g.update(t, Vector2(1.0, 0.3 if i % 10 < 5 else -0.3).normalized())
		looped = looped or g.looped
	_check(not looped, "gesture: side-to-side wiggle is not a mend")


func _test_flick_sets() -> void:
	var g := StickGestures.new()
	g.update(0.0, Vector2.ZERO)
	g.update(DT, Vector2(0, -0.5))
	g.update(DT * 2, Vector2(0, -1.0))
	_check(g.flicked, "gesture: fast flick up is a hook set")
	g.update(DT * 3, Vector2(0, -1.0))
	_check(not g.flicked, "gesture: holding up doesn't set twice")


func _test_slow_push_is_not_a_flick() -> void:
	var g := StickGestures.new()
	var t := 0.0
	var flicked := false
	for i in 30:
		t += DT
		g.update(t, Vector2(0, -float(i) / 29.0))
		flicked = flicked or g.flicked
	_check(not flicked, "gesture: slowly pushing up is not a hook set")


# --- Drift -----------------------------------------------------------------

func _test_uniform_current_starts_drag_free() -> void:
	var d := DriftModel.new()
	d.start(Vector2(20, 16.25), Vector2(20, 11.25))
	_run_drift(d, 1.0, func(_p: Vector2): return Vector2(2.5, 0))
	_check(d.drag < 0.15, "drift: first second in even current is drag-free (drag %.2f)" % d.drag)


func _test_faster_belly_drags() -> void:
	var d := DriftModel.new()
	d.start(Vector2(20, 16.25), Vector2(20, 8.75))
	# Fast water mid-river, slow water at the fly: the classic drag setup.
	_run_drift(d, 2.0, func(p: Vector2): return Vector2(6.25 if p.y > 10.625 else 1.5, 0))
	_check(d.drag > 0.5, "drift: fast mid-river current drags a fly in slow water (drag %.2f)" % d.drag)


func _test_mend_buys_a_drag_free_drift() -> void:
	var flow := func(p: Vector2): return Vector2(6.25 if p.y > 10.625 else 1.5, 0)
	var unmended := DriftModel.new()
	unmended.start(Vector2(20, 16.25), Vector2(20, 8.75))
	var mended := DriftModel.new()
	mended.start(Vector2(20, 16.25), Vector2(20, 8.75))
	var worst_unmended := 0.0
	var worst_mended := 0.0
	for i in 120:
		unmended.update(DT, flow)
		mended.update(DT, flow)
		if mended.bow() > 1.0:
			mended.mend()
		worst_unmended = maxf(worst_unmended, unmended.drag)
		worst_mended = maxf(worst_mended, mended.drag)
	_check(worst_mended < 0.35 and worst_mended < worst_unmended,
		"drift: mending as the line bows keeps drag down (%.2f vs %.2f unmended)" % [worst_mended, worst_unmended])


func _test_early_mend_jolts_fly() -> void:
	var d := DriftModel.new()
	d.start(Vector2(20, 16.25), Vector2(20, 8.75))
	d.mend()
	_check(d.over_mended, "drift: mending with no bow moves the fly")
	_run_drift(d, 0.15, func(_p: Vector2): return Vector2(1.25, 0))
	_check(d.drag > 0.3, "drift: over-mend shows as drag (%.2f)" % d.drag)


# --- Fish ------------------------------------------------------------------

func _test_bite_chance_by_distance_and_presentation() -> void:
	var f := Fish.new(_redband, _rng)
	var close := f.lie + Vector2(-0.625, 0)
	var delicate := f.bite_chance_for(close, "Delicate")
	_check(is_equal_approx(delicate, _redband.bite_chance), "odds: delicate cast right by the fish gets the full chance (%.2f)" % delicate)
	_check(f.bite_chance_for(close, "Fair") < delicate, "odds: a fair landing is less likely")
	_check(f.bite_chance_for(close, "Splashy") < f.bite_chance_for(close, "Fair"), "odds: a splashy landing is least likely")
	var mid := f.bite_chance_for(f.lie + Vector2(0, -_redband.bite_range_m * 0.6), "Delicate")
	_check(mid > 0.0 and mid < delicate, "odds: farther away is less likely (%.2f)" % mid)
	_check(f.bite_chance_for(f.lie + Vector2(_redband.bite_range_m + 0.125, 0), "Delicate") == 0.0, "odds: out of range never bites")


func _test_bite_rate_matches_the_odds() -> void:
	var f := Fish.new(_redband, _rng)
	var bites := 0
	var casts := 2000
	for i in casts:
		f.on_landing(f.lie + Vector2(-0.625, 0), "Delicate")
		if f.state == Fish.State.WAITING:
			bites += 1
	var rate := float(bites) / casts
	_check(absf(rate - _redband.bite_chance) < 0.04, "odds: bite rate over %d casts is %.2f (expected %.2f)" % [casts, rate, _redband.bite_chance])


func _test_bite_becomes_a_take() -> void:
	var f := Fish.new(_eager(_redband), _rng)
	var fly := f.lie + Vector2(-0.625, 0)
	f.on_landing(fly, "Delicate")
	var events: Array[StringName] = []
	for i in 180:
		var e := f.update(DT, fly, true)
		if e != &"" and e != &"dimple":
			events.append(e)
		if f.state == Fish.State.TAKEN:
			break
	_check(events == [&"rising", &"take"], "take: a bite rises then takes the fly (%s)" % [events])


func _test_picking_up_cancels_a_bite() -> void:
	var f := Fish.new(_eager(_redband), _rng)
	f.on_landing(f.lie, "Delicate")
	f.update(DT, f.lie, false)
	_check(f.state == Fish.State.HOLDING, "take: lifting the fly off the water cancels the bite")


func _test_dimples_show_where_the_fish_is() -> void:
	var f := Fish.new(_redband, _rng)
	var dimples := 0
	for i in 600:
		if f.update(DT, Vector2.ZERO, false) == &"dimple":
			dimples += 1
	_check(dimples >= 1, "dimple: the fish rises on its own now and then (%d in 10 s)" % dimples)


func _test_set_timing() -> void:
	var early := _taken_fish(_cutthroat)
	early.since_take = _cutthroat.set_min * 0.5
	_check(early.try_set() == Fish.SetResult.TOO_EARLY, "set: too early pulls the fly away")
	var good := _taken_fish(_cutthroat)
	good.since_take = (_cutthroat.set_min + _cutthroat.set_max) * 0.5
	_check(good.try_set() == Fish.SetResult.HOOKED, "set: in the window hooks it")
	var late := _taken_fish(_cutthroat)
	var event := &""
	for i in 120:
		var e := late.update(DT, late.pos, true)
		if e != &"":
			event = e
			break
	_check(event == &"spat", "set: waiting too long, it spits the fly")
	_check(Fish.new(_cutthroat, _rng).try_set() == Fish.SetResult.NO_FISH, "set: nothing there, nothing happens")


# --- Fight -----------------------------------------------------------------

func _test_full_pressure_snaps_a_strong_fish() -> void:
	var strong: FishSpecies = _redband.duplicate()
	strong.pull = 1.0
	var f := FightModel.new(strong, 6.25, -PI / 2.0, _rng)
	var result := _run_fight(f, 10.0, func(_f: FightModel): return Vector2(0, -1))
	_check(result == FightModel.Result.SNAPPED, "fight: full pressure on a strong running fish snaps it (%s)" % FightModel.Result.keys()[result])


func _test_no_pressure_throws_hook() -> void:
	var f := FightModel.new(_brook, 5.0, -PI / 2.0, _rng)
	var result := _run_fight(f, 10.0, func(_f: FightModel): return Vector2.ZERO)
	_check(result == FightModel.Result.THREW_HOOK, "fight: no pressure and it throws the hook (%s)" % FightModel.Result.keys()[result])


func _test_steady_pressure_lands_fish() -> void:
	for sp in [_cutthroat, _redband, _brook]:
		var f := FightModel.new(sp, 6.25, -PI / 2.0, _rng)
		# Ease off and pull sideways on runs, lean in between them.
		var policy := func(fm: FightModel):
			return Vector2(-fm.run_dir * 0.4, -0.1) if fm.running else Vector2(0, -0.85)
		var result := _run_fight(f, 60.0, policy)
		_check(result == FightModel.Result.LANDED, "fight: easing off on runs lands a %s (%s)" % [sp.id, FightModel.Result.keys()[result]])


func _test_holding_on_lands_the_starter_trout() -> void:
	# The starter redband is gentle: holding full pressure the whole fight (as on
	# a keyboard) lands it instead of snapping.
	var f := FightModel.new(_redband, 6.25, -PI / 2.0, _rng)
	var result := _run_fight(f, 60.0, func(_f: FightModel): return Vector2(0, -1))
	_check(result == FightModel.Result.LANDED, "fight: holding on the whole time lands the starter redband (%s)" % FightModel.Result.keys()[result])


# --- Helpers ---------------------------------------------------------------

func _run_drift(d: DriftModel, seconds: float, flow: Callable) -> void:
	for i in roundi(seconds / DT):
		d.update(DT, flow)


## A copy of a species that always bites, for testing what happens after.
func _eager(species: FishSpecies) -> FishSpecies:
	var copy: FishSpecies = species.duplicate()
	copy.bite_chance = 1.0
	return copy


func _taken_fish(species: FishSpecies) -> Fish:
	var f := Fish.new(species, _rng)
	f.state = Fish.State.TAKEN
	f.since_take = 0.0
	return f


func _run_fight(f: FightModel, seconds: float, policy: Callable) -> FightModel.Result:
	for i in roundi(seconds / DT):
		var r := f.update(DT, policy.call(f))
		if r != FightModel.Result.FIGHTING:
			return r
	return FightModel.Result.FIGHTING


func _test_fish_hold_in_good_lies() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var river: RiverField = main.river
	var worst := 1.0
	var outside := 0
	for i in 40:
		var f := Fish.new(_redband, _rng, river)
		worst = minf(worst, river.lie_at(f.lie))
		if not _redband.lie_area_m.grow(0.125).has_point(f.lie) or not river.is_water(f.lie):
			outside += 1
	_check(worst >= Fish.MIN_LIE_SCORE * 0.8, "lies: the redband only holds in good water (worst lie %.2f)" % worst)
	_check(outside == 0, "lies: always in its own area and never in the rock (%d strays)" % outside)
	var nowhere := _redband.duplicate() as FishSpecies
	nowhere.lie_area_m = Rect2(1.25, 17.5, 2.5, 0.75)  # ankle-deep edge water, no lies
	var f := Fish.new(nowhere, _rng, river)
	_check(nowhere.lie_area_m.grow(0.125).has_point(f.lie), "lies: with no good water it still stays in its area")
	main.free()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
