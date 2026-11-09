extends SceneTree
## Headless tests for lightning (REQ-0015): a strike is a few flickers and a
## fade, never faster than three flickers a second or brighter than the cap;
## the look's flash strength scales it to nothing; near strikes come from a
## side and leave an afterglow; and the same seed gives the same storm.
##   godot --headless --path . --script res://tests/lightning_test.gd

const STEP := 1.0 / 240.0

var _failures := 0


func _initialize() -> void:
	_test_strike_shape()
	_test_flash_safety()
	_test_strength()
	_test_near_and_far()
	_test_rate_and_seed()
	if _failures == 0:
		print("Lightning tests passed.")
		quit(0)
	else:
		printerr("%d lightning test(s) failed." % _failures)
		quit(1)


func _test_strike_shape() -> void:
	var m := LightningModel.new(3)
	var heard := [0]
	m.struck.connect(func(_near: bool): heard[0] += 1)
	m.strike(false)
	_check(heard[0] == 1, "shape: a strike says so")
	_check(m.starts.size() >= 2 and m.starts.size() <= 4, "shape: two to four flickers (%d)" % m.starts.size())
	_check(m.flash > 0.0 and m.is_striking(), "shape: the first flicker is at once")
	var between := m.starts[0] + m.lengths[0] + 0.01
	_check(m.flash_at(between) == 0.0, "shape: dark between flickers")
	var last := m.starts.size() - 1
	var end := m.starts[last] + m.lengths[last]
	_check(m.flash_at(end + 0.1) > 0.0 and m.flash_at(end + 0.1) < m.peaks[last], "shape: a dimmer fade after the last flicker")
	_check(m.flash_at(end + LightningModel.TAIL_SECONDS + 0.01) == 0.0, "shape: then nothing")
	for i in int(5.0 / STEP):
		m.step(STEP, 0.0)
	_check(m.flash == 0.0 and not m.is_striking(), "shape: the strike ends")


## Acceptance: no flickers closer than 1/3 s, none brighter than the cap.
func _test_flash_safety() -> void:
	var closest := INF
	var brightest := 0.0
	for s in 200:
		var m := LightningModel.new(s)
		m.strike(s % 2 == 0)
		for i in range(1, m.starts.size()):
			closest = minf(closest, m.starts[i] - m.starts[i - 1])
		var t := 0.0
		while t < 3.0:
			brightest = maxf(brightest, m.flash_at(t))
			t += STEP
	_check(closest >= 1.0 / 3.0, "safety: flickers start at least a third of a second apart (%.3f)" % closest)
	_check(brightest <= LightningModel.MAX_FLASH, "safety: never brighter than the cap (%.2f)" % brightest)


## Acceptance: flash_strength 0 gives no flash.
func _test_strength() -> void:
	var m := LightningModel.new(5)
	m.strength = 0.0
	m.strike(true)
	var any := 0.0
	for i in int(3.0 / STEP):
		m.step(STEP, 0.0)
		any = maxf(any, maxf(m.flash, m.afterglow))
	_check(any == 0.0, "strength: 0 shows no flash and no afterglow")
	var half := LightningModel.new(5)
	half.strength = 0.5
	half.strike(true)
	var full := LightningModel.new(5)
	full.strike(true)
	_check(is_equal_approx(half.flash, full.flash * 0.5), "strength: 0.5 halves the flash")


func _test_near_and_far() -> void:
	var near := LightningModel.new(9)
	near.strike(true)
	var far := LightningModel.new(9)
	far.strike(false)
	_check(absf(near.side) == 1.0 and far.side == 0.0, "near: comes from one side; far from everywhere")
	_check(near.peaks[0] > far.peaks[0], "near: is brighter than far (%.2f > %.2f)" % [near.peaks[0], far.peaks[0]])
	var glow_near := 0.0
	var glow_far := 0.0
	for i in int(4.0 / STEP):
		near.step(STEP, 0.0)
		far.step(STEP, 0.0)
		glow_near = maxf(glow_near, near.afterglow)
		glow_far = maxf(glow_far, far.afterglow)
		_check_quiet(not (near.afterglow > 0.0 and near.flash > 0.0), "near: the afterglow waits for the flash to end")
	_check(glow_near > 0.0 and glow_near <= LightningModel.AFTERGLOW and glow_far == 0.0, "near: leaves an afterglow, far doesn't")
	_check(near.afterglow == 0.0, "near: the afterglow passes")


## Strikes come about as often as asked, never without a storm, and the same
## seed plays the same storm.
func _test_rate_and_seed() -> void:
	var a := LightningModel.new(11)
	var b := LightningModel.new(11)
	var strikes := [0, 0]
	a.struck.connect(func(_n: bool): strikes[0] += 1)
	var same := true
	for i in int(300.0 / STEP):
		a.step(STEP, 4.0)
		b.step(STEP, 4.0)
		same = same and a.flash == b.flash
	_check(same, "seed: the same seed plays the same storm")
	_check(strikes[0] >= 12 and strikes[0] <= 30, "rate: about 4 a minute over 5 minutes (%d)" % strikes[0])
	var calm := LightningModel.new(11)
	calm.struck.connect(func(_n: bool): strikes[1] += 1)
	for i in int(120.0 / STEP):
		calm.step(STEP, 0.0)
	_check(strikes[1] == 0, "rate: no storm, no strikes")


## Counts a failure but doesn't print a pass (for checks inside loops).
func _check_quiet(ok: bool, what: String) -> void:
	if not ok:
		_check(false, what)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", what)
