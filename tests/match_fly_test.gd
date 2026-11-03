extends SceneTree
## Headless tests for fly matching (REQ-0003): what a fly imitates against what
## a trout eats, scaled by its selectivity, in the Drift past bite rules.
##   godot --headless --path . --script res://tests/match_fly_test.gd

var _failures := 0
var _rng := RandomNumberGenerator.new()
var _match: DriftPastRules = load("res://data/take_rules/drift_past.tres")
var _caddis: FlyPattern = load("res://data/tackle/flies/elk_hair_caddis.tres")
var _adams: FlyPattern = load("res://data/tackle/flies/parachute_adams.tres")
var _wulff: FlyPattern = load("res://data/tackle/flies/royal_wulff.tres")
var _redband: FishSpecies = load("res://data/fish/redband.tres")
var _cutthroat: FishSpecies = load("res://data/fish/cutthroat.tres")
var _brook: FishSpecies = load("res://data/fish/brook.tres")


func _initialize() -> void:
	_rng.seed = 5
	_test_match_table()
	_test_match_rule()
	_test_no_fly_is_a_match()
	_test_perfect_pass_odds()
	_test_partial_appetite_odds()
	_test_the_fly_changes_the_odds()
	_test_odds_text()
	_test_tie_on_text()
	_test_same_inputs_same_odds()
	if _failures == 0:
		print("Match fly tests passed.")
		quit(0)
	else:
		printerr("%d match fly test(s) failed." % _failures)
		quit(1)


## The table in REQ-0003, from the real data files.
func _test_match_table() -> void:
	var table := [
		[_redband, _caddis, 0.75], [_redband, _adams, 1.0], [_redband, _wulff, 0.5],
		[_cutthroat, _caddis, 1.0], [_cutthroat, _adams, 0.4], [_cutthroat, _wulff, 0.4],
		[_brook, _caddis, 1.0], [_brook, _adams, 1.0], [_brook, _wulff, 1.0],
	]
	for row in table:
		var sp: FishSpecies = row[0]
		var fly: FlyPattern = row[1]
		var got := sp.fly_match(fly)
		_check(is_equal_approx(got, row[2]), "match: %s on a %s is x%.2f (got %.2f)" % [sp.id, fly.id, row[2], got])


## 1 - selectivity x (1 - appetite), with appetite the best diet weight.
func _test_match_rule() -> void:
	var sp := FishSpecies.new()
	sp.selectivity = 0.8
	sp.diet = [_entry("pmd", 0.25), _entry("caddis", 0.5)]
	var both := FlyPattern.new()
	both.imitates = [load("res://data/insects/pmd.tres"), load("res://data/insects/caddis.tres")]
	_check(is_equal_approx(sp.appetite_for(both).appetite, 0.5), "match: appetite is the best diet weight among the fly's bugs")
	_check((sp.appetite_for(both).insect as Insect).id == &"caddis", "match: the best bug is the one reported")
	_check(is_equal_approx(sp.fly_match(both), 1.0 - 0.8 * 0.5), "match: 1 - selectivity x (1 - appetite)")
	sp.selectivity = 0.0
	_check(is_equal_approx(sp.fly_match(_wulff), 1.0), "match: selectivity 0 takes anything")
	sp.selectivity = 1.0
	_check(is_equal_approx(sp.fly_match(_wulff), 0.0), "match: selectivity 1 takes only its food")


func _test_no_fly_is_a_match() -> void:
	_check(is_equal_approx(_cutthroat.fly_match(null), 1.0), "match: nothing tied on counts as x1")
	var f := Fish.new(_cutthroat, _rng)
	var odds := _match.pass_odds(f, f.lie, "Delicate", 0.0)
	_check(is_equal_approx(odds.chance, _cutthroat.bite_chance), "match: no fly gives the plain lane + landing + drift odds")


