class_name Fish
extends RefCounted
## One trout holding in the stream.
##
## In the game each fish comes from a FishPlan (from_plan(), REQ-0007): the
## fish generator picks its species, length, lie and how often it rises, and
## a fish that breaks off comes back to that same lie. Built directly (tests),
## it picks its own lie from the river field (RiverField.pick_lie()) inside
## the area it's given, or any spot there without a field. Positions are in
## metres (REQ-0001).
##
## When it bites is up to the fishing controller's bite rules (DriftPastRules):
## one roll per pass as the fly drifts by (watch_pass() and roll()). If the
## roll succeeds, it rises to the fly a moment later. Then you have to set the
## hook in its window.
##
## update() returns an event name the scene can react to:
##   &"dimple"  a natural rise at its lie, so you can see where it is
##   &"rising"  coming up for your fly
##   &"take"    took the fly: the hook-set window is open
##   &"spat"    you waited too long and it spat the fly

## CAUGHT: landed this session. It stays out of the water until the session
## ends: it never rises, bites or comes back (a break-off is GONE and returns).
enum State { HOLDING, WAITING, RISING, TAKEN, HOOKED, GONE, CAUGHT }
enum SetResult { HOOKED, TOO_EARLY, TOO_LATE, NO_FISH }

const RISE_TIME := 0.35
const BITE_DELAY := Vector2(0.6, 2.0)  # seconds after landing before it rises
const DIMPLE_EVERY := Vector2(3.0, 6.0)
const GONE_TIME := 4.0
## Drift-past rules: the fly has passed its closest point once it is this much
## (m) farther away again; or the fish rolls after this long (s) in the window.
const PASS_MOVED_AWAY := 0.05
const PASS_MAX_WAIT := 1.0

## Only lies scoring at least this in the river field are taken.
const MIN_LIE_SCORE := 0.4
## Where a fish holds when it's given no area: the water band of the
## one-screen test stream, for tests.
const TEST_AREA := Rect2(0, 7.5, 40, 10)
## Trout sharing water keep at least this far (m) from each other's lies.
const LIE_GAP := 3.0

var species: FishSpecies
## Where it holds the rest of the time.
var lie := Vector2.ZERO
## The river it lives in; optional.
var river: RiverField
## Where it may hold (m): the stretch it was stocked in (TEST_AREA if none).
var area := Rect2()
## Optional: returns the lies (m) of the other trout in the same water, as a
## PackedVector2Array, so this one keeps clear of them. Takes this fish.
var other_lies: Callable
## Where to draw it. Moves to the fly during a rise.
var pos := Vector2.ZERO
var length_in := 0.0
## 0 to 1: how keen it is today. Natural rises come 1/activity times as far
## apart as at full activity.
var activity := 1.0
## Built from a FishPlan: it keeps its lie and length when it comes back.
var planned := false
var state := State.HOLDING
## Time since the take, while TAKEN.
var since_take := 0.0
## The bite chance rolled for the last cast that landed, or the last pass.
var last_bite_chance := 0.0

# Drift-past rules: the fly's current pass through this fish's window.
var _pass_open := false
var _pass_rolled := false
var _pass_closest := 0.0
var _pass_time := 0.0
## The worst slip (m/s) the fly has had so far in this pass.
var pass_worst_slip := 0.0

var _timer := 0.0
var _dimple_timer := 0.0
var _rng: RandomNumberGenerator


func _init(p_species: FishSpecies, rng: RandomNumberGenerator, p_river: RiverField = null,
		p_area := Rect2(), p_other_lies := Callable()) -> void:
	species = p_species
	_rng = rng
	river = p_river
	area = p_area if p_area.has_area() else TEST_AREA
	other_lies = p_other_lies
	respawn()


## A fish from the generator's plan, on its planned lie.
static func from_plan(plan: FishPlan, rng: RandomNumberGenerator) -> Fish:
	var f := Fish.new(plan.species, rng)
	f.planned = true
	f.lie = plan.lie
	f.length_in = plan.length_in
	f.activity = plan.activity
	f.respawn()
	return f


