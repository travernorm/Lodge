class_name FightModel
extends RefCounted
## Playing a hooked fish, as pure logic.
##
## Push the right stick to put the rod's pressure on: the further you push, the
## harder you pull. Pressure reels the fish in and tires it, but pressure while it
## runs spikes the tension, and holding tension at the top snaps the tippet. Too
## little pressure for too long and it throws the hook. Pushing the stick against
## the direction it's running (side pressure) tires it faster.

enum Result { FIGHTING, LANDED, SNAPPED, THREW_HOOK }

const TENSION_RATE := 6.0  # how fast tension follows its target, per second
const SNAP_HOLD := 0.15  # seconds at full tension before the tippet breaks
const SLACK_LEVEL := 0.08
const SLACK_TIME := 1.6
const REEL_SPEED := 2.75  # m/s gained at full pressure
const RUN_SPEED := 3.75  # m/s a fresh fish takes on a run
const LAND_DISTANCE := 1.75  # m
const LAND_STAMINA := 0.25
const MAX_DISTANCE := 18.75  # m: run past this and it breaks off
const RUN_TIME := Vector2(0.6, 1.4)
const REST_TIME := Vector2(1.0, 2.2)

var species: FishSpecies
var tension := 0.0
var stamina := 1.0
var distance := 0.0
## Direction from the rod tip to the fish, in radians (-PI/2 is straight across).
var angle := -PI / 2.0
var running := true
## -1 running upstream (left), 1 downstream (right).
var run_dir := 1.0

var _phase_timer := 0.0
var _over := 0.0
var _slack := 0.0
var _rng: RandomNumberGenerator


func _init(p_species: FishSpecies, start_distance: float, start_angle: float, rng: RandomNumberGenerator) -> void:
	species = p_species
	distance = start_distance
	angle = start_angle
	_rng = rng
	# Every fish bolts the moment it feels the hook.
	running = true
	run_dir = 1.0 if _rng.randf() < 0.6 else -1.0
	_phase_timer = _rng.randf_range(RUN_TIME.x, RUN_TIME.y)


## How hard the fish is pulling right now, 0..~1.5.
func effort() -> float:
	return (1.0 if running else 0.25) * species.pull * lerpf(0.35, 1.0, stamina)


func update(dt: float, stick: Vector2) -> Result:
	_phase_timer -= dt
	if _phase_timer <= 0.0:
		running = not running
		if running:
			run_dir = -run_dir if _rng.randf() < 0.5 else run_dir
			_phase_timer = _rng.randf_range(RUN_TIME.x, RUN_TIME.y)
		else:
			_phase_timer = _rng.randf_range(REST_TIME.x, REST_TIME.y)

	var pressure := clampf(stick.length(), 0.0, 1.0)
	var e := effort()
	tension = move_toward(tension, pressure * (0.3 + e), TENSION_RATE * dt)

	var side := clampf(-stick.x * run_dir, 0.0, 1.0) if running else 0.0
	stamina = maxf(0.0, stamina - dt * (0.03 + tension * 0.12 + side * 0.08) / species.toughness)

	var away := e * RUN_SPEED * (1.0 if running else 0.3)
	distance = maxf(0.0, distance + (away - pressure * REEL_SPEED) * dt)
	if running:
		angle = clampf(angle + run_dir * e * 0.6 * dt, -PI + 0.25, -0.25)

	_over = _over + dt if tension >= 0.999 else 0.0
	if _over >= SNAP_HOLD or distance > MAX_DISTANCE:
		return Result.SNAPPED
	_slack = _slack + dt if tension < SLACK_LEVEL else 0.0
	if _slack >= SLACK_TIME:
		return Result.THREW_HOOK
	if distance <= LAND_DISTANCE and stamina <= LAND_STAMINA:
		return Result.LANDED
	return Result.FIGHTING
