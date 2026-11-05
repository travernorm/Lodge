class_name GrassField
extends RefCounted
## The tall grass on a stretch (REQ-0012): where each clump grows, and how far
## the angler has bent it. GrassView draws it; this model holds the rules.
##
## Clumps grow on a jittered grid inside each GrassPatch, only on land and not
## within SHORE_GAP_M of the water. Each clump is a damped spring: the angler
## pushes its top away (variant A, lean), walks it flat for a while (B, trail),
## or makes it shiver (C, rustle), and it swings back upright with a little
## overshoot. The wind's lean (Wind) is added on top when drawing, so a clump
## at rest costs nothing to update.
##
## Leans are a share of the clump's height: 1 moves its top sideways by a full
## height. + leans right on screen. Positions are metres (R11).

## How the grass reacts to the angler walking through. The feel experiment.
enum Push { LEAN, TRAIL, RUSTLE }
const PUSH_NAMES: Array[String] = ["A lean", "B part and trail", "C rustle"]

## Grass keeps this far (m) from the water.
const SHORE_GAP_M := 1.0
## Physics step (s); longer frames are split so the springs stay stable.
const STEP := 1.0 / 60.0
## Below this a clump counts as at rest.
const REST := 0.0005
## Variant C: how hard the brush-past shakes a clump, and how fast (rad/s).
const RUSTLE_FORCE := 260.0
const RUSTLE_RATE := 37.0
## Walking this fast (m/s) or faster brushes the grass fully (variant C).
const BRUSH_SPEED := 2.0
## Variant B: the angler flattens a clump when this close (share of the radius).
const TRAMPLE := 0.35

## Per clump, in drawing order (top of the screen first).
var pos := PackedVector2Array()
var kind := PackedByteArray()
var phase := PackedFloat32Array()
var bend := PackedFloat32Array()
var vel := PackedFloat32Array()
var flat := PackedFloat32Array()

var _hold := PackedFloat32Array()
var _angler := Vector2.INF
var _time := 0.0


## Grows the grass for every GrassPatch in the river's features. `kinds` is how
## many clump sprites there are to pick from.
static func grow(river: RiverField, look: GrassLook, rng: RandomNumberGenerator, kinds := 1) -> GrassField:
	var found: Array[Vector4] = []
	for feat in river.features:
		var g := feat as GrassPatch
		if g == null or g.density * look.density <= 0.0:
			continue
		var cell := 1.0 / sqrt(g.density * look.density)
		var box := g.bounds()
		var y := box.position.y + cell * 0.5
		while y < box.end.y:
			var x := box.position.x + cell * 0.5
			while x < box.end.x:
				var p := Vector2(x, y) + Vector2(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.45, 0.45)) * cell
				var k := rng.randi_range(0, maxi(kinds, 1) - 1)
				var ph := rng.randf() * TAU
				if g.contains(p) and is_land(river, p):
					found.append(Vector4(p.x, p.y, k, ph))
				x += cell
			y += cell
	found.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.y < b.y)
	var f := GrassField.new()
	for c in found:
		f.add(Vector2(c.x, c.y), int(c.z), c.w)
	return f


## True where grass can grow: dry, not under a rock or log, and clear of the water.
static func is_land(river: RiverField, p: Vector2) -> bool:
	if river.is_water(p) or river.is_solid(p):
		return false
	for a in 8:
		if river.is_water(p + Vector2.from_angle(a * TAU / 8.0) * SHORE_GAP_M):
			return false
	return true


func add(p: Vector2, p_kind := 0, p_phase := 0.0) -> void:
	pos.append(p)
	kind.append(p_kind)
	phase.append(p_phase)
	bend.append(0.0)
	vel.append(0.0)
	flat.append(0.0)
	_hold.append(0.0)


func size() -> int:
	return pos.size()


## Moves every clump on by `delta` seconds with the angler standing at `angler` (m).
func step(delta: float, angler: Vector2, push: Push, look: GrassLook) -> void:
	var moving := 0.0
	if _angler != Vector2.INF and delta > 0.0:
		moving = clampf(angler.distance_to(_angler) / delta / BRUSH_SPEED, 0.0, 1.0)
	_angler = angler
	var left := delta
	while left > 0.000001:
		var h := minf(left, STEP)
		_time += h
		_settle(h, angler, moving, push, look)
		left -= h


## The clump's sideways lean on screen: the angler's push plus the wind, the
## wind softened where the clump lies flat.
func sway(i: int, wind: Wind, look: GrassLook) -> float:
	var w := 0.0
	if wind != null:
		w = wind.sway_at(pos[i]) * look.wind_lean * (0.8 + 0.2 * sin(phase[i]))
	return clampf(bend[i] + w * (1.0 - 0.7 * flat[i]), -1.5, 1.5)


## True when nothing near the angler is still moving.
func is_still() -> bool:
	for i in pos.size():
		if absf(bend[i]) > REST or absf(vel[i]) > REST or flat[i] > 0.0:
			return false
	return true


func _settle(h: float, angler: Vector2, moving: float, push: Push, look: GrassLook) -> void:
	var r := maxf(look.push_radius_m, 0.01)
	var omega := TAU / maxf(look.spring_seconds, 0.05)
	var k := omega * omega
	var c := 2.0 * look.damping * omega
	for i in pos.size():
		var d := pos[i] - angler
		var near := 0.0
		if d.length_squared() < r * r:
			near = 1.0 - smoothstep(0.0, r, d.length())
		if near == 0.0 and _hold[i] <= 0.0 and flat[i] == 0.0 \
				and absf(bend[i]) < REST and absf(vel[i]) < REST:
			bend[i] = 0.0
			vel[i] = 0.0
			continue
		var side := signf(d.x) if absf(d.x) > 0.05 else (1.0 if phase[i] < PI else -1.0)
		var target := side * look.push_lean * near
		if push == Push.TRAIL:
			target *= 0.5
			if near > TRAMPLE:
				_hold[i] = look.trail_seconds
				flat[i] = move_toward(flat[i], look.flatten, h * 6.0)
			elif _hold[i] > 0.0:
				_hold[i] -= h
			else:
				flat[i] = move_toward(flat[i], 0.0, h / maxf(look.spring_seconds, 0.05))
		else:
			_hold[i] = 0.0
			flat[i] = move_toward(flat[i], 0.0, h / maxf(look.spring_seconds, 0.05))
		if push == Push.RUSTLE:
			target *= 0.25
			vel[i] += sin(_time * RUSTLE_RATE + phase[i] * 5.0) * look.rustle * near * moving * RUSTLE_FORCE * h
		vel[i] += (-k * (bend[i] - target) - c * vel[i]) * h
		bend[i] += vel[i] * h