## Back on its lie, holding. A planned fish keeps its lie and length; any
## other picks a new lie in its habitat, as a new fish. in its habitat, as a new fish.
func respawn() -> void:
	if planned:
		_hold()
		return
	var a := area
	var spot := Vector2.INF
	if river != null:
		var taken: PackedVector2Array = other_lies.call(self) if other_lies.is_valid() else PackedVector2Array()
		spot = river.pick_lie(a, _rng, MIN_LIE_SCORE, taken, LIE_GAP)
	if spot == Vector2.INF:
		spot = Vector2(_rng.randf_range(a.position.x, a.end.x), _rng.randf_range(a.position.y, a.end.y))
	lie = spot
	pos = lie
	length_in = snappedf(_rng.randf_range(species.min_length_in, species.max_length_in), 0.5)
	_hold()


func _hold() -> void:
	pos = lie
	state = State.HOLDING
	_dimple_timer = _rng.randf_range(0.5, DIMPLE_EVERY.y) / maxf(activity, 0.05)


## Visible in the water (not gone off somewhere, and not caught).
func is_present() -> bool:
	return state != State.GONE and state != State.CAUGHT


## Rolls `chance` for a bite. On a bite it rises after `delay` seconds (a
## random time in the range). Returns the chance.
func roll(chance: float, delay := BITE_DELAY) -> float:
	last_bite_chance = chance
	if _rng.randf() < chance:
		state = State.WAITING
		_timer = _rng.randf_range(delay.x, delay.y)
	else:
		_settle()
	return chance


## A new cast landed: forget the last fly's pass.
func reset_pass() -> void:
	_pass_open = false
	_pass_rolled = false


## For the drift-past rules: follows the fly (m) through this fish's window
## (radius m). A pass starts when the fly comes within the window, including
## landing in it, and ends when it leaves. Returns true once per pass, when it's
## time to roll: as the fly starts to move away (its closest point), or after
## a second in the window. pass_worst_slip holds the worst slip up to then.
func watch_pass(fly: Vector2, slip: float, radius: float, dt: float) -> bool:
	if state != State.HOLDING:
		return false
	var d := fly.distance_to(lie)
	if d > radius:
		_pass_open = false
		return false
	if not _pass_open:
		_pass_open = true
		_pass_rolled = false
		_pass_closest = d
		_pass_time = 0.0
		pass_worst_slip = slip
		return false
	if _pass_rolled:
		return false
	pass_worst_slip = maxf(pass_worst_slip, slip)
	_pass_time += dt
	if d < _pass_closest:
		_pass_closest = d
	if d > _pass_closest + PASS_MOVED_AWAY or _pass_time >= PASS_MAX_WAIT:
		_pass_rolled = true
		return true
	return false


func update(dt: float, fly: Vector2, fly_on_water: bool) -> StringName:
	_timer -= dt
	match state:
		State.GONE:
			if _timer <= 0.0:
				respawn()
		State.HOLDING:
			_dimple_timer -= dt
			if _dimple_timer <= 0.0:
				_dimple_timer = _rng.randf_range(DIMPLE_EVERY.x, DIMPLE_EVERY.y) / maxf(activity, 0.05)
				return &"dimple"
		State.WAITING:
			if not fly_on_water:
				_settle()
			elif _timer <= 0.0:
				state = State.RISING
				_timer = RISE_TIME
				return &"rising"
		State.RISING:
			if not fly_on_water:
				_settle()
				return &""
			pos = lie.lerp(fly, clampf(1.0 - _timer / RISE_TIME, 0.0, 1.0))
			if _timer <= 0.0:
				state = State.TAKEN
				since_take = 0.0
				pos = fly
				return &"take"
		State.TAKEN:
			since_take += dt
			pos = fly
			if since_take > species.set_max:
				_settle()
				return &"spat"
	return &""


## The player flicked to set the hook.
func try_set() -> SetResult:
	match state:
		State.RISING:
			_settle()
			return SetResult.TOO_EARLY
		State.TAKEN:
			if since_take < species.set_min:
				_settle()
				return SetResult.TOO_EARLY
			if since_take > species.set_max:
				_settle()
				return SetResult.TOO_LATE
			state = State.HOOKED
			return SetResult.HOOKED
	return SetResult.NO_FISH


## Broke off: gone for a moment, then a fish takes the lie again. Landed
## (`landed` true): out of the water for the rest of the session.
func leave(landed := false) -> void:
	state = State.CAUGHT if landed else State.GONE
	_timer = GONE_TIME
	pos = lie


func _settle() -> void:
	state = State.HOLDING
	pos = lie
