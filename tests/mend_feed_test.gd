extends SceneTree
## Headless tests for mends feeding out line: each mend feeds as much line as
## the belly had bowed downstream (DriftModel.MEND_FEED_MIN to MEND_SHIFT).
##   godot --headless --path . --script res://tests/mend_feed_test.gd

const DT := 1.0 / 60.0

var _failures := 0


func _initialize() -> void:
	_test_every_mend_feeds_line()
	_test_mend_keeps_its_shape()
	_test_bigger_bow_feeds_more()
	_test_line_stops_at_the_limit()
	_test_more_line_drifts_further()
	if _failures == 0:
		print("Mend feed tests passed.")
		quit(0)
	else:
		printerr("%d mend feed test(s) failed." % _failures)
		quit(1)


func _drift() -> DriftModel:
	var d := DriftModel.new()
	d.start(Vector2(20, 16.25), Vector2(20, 8.75))
	return d


## Mending as the line bows, the way a player does: every mend feeds line.
func _test_every_mend_feeds_line() -> void:
	var flow := func(p: Vector2): return Vector2(6.25 if p.y > 10.625 else 1.5, 0)
	var d := _drift()
	var ok := true
	var fed := PackedStringArray()
	for i in 180:
		d.update(DT, flow)
		if d.bow() > 1.0:
			var before := d.line_length
			d.mend()
			fed.append("%.2f" % d.fed)
			ok = ok and d.fed >= DriftModel.MEND_FEED_MIN and is_equal_approx(d.line_length, before + d.fed)
	_check(ok and fed.size() >= 3, "mend feed: all %d mends feed line (%s m)" % [fed.size(), ", ".join(fed)])


## The flipped belly isn't pulled straight again: the line covers it.
func _test_mend_keeps_its_shape() -> void:
	var d := _drift()
	d.mend()
	var path := d.tip.distance_to(d.belly) + d.belly.distance_to(d.fly)
	_check(d.line_length >= path - 0.001 and d.fed >= DriftModel.MEND_FEED_MIN,
		"mend feed: the line covers the flipped belly (line %.2f m, path %.2f m)" % [d.line_length, path])
	var belly := d.belly
	d.update(DT, func(_p: Vector2): return Vector2.ZERO)
	_check(d.belly.distance_to(belly) < 0.01, "mend feed: the belly stays where the mend put it")


func _test_bigger_bow_feeds_more() -> void:
	var small := _drift()
	small.belly += small.downstream * 1.0
	small.mend()
	var big := _drift()
	big.belly += big.downstream * 2.0
	big.mend()
	var huge := _drift()
	huge.belly += huge.downstream * 5.0
	huge.mend()
	_check(big.fed > small.fed and is_equal_approx(small.fed, 1.0),
		"mend feed: a bigger bow feeds more (%.2f m vs %.2f m)" % [big.fed, small.fed])
	_check(huge.fed <= DriftModel.MEND_SHIFT + 0.001, "mend feed: at most %.2f m per mend (%.2f m)" % [DriftModel.MEND_SHIFT, huge.fed])


func _test_line_stops_at_the_limit() -> void:
	var d := _drift()
	for i in 60:
		d.mend()
	_check(d.line_length <= DriftModel.LINE_LIMIT + 0.001 and is_zero_approx(d.fed),
		"mend feed: line stops at %.1f m" % DriftModel.LINE_LIMIT)
	# A cast already past the limit doesn't lose line on a mend.
	var long := DriftModel.new()
	long.start(Vector2.ZERO, Vector2(17, 0))
	var before := long.line_length
	long.mend()
	_check(long.line_length >= before, "mend feed: a mend never takes line back")


## The point of it: mending again and again lets the fly drift further.
func _test_more_line_drifts_further() -> void:
	var flow := func(_p: Vector2): return Vector2(1.5, 0)
	var plain := _drift()
	var mended := _drift()
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


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