## A delicate, drag-free pass: full bite_chance with the right fly,
## bite_chance x (1 - selectivity) with a fly it doesn't eat.
func _test_perfect_pass_odds() -> void:
	for sp in [_redband, _cutthroat, _brook]:
		var f := Fish.new(sp, _rng)
		var right: FlyPattern = _caddis if sp.wants(load("res://data/insects/caddis.tres")) >= 1.0 else _adams
		var good: float = _match.pass_odds(f, f.lie, "Delicate", 0.0, right).chance
		_check(is_equal_approx(good, sp.bite_chance), "odds: %s, right fly, perfect pass gets bite_chance (%.2f)" % [sp.id, good])
	var c := Fish.new(_cutthroat, _rng)
	var wrong: float = _match.pass_odds(c, c.lie, "Delicate", 0.0, _wulff).chance
	_check(is_equal_approx(wrong, _cutthroat.bite_chance * (1.0 - _cutthroat.selectivity)),
		"odds: cutthroat, wrong fly, perfect pass gets bite_chance x (1 - selectivity) (%.2f)" % wrong)


## The worked example: a redband, an Elk Hair Caddis landed Fair nearby, worst
## slip 0.55 m/s: (20 + 10 + 10) x 0.75 = 30%.
func _test_partial_appetite_odds() -> void:
	var f := Fish.new(_redband, _rng)
	var odds := _match.pass_odds(f, f.lie + Vector2(-1.5, 0), "Fair", 0.55, _caddis)
	_check(is_equal_approx(odds.chance, 0.3), "odds: the REQ's worked example comes to 30%% (%.3f)" % odds.chance)


## The tied-on fly moves the odds of the same pass: the bite rules weigh it.
func _test_the_fly_changes_the_odds() -> void:
	var f := Fish.new(_cutthroat, _rng)
	var near := f.lie + Vector2(-1.5, 0)
	var a: float = _match.pass_odds(f, near, "Delicate", 0.0, _caddis).chance
	var b: float = _match.pass_odds(f, near, "Delicate", 0.0, _wulff).chance
	_check(a > b, "rules: a cutthroat takes the caddis over the Wulff on the same pass (%.2f vs %.2f)" % [a, b])


func _test_odds_text() -> void:
	var r := Fish.new(_redband, _rng)
	var t1: String = _match.pass_odds(r, r.lie, "Delicate", 0.0, _adams).text
	_check(t1 == "(Lane 20 + Delicate 20 + No drag 20) × PMD 1 = 60%", "text: a match names the bug (%s)" % t1)
	var t2: String = _match.pass_odds(r, r.lie, "Delicate", 0.0, _wulff).text
	_check(t2 == "(Lane 20 + Delicate 20 + No drag 20) × No match 0.5 = 30%", "text: a miss says so (%s)" % t2)
	var t3: String = _match.pass_odds(r, r.lie, "Delicate", 0.0, _caddis).text
	_check(t3 == "(Lane 20 + Delicate 20 + No drag 20) × Caddis 0.75 = 45%", "text: a partial match shows its factor (%s)" % t3)


func _test_tie_on_text() -> void:
	_check(_adams.kinds_text() == "mayfly", "fly: the Adams ties on as a mayfly (%s)" % _adams.kinds_text())
	_check(_caddis.kinds_text() == "caddis", "fly: the Caddis ties on as a caddis")
	_check(_wulff.kinds_text() == "attractor", "fly: the Wulff ties on as an attractor")


## No dice in the match: the same pass gives the same odds every time.
func _test_same_inputs_same_odds() -> void:
	var f := Fish.new(_redband, _rng)
	var first: float = _match.pass_odds(f, f.lie, "Fair", 0.4, _caddis).chance
	for i in 20:
		if not is_equal_approx(_match.pass_odds(f, f.lie, "Fair", 0.4, _caddis).chance, first):
			_check(false, "determinism: the same pass gave different odds")
			return
	_check(true, "determinism: the same pass gives the same odds")


func _entry(insect_id: String, weight: float) -> DietEntry:
	var e := DietEntry.new()
	e.insect = load("res://data/insects/%s.tres" % insect_id)
	e.weight = weight
	return e


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s" % label)
