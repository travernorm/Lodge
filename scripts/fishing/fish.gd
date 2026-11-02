class_name Fish
extends RefCounted
## One trout holding in the stream. It watches flies drift down to it and decides
## whether to rise, refuse, or bolt, and it judges your hook set.
##
## update() returns an event name the scene can react to:
##   &"rising"      started coming up for the fly
##   &"take"        took the fly: the hook-set window is open
##   &"spat"        you waited too long and it spat the fly
##   &"refuse"      looked and turned away (wrong fly)
##   &"refuse_drag" turned away because the fly was dragging
##   &"spook"       bolted (heavy drag)

enum State { HOLDING, RISING, TAKEN, HOOKED, COOLDOWN, GONE }
enum SetResult { HOOKED, TOO_EARLY, TOO_LATE, NO_FISH }

const LOOK_UPSTREAM := 26.0  # px upstream it can see a fly coming
const DECIDE_AT := -6.0  # it decides once the fly is this close upstream
const LOOK_DOWNSTREAM := 4.0
const LOOK_SIDE := 9.0
const RISE_TIME := 0.35
const COOLDOWN_TIME := 4.0
const GONE_TIME := 10.0

var species: FishSpecies
var lie := Vector2.ZERO
## Where to draw it. Moves to the fly during a rise.
var pos := Vector2.ZERO
var length_in := 0.0
var state := State.HOLDING
## Time since the take, while TAKEN.
var since_take := 0.0

var _timer := 0.0
var _looked := false
var _rng: RandomNumberGenerator


func _init(p_species: FishSpecies, rng: RandomNumberGenerator) -> void:
	species = p_species
	_rng = rng
	respawn()


## Picks a new lie in its habitat, as a new fish.
func respawn() -> void:
	var a := species.lie_area
	lie = Vector2(_rng.randf_range(a.position.x, a.end.x), _rng.randf_range(a.position.y, a.end.y)).floor()
	pos = lie
	length_in = snappedf(_rng.randf_range(species.min_length_in, species.max_length_in), 0.5)
	state = State.HOLDING
	_looked = false


## Visible in the water (not off sulking somewhere).
func is_present() -> bool:
	return state != State.GONE


## A fresh cast landed. Returns true if it landed hard enough nearby to spook the fish.
func on_landing(at: Vector2, presentation: String) -> bool:
	_looked = false
	if state != State.HOLDING and state != State.COOLDOWN:
		return false
	var d := at.distance_to(lie)
	var spooked := d < 3.0 \
		or (presentation == "Splashy" and d < 18.0) \
		or (presentation == "Fair" and d < 7.0)
	if spooked:
		leave()
	return spooked


func update(dt: float, fly: Vector2, fly_id: StringName, drag: float, fly_on_water: bool) -> StringName:
	_timer -= dt
	match state:
		State.COOLDOWN:
			if _timer <= 0.0:
				state = State.HOLDING
		State.GONE:
			if _timer <= 0.0:
				respawn()
		State.HOLDING:
			if fly_on_water and not _looked:
				return _judge(fly, fly_id, drag)
		State.RISING:
			if not fly_on_water:
				_cooldown()
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
				_cooldown()
				return &"spat"
	return &""


## The player flicked to set the hook.
func try_set() -> SetResult:
	match state:
		State.RISING:
			leave()
			return SetResult.TOO_EARLY
		State.TAKEN:
			if since_take < species.set_min:
				leave()
				return SetResult.TOO_EARLY
			if since_take > species.set_max:
				_cooldown()
				return SetResult.TOO_LATE
			state = State.HOOKED
			return SetResult.HOOKED
	return SetResult.NO_FISH


## Spooked, broke off, or released: gone for a while, then a new fish takes the lie.
func leave() -> void:
	state = State.GONE
	_timer = GONE_TIME
	pos = lie


func _judge(fly: Vector2, fly_id: StringName, drag: float) -> StringName:
	var dx := fly.x - lie.x
	if absf(fly.y - lie.y) > LOOK_SIDE or dx < -LOOK_UPSTREAM or dx > LOOK_DOWNSTREAM:
		return &""
	if dx < DECIDE_AT:
		return &""
	_looked = true
	if drag > species.drag_tolerance:
		if drag > 0.6 and _rng.randf() < 0.5:
			leave()
			return &"spook"
		_cooldown()
		return &"refuse_drag"
	var chance := species.take_chance if species.preferred_flies.has(String(fly_id)) else species.off_pattern_take
	if _rng.randf() < chance:
		state = State.RISING
		_timer = RISE_TIME
		return &"rising"
	_cooldown()
	return &"refuse"


func _cooldown() -> void:
	state = State.COOLDOWN
	_timer = COOLDOWN_TIME
	pos = lie
