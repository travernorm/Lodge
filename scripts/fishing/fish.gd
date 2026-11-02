class_name Fish
extends RefCounted
## One trout holding in the stream.
##
## It holds where the river field says a trout would: slow, deep-enough water
## with fast water close by (see RiverField.pick_lie()). Without a river field it
## picks any spot in its species' lie_area.
##
## Bites are a simple roll per cast: when the fly lands, the fish works out a bite
## chance from how close the fly landed and how softly (see bite_chance_for()).
## If the roll succeeds, it rises to the fly a moment later. Then you have to set
## the hook in its window.
##
## update() returns an event name the scene can react to:
##   &"dimple"  a natural rise at its lie, so you can see where it is
##   &"rising"  coming up for your fly
##   &"take"    took the fly: the hook-set window is open
##   &"spat"    you waited too long and it spat the fly

enum State { HOLDING, WAITING, RISING, TAKEN, HOOKED, GONE }
enum SetResult { HOOKED, TOO_EARLY, TOO_LATE, NO_FISH }

const PRESENTATION_FACTOR := {"Delicate": 1.0, "Fair": 0.6, "Splashy": 0.25}
const CLOSE_RANGE := 8.0  # px: inside this the distance doesn't lower the chance
const RISE_TIME := 0.35
const BITE_DELAY := Vector2(0.6, 2.0)  # seconds after landing before it rises
const DIMPLE_EVERY := Vector2(3.0, 6.0)
const GONE_TIME := 4.0

## Only lies scoring at least this in the river field are taken.
const MIN_LIE_SCORE := 0.4

var species: FishSpecies
## Where it holds the rest of the time.
var lie := Vector2.ZERO
## The river it lives in; optional.
var river: RiverField
## Where to draw it. Moves to the fly during a rise.
var pos := Vector2.ZERO
var length_in := 0.0
var state := State.HOLDING
## Time since the take, while TAKEN.
var since_take := 0.0
## The bite chance rolled for the last cast that landed.
var last_bite_chance := 0.0

var _timer := 0.0
var _dimple_timer := 0.0
var _rng: RandomNumberGenerator


func _init(p_species: FishSpecies, rng: RandomNumberGenerator, p_river: RiverField = null) -> void:
	species = p_species
	_rng = rng
	river = p_river
	respawn()


## Picks a new lie in its habitat, as a new fish.
func respawn() -> void:
	var a := species.lie_area
	var spot := Vector2.INF
	if river != null:
		spot = river.pick_lie(a, _rng, MIN_LIE_SCORE)
	if spot == Vector2.INF:
		spot = Vector2(_rng.randf_range(a.position.x, a.end.x), _rng.randf_range(a.position.y, a.end.y))
	lie = spot.floor()
	pos = lie
	length_in = snappedf(_rng.randf_range(species.min_length_in, species.max_length_in), 0.5)
	state = State.HOLDING
	_dimple_timer = _rng.randf_range(0.5, DIMPLE_EVERY.y)


## Visible in the water (not gone off somewhere).
func is_present() -> bool:
	return state != State.GONE


## 0..1 chance this fish bites a fly landing at `at` with the given presentation.
func bite_chance_for(at: Vector2, presentation: String) -> float:
	var d := at.distance_to(lie)
	if d > species.bite_range:
		return 0.0
	var closeness := 1.0 - clampf((d - CLOSE_RANGE) / (species.bite_range - CLOSE_RANGE), 0.0, 1.0)
	return species.bite_chance * closeness * PRESENTATION_FACTOR.get(presentation, 0.5)


## A cast landed: roll for a bite. Returns the chance that was rolled.
func on_landing(at: Vector2, presentation: String) -> float:
	if state == State.GONE or state == State.HOOKED:
		return 0.0
	last_bite_chance = bite_chance_for(at, presentation)
	if _rng.randf() < last_bite_chance:
		state = State.WAITING
		_timer = _rng.randf_range(BITE_DELAY.x, BITE_DELAY.y)
	else:
		_settle()
	return last_bite_chance


func update(dt: float, fly: Vector2, fly_on_water: bool) -> StringName:
	_timer -= dt
	match state:
		State.GONE:
			if _timer <= 0.0:
				respawn()
		State.HOLDING:
			_dimple_timer -= dt
			if _dimple_timer <= 0.0:
				_dimple_timer = _rng.randf_range(DIMPLE_EVERY.x, DIMPLE_EVERY.y)
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


## Landed or broke off: gone for a moment, then a fish takes the lie again.
func leave() -> void:
	state = State.GONE
	_timer = GONE_TIME
	pos = lie


func _settle() -> void:
	state = State.HOLDING
	pos = lie
