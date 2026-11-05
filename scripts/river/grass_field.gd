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
## Clumps still moving (index -> true), so a step only visits those and the
## ones by the angler, however much grass the stretch has.
var _awake := {}
var _angler := Vector2.INF
var _time := 0.0


## Grows the grass for every GrassPatch (and GrassBank) in the river's
## features. Where patches overlap, the first one in the list decides, so
## overlaps don't double up. `kinds` is how many clump sprites there are.
static func grow(river: RiverField, look: GrassLook, rng: RandomNumberGenerator, kinds := 1) -> GrassField:
	var patches: Array[GrassPatch] = []
	for feat in river.features:
		if feat is GrassPatch and (feat as GrassPatch).density * look.density > 0.0:
			patches.append(feat)
	var world := Rect2(0.0, river.top, river.cols * RiverField.CELL, river.rows * RiverField.CELL)
	if patches.is_empty():
		return GrassField.new()
	var dist := WaterDistance.new(river, world)
	var found: Array[Vector4] = []
	for n in patches.size():
		var g := patches[n]
		var cell := 1.0 / sqrt(g.density * look.density)
		var box := g.area(world).intersection(world)
		var y := box.position.y + cell * 0.5
		while y < box.end.y:
			var x := box.position.x + cell * 0.5
			while x < box.end.x:
				var p := Vector2(x, y) + Vector2(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.45, 0.45)) * cell
				var k := rng.randi_range(0, maxi(kinds, 1) - 1)
				var ph := rng.randf() * TAU
				var d := dist.at(p)
				if g.grows_at(p, d) and is_land(river, p) and not _earlier(patches, n, p, d):
					found.append(Vector4(p.x, p.y, k, ph))
				x += cell
			y += cell
	found.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.y < b.y)
	var f := GrassField.new()
	for c in found:
		f.add(Vector2(c.x, c.y), int(c.z), c.w)
	return f


static func _earlier(patches: Array[GrassPatch], n: int, p: Vector2, d: float) -> bool:
	for m in n:
		if patches[m].grows_at(p, d):
			return true
	return false


## True where grass can grow: dry, not under a rock or log, clear of the
## water, and not on the gravel or the cut bank at the water's edge (the same
## edge the stream scene paints: wider on the inside of a bend, the point bar).
static func is_land(river: RiverField, p: Vector2) -> bool:
	if river.is_water(p) or river.is_solid(p):
		return false
	if not river.shore.is_empty():
		var i := clampi(roundi(p.x / RiverField.CELL), 0, river.cols - 1)
		var j := clampi(roundi((p.y - river.top) / RiverField.CELL), 0, river.rows - 1)
		if river.shore[j * river.cols + i] < SHORE_GAP_M + 3.0 * maxf(-river.bend[j * river.cols + i], 0.0):
			return false
	for a in 8:
		if river.is_water(p + Vector2.from_angle(a * TAU / 8.0) * SHORE_GAP_M):
			return false
	return true


## The first clump at or below `y` (m), by binary search on the drawing order.
func first_at(y: float) -> int:
	var lo := 0
	var hi := pos.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if pos[mid].y < y:
			lo = mid + 1
		else:
			hi = mid
	return lo


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
	return _awake.is_empty()


func _settle(h: float, angler: Vector2, moving: float, push: Push, look: GrassLook) -> void:
	var r := maxf(look.push_radius_m, 0.01)
	var omega := TAU / maxf(look.spring_seconds, 0.05)
	var k := omega * omega
	var c := 2.0 * look.damping * omega
	for i in range(first_at(angler.y - r), first_at(angler.y + r)):
		if absf(pos[i].x - angler.x) < r:
			_awake[i] = true
	for i: int in _awake.keys():
		var d := pos[i] - angler
		var near := 0.0
		if d.length_squared() < r * r:
			near = 1.0 - smoothstep(0.0, r, d.length())
		if near == 0.0 and _hold[i] <= 0.0 and flat[i] == 0.0 \
				and absf(bend[i]) < REST and absf(vel[i]) < REST:
			bend[i] = 0.0
			vel[i] = 0.0
			_awake.erase(i)
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


## How far each point is from the water (m), on a 1 m grid: a two-pass chamfer
## over the river's water mask, built once when the grass grows.
class WaterDistance:
	const CELL := 1.0
	var _origin: Vector2
	var _cols: int
	var _rows: int
	var _d := PackedFloat32Array()

	func _init(river: RiverField, world: Rect2) -> void:
		_origin = world.position
		_cols = maxi(ceili(world.size.x / CELL), 1)
		_rows = maxi(ceili(world.size.y / CELL), 1)
		_d.resize(_cols * _rows)
		for j in _rows:
			for i in _cols:
				var water := river.is_water(_origin + (Vector2(i, j) + Vector2(0.5, 0.5)) * CELL)
				_d[j * _cols + i] = 0.0 if water else INF
		_sweep([Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(1, -1)], false)
		_sweep([Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)], true)

	func _sweep(steps: Array, backward: bool) -> void:
		for jj in _rows:
			var j := _rows - 1 - jj if backward else jj
			for ii in _cols:
				var i := _cols - 1 - ii if backward else ii
				var best := _d[j * _cols + i]
				for s: Vector2i in steps:
					var a := i + s.x
					var b := j + s.y
					if a >= 0 and b >= 0 and a < _cols and b < _rows:
						best = minf(best, _d[b * _cols + a] + CELL * Vector2(s).length())
				_d[j * _cols + i] = best

	func at(p: Vector2) -> float:
		var g := ((p - _origin) / CELL).floor()
		var i := clampi(int(g.x), 0, _cols - 1)
		var j := clampi(int(g.y), 0, _rows - 1)
		return _d[j * _cols + i]
