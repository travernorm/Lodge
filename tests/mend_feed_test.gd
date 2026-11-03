extends SceneTree
## Headless tests for mends feeding out line (DriftModel.MendFeed, a feel
## experiment with three variants).
##   godot --headless --path . --script res://tests/mend_feed_test.gd

const DT := 1.0 / 60.0

var _failures := 0


func _initialize() -> void:
	_test_every_mend_feeds_line()
	_test_flat_feeds_the_same_each_time()
	_test_match_bow_keeps_the_mend()
	_test_match_bow_feeds_more_for_a_bigger_bow()
	_test_taper_feeds_less_each_time()
	_test_line_stops_at_the_limit()
	_test_more_line_drifts_further()
	_test_start_resets_the_count()
	if _failures == 0:
		print("Mend feed tests passed.")
		quit(0)
	else:
		printerr("%d mend feed test(s) failed." % _failures)
		quit(1)


func _drift(mode: DriftModel.MendFeed) -> DriftModel:
	var d := DriftModel.new()
	d.mend_feed = mode
	d.start(Vector2(20, 16.25), Vector2(20, 8.75))
	return d


## Mending as the line bows, the way a player does: every mend feeds line.
func _test_every_mend_feeds_line() -> void:
	var flow := func(p: Vector2): return Vector2(6.25 if p.y > 10.625 else 1.5, 0)
	for mode in DriftModel.MendFeed.values():
		var d := _drift(mode)
		var ok := true
		var fed := PackedStringArray()
		for i in 180:
			d.update(DT, flow)
			if d.bow() > 1.0:
				var before := d.line_length
				d.mend()
				fed.append("%.2f" % d.fed)
				ok = ok and d.fed > 0.0 and is_equal_approx(d.line_length, before + d.fed)
		_check(ok and d.mends >= 3, "mend feed: all %d mends feed line (%s: %s m)" % [
			d.mends, DriftModel.MEND_FEED_NAMES[mode], ", ".join(fed)])


func _test_flat_feeds_the_same_each_time() -> void:
	var d := _drift(DriftModel.MendFeed.FLAT)
	var start := d.line_length
	for i in 3:
		d.mend()
		_check(is_equal_approx(d.fed, DriftModel.MEND_FEED_FLAT), "mend feed: flat feeds %.1f m on mend %d" % [DriftModel.MEND_FEED_FLAT, i + 1])
	_check(is_equal_approx(d.line_length, start + 3.0 * DriftModel.MEND_FEED_FLAT), "mend feed: flat adds up over 3 mends")


## The flipped belly isn't pulled straight again: the line covers it.
func _test_match_bow_keeps_the_mend() -> void:
	var d := _drift(DriftModel.MendFeed.MATCH_BOW)
	d.mend()
	var path := d.tip.distance_to(d.belly) + d.belly.distance_to(d.fly)
	_check(d.line_length >= path - 0.001 and d.fed >= DriftModel.MEND_FEED_MIN,
		"mend feed: matches the bow covers the flipped belly (line %.2f m, path %.2f m)" % [d.line_length, path])
	var belly := d.belly
	d.update(DT, func(_p: Vector2): return Vector2.ZERO)
	_check(d.belly.distance_to(belly) < 0.01, "mend feed: the belly stays where the mend put it")


func _test_match_bow_feeds_more_for_a_bigger_bow() -> void:
	var small := _drift(DriftModel.MendFeed.MATCH_BOW)
	small.belly += small.downstream * 1.0
	small.mend()
	var big := _drift(DriftModel.MendFeed.MATCH_BOW)
	big.belly += big.downstream * 2.0
	big.mend()
	_check(big.fed > small.fed and is_equal_approx(small.fed, 1.0),
		"mend feed: matches the bow feeds more for a bigger bow (%.2f m vs %.2f m)" % [big.fed, small.fed])


func _test_taper_feeds_less_each_time() -> void:
	var d := _drift(DriftModel.MendFeed.TAPER)
	var last := INF
	var ok := true
	for i in 4:
		d.mend()
		ok = ok and d.fed < last
		last = d.fed
	_check(ok, "mend feed: taper feeds less on each mend (last %.2f m)" % last)


func _test_line_stops_at_the_limit() -> void:
	for mode in DriftModel.MendFeed.values():
		var d := _drift(mode)
		for i in 60:
			d.mend()
		_check(d.line_length <= DriftModel.LINE_LIMIT + 0.001 and is_zero_approx(d.fed),
			"mend feed: line stops at %.1f m (%s)" % [DriftModel.LINE_LIMIT, DriftModel.MEND_FEED_NAMES[mode]])
	# A cast already past the limit doesn't lose line on a mend.
	var long := DriftModel.new()
	long.start(Vector2.ZERO, Vector2(17, 0))
	var before := long.line_length
	long.mend()
	_check(long.line_length >= before, "mend feed: a mend never takes line back")


## The point of it: mending again and again lets the fly drift further.
func _test_more_line_drifts_further() -> void:
	var flow := func(_p: Vector2): return Vector2(1.5, 0)
	var plain := DriftModel.new()
	plain.mend_feed = DriftModel.MendFeed.FLAT
	plain.start(Vector2(20, 16.25), Vector2(20, 8.75))
	var mended := DriftModel.new()
	mended.mend_feed = DriftModel.MendFeed.FLAT
	mended.start(Vector2(20, 16.25), Vector2(20, 8.75))
	for i in 600:
		plain.update(DT, flow)
		mended.update(DT, flow)
		if i % 60 == 0:
			mended.mend()
			mended.belly += mended.downstream * DriftModel.MEND_SHIFT  # compare line only, not belly shape
	var reach_plain := plain.tip.distance_to(plain.fly)
	var reach_mended := mended.tip.distance_to(mended.fly)
	_check(reach_mended > reach_plain + 3.0,
		"mend feed: mending lets the fly drift further (%.1f m vs %.1f m)" % [reach_mended, reach_plain])


func _test_start_resets_the_count() -> void:
	var d := _drift(DriftModel.MendFeed.TAPER)
	d.mend()
	d.mend()
	d.start(Vector2(20, 16.25), Vector2(20, 8.75))
	d.mend()
	_check(is_equal_approx(d.fed, DriftModel.MEND_FEED_TAPER) and d.mends == 1,
		"mend feed: a new cast starts the taper over")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
