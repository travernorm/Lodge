class_name FishGenerator
extends RefCounted
## Stocks a stretch for one day (REQ-0007, FISH_LOGIC.md step 1). Give it any
## stretch and its river field once; then generate() turns a day's Conditions
## and a seeded RNG into fish: which species, how big, and which lie each one
## holds. The same stretch, day and seed always give the same fish.
##
##   1. Who can be here: spawn entries in season whose species suits the water.
##   2. How many: the stretch's fish_count(), as far as the lies allow.
##   3. Which species: each lie picks one, weighted by abundance times how
##      much the species likes that lie's kind of water (REQ-0010).
##   4. Size and lie: sizes lean small, and the best lies get the biggest,
##      with a little noise; a fish's size is a rank within its own species'
##      range. A lie is a feeding lie (RiverField.lie) or a resting lie
##      (RestingLies), and each reach of river gets its share of fish (REQ-0011).
##
## It also answers which hatches are on and how active each fish is, which is
## how the day shows: fish rise more in a good hatch on a good evening.

## Only lies scoring at least this in the river field hold a fish.
const MIN_LIE_SCORE := 0.4
## Fish keep at least this far (m) from each other's lies.
const LIE_GAP := 3.0
## Length leans toward the small end: min + range × u^SIZE_SKEW.
const SIZE_SKEW := 2.0
## How much luck there is in which lie a fish gets, on a 0..1 score.
const LIE_NOISE := 0.1
## Tries per fish to find a lie clear of the others.
const LIE_TRIES := 40

var stretch: Stretch
var calendar: Calendar
var water_rules: WaterTypeRules
## The river is shared out between reaches about this long (m) along the
## centreline, so every reach gets fish (REQ-0011).
const REACH_M := 40.0

## Resting lies (REQ-0011), scored once from the field.
var resting: RestingLies
## Every cell that could hold a fish: x, y (m) and its lie score, the better of
## feeding and resting.
var _cells := PackedVector3Array()
## Per cell: 1 when its resting score beats its feeding score.
var _rests := PackedByteArray()
## Running total of score², for picking better lies more often.
var _cumulative := PackedFloat32Array()
## Per candidate cell: its water type (WaterTypeRules.WaterType).
var _types := PackedByteArray()
## Per reach: its cells (indices into _cells), their running score² totals, and
## its length (m) inside the map.
var _reach_cells: Array[PackedInt32Array] = []
var _reach_cumulative: Array[PackedFloat32Array] = []
var _reach_len := PackedFloat32Array()
## Stocking one area of a section rather than the whole stretch.
var _area_mode := false


## Scans the river field once for lies. With no field there are no lies, so
## generate() gives no fish. With an `area` (m), only that part of the river is
## stocked, with fish_per_100m over the river's length inside it: one chunk of
## a streamed section (REQ-0014).
func _init(p_stretch: Stretch, field: RiverField, p_calendar: Calendar,
		p_rules: WaterTypeRules = null, area := Rect2()) -> void:
	stretch = p_stretch
	calendar = p_calendar
	water_rules = p_rules if p_rules != null else WaterTypeRules.shared()
	if field == null or stretch == null:
		return
	resting = RestingLies.new(field)
	var bounds := area if area.has_area() else Rect2(Vector2.ZERO, stretch.size_m)
	_area_mode = area.has_area()
	_measure_reaches(field, bounds)
	var total := 0.0
	for j in field.rows:
		for i in field.cols:
			var idx := j * field.cols + i
			var score := maxf(field.lie[idx], resting.rest[idx])
			if score < MIN_LIE_SCORE:
				continue
			var p := field.cell_pos(i, j)
			if bounds.has_point(p) and field.is_water(p):
				var reach := _reach_at(field, p)
				var k := _cells.size()
				_cells.append(Vector3(p.x, p.y, score))
				_types.append(WaterTypes.at(field, water_rules, p))
				_rests.append(1 if resting.rest[idx] > field.lie[idx] else 0)
				total += score * score
				_cumulative.append(total)
				var cells_here := _reach_cells[reach]
				cells_here.append(k)
				_reach_cells[reach] = cells_here
				var rc := _reach_cumulative[reach]
				rc.append((rc[-1] if not rc.is_empty() else 0.0) + score * score)
				_reach_cumulative[reach] = rc


## Each reach's length inside the map, from the centreline's points (one per
## RiverField.CHANNEL_STEP m). A field with no centreline is one reach.
func _measure_reaches(field: RiverField, bounds: Rect2) -> void:
	var count := maxi(ceili(field.centre.size() * RiverField.CHANNEL_STEP / REACH_M), 1)
	_reach_len.resize(count)
	_reach_len.fill(0.0)
	for k in field.centre.size():
		if bounds.has_point(field.centre[k]):
			_reach_len[_reach_index(k)] += RiverField.CHANNEL_STEP
	if field.centre.is_empty():
		_reach_len[0] = 1.0
	for r in count:
		_reach_cells.append(PackedInt32Array())
		_reach_cumulative.append(PackedFloat32Array())


func _reach_at(field: RiverField, p: Vector2) -> int:
	return 0 if field.centre.is_empty() else _reach_index(field.nearest_centre(p))


func _reach_index(k: int) -> int:
	return mini(floori(k * RiverField.CHANNEL_STEP / REACH_M), _reach_len.size() - 1)


## A generator for `p_stretch`, or null when there's no stretch.
static func for_stretch(p_stretch: Stretch, field: RiverField, p_calendar: Calendar) -> FishGenerator:
	return FishGenerator.new(p_stretch, field, p_calendar) if p_stretch != null else null


## How many cells could hold a fish.
func lie_cells() -> int:
	return _cells.size()


## The fish for one day. The rng is only used to seed three streams (species,
## size, lies), so changing one stage doesn't reshuffle the others.
func generate(c: Conditions, rng: RandomNumberGenerator) -> Array[FishPlan]:
	var species_rng := _stream(rng)
	var size_rng := _stream(rng)
	var lie_rng := _stream(rng)
	var out: Array[FishPlan] = []
	var entries := eligible(stretch.spawn, c)
	if entries.is_empty():
		return out
	var lies := _pick_lies(_area_count(lie_rng) if _area_mode else stretch.fish_count(), lie_rng)
	# Best lie first, with a little luck: (cell, noisy score). Each lie picks
	# a species that suits its water, and the best lies get the biggest ranks.
	var keyed: Array[Vector2] = []
	for k in lies:
		keyed.append(Vector2(k, _cells[k].z + lie_rng.randf_range(-LIE_NOISE, LIE_NOISE)))
	keyed.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y > b.y)
	var ranks: Array[float] = []
	for n in keyed.size():
		ranks.append(size_rank(size_rng))
	ranks.sort_custom(func(a: float, b: float) -> bool: return a > b)
	for n in keyed.size():
		var k := int(keyed[n].x)
		var type := _types[k]
		var sp := pick_species_for(entries, type, water_rules.stray_weight, species_rng)
		var plan := FishPlan.new(sp, length_at(sp, ranks[n]), Vector2(_cells[k].x, _cells[k].y), _cells[k].z, activity(sp, c), type)
		plan.resting = _rests[k] == 1
		out.append(plan)
	out.sort_custom(func(a: FishPlan, b: FishPlan) -> bool: return a.length_in > b.length_in)
	return out


## How many fish an area holds: fish_per_100m over the river's length inside
## it, the fraction rolled so that over many areas the total is right.
func _area_count(rng: RandomNumberGenerator) -> int:
	var length := 0.0
	for l in _reach_len:
		length += l
	var exact := stretch.fish_per_100m * length / 100.0
	return floori(exact) + (1 if rng.randf() < exact - floorf(exact) else 0)


## The spawn entries that can be in the water today: in season, and the water
## temperature suits the species.
static func eligible(entries: Array[SpawnEntry], c: Conditions) -> Array[SpawnEntry]:
	var out: Array[SpawnEntry] = []
	for e in entries:
		if e != null and e.species != null and SeasonWindow.allows(e.window, c.season, c.day) \
				and e.species.suits_water(c.water_f):
			out.append(e)
	return out


## One species, weighted by abundance.
static func pick_species(entries: Array[SpawnEntry], rng: RandomNumberGenerator) -> FishSpecies:
	var total := 0.0
	for e in entries:
		total += e.abundance
	var r := rng.randf() * total
	for e in entries:
		r -= e.abundance
		if r < 0.0:
			return e.species
	return entries[-1].species


## One species for a lie in water of `type`, weighted by abundance times how
## much the species likes that water (FishSpecies.habitat_for).
static func pick_species_for(entries: Array[SpawnEntry], type: int, stray: float,
		rng: RandomNumberGenerator) -> FishSpecies:
	var weights := PackedFloat32Array()
	var total := 0.0
	for e in entries:
		weights.append(e.abundance * e.species.habitat_for(type, stray))
		total += weights[-1]
	if total <= 0.0:
		return pick_species(entries, rng)
	var r := rng.randf() * total
	for k in entries.size():
		r -= weights[k]
		if r < 0.0:
			return entries[k].species
	return entries[-1].species


## A size rank, 0 (smallest) to 1 (biggest), leaning small.
static func size_rank(rng: RandomNumberGenerator) -> float:
	return pow(rng.randf(), SIZE_SKEW)


## The length (in, to the half inch) at size rank `u` in the species' range.
static func length_at(sp: FishSpecies, u: float) -> float:
	return snappedf(lerpf(sp.min_length_in, sp.max_length_in, u), 0.5)


## A length (in, to the half inch) in the species' range, leaning small.
static func roll_length(sp: FishSpecies, rng: RandomNumberGenerator) -> float:
	return length_at(sp, size_rank(rng))


## The stretch's hatches that are coming off in `c`.
func active_hatch(c: Conditions) -> Array[HatchEntry]:
	var out: Array[HatchEntry] = []
	for h in stretch.hatches:
		if h != null and h.is_on(c):
			out.append(h)
	return out


## How keen a fish of `sp` is to rise in `c`, 0 to 1: its appetite for the
## best hatch it eats (or the calendar's base appetite), times the slot and
## weather factors, never below the calendar's floor.
func activity(sp: FishSpecies, c: Conditions) -> float:
	var food := 0.0
	for h in active_hatch(c):
		food = maxf(food, h.strength * sp.wants(h.insect))
	var appetite := calendar.base_appetite + (1.0 - calendar.base_appetite) * food
	var a := appetite * calendar.slot_activity[c.slot] * calendar.weather_activity[c.weather]
	return clampf(a, calendar.min_activity, 1.0)


## How many fish each reach gets out of `count`: its share by length. The
## whole part is certain and the fractions are rolled, so the total is always
## `count` and over many days each reach gets its share. A reach with no lies
## passes its share to the nearest reach that has some.
func reach_quota(count: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var n := _reach_len.size()
	var quota := PackedInt32Array()
	quota.resize(n)
	quota.fill(0)
	var total := 0.0
	for r in n:
		total += _reach_len[r]
	if total <= 0.0 or n == 0:
		return quota
	var rest: Array[Vector2] = []
	var given := 0
	for r in n:
		var exact := count * _reach_len[r] / total
		quota[r] = floori(exact)
		given += quota[r]
		rest.append(Vector2(r, exact - quota[r]))
	for k in count - given:
		var weight := 0.0
		for e in rest:
			weight += e.y
		var roll := rng.randf() * weight
		var pick := rest.size() - 1
		for e_at in rest.size():
			roll -= rest[e_at].y
			if roll < 0.0:
				pick = e_at
				break
		quota[int(rest[pick].x)] += 1
		rest.remove_at(pick)
	for r in n:
		if quota[r] > 0 and _reach_cells[r].is_empty():
			var to := _nearest_reach_with_lies(r)
			if to >= 0:
				quota[to] += quota[r]
			quota[r] = 0
	return quota


## How many reaches the river is shared between.
func reach_count() -> int:
	return _reach_len.size()


## Which reach a lie (m) is in, for tests and the tool.
func reach_at(p: Vector2) -> int:
	return _reach_at(resting.field, p) if resting != null else 0


func _nearest_reach_with_lies(r: int) -> int:
	for d in range(1, _reach_len.size()):
		for to in [r - d, r + d]:
			if to >= 0 and to < _reach_len.size() and not _reach_cells[to].is_empty():
				return to
	return -1


## Up to `count` lies (indices into _cells), shared out by reach_quota(). In
## each reach better lies are more likely (score²), and every lie is at least
## LIE_GAP from the others. A reach that runs out of room passes what's left
## to the whole river; fewer fish if the water runs out.
func _pick_lies(count: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _cells.is_empty():
		return out
	var short := 0
	var quota := reach_quota(count, rng)
	for r in quota.size():
		for n in quota[r]:
			if not _pick_one(_reach_cells[r], _reach_cumulative[r], rng, out):
				short += 1
	var everywhere := PackedInt32Array()
	for n in short:
		_pick_one(everywhere, _cumulative, rng, out)
	return out


## Picks one cell from `cells` (indices into _cells; empty means every cell)
## weighted by `cumulative`, clear of `out`, and adds it. False if none fits.
func _pick_one(cells: PackedInt32Array, cumulative: PackedFloat32Array, rng: RandomNumberGenerator,
		out: PackedInt32Array) -> bool:
	if cumulative.is_empty():
		return false
	for t in LIE_TRIES:
		var at := mini(cumulative.bsearch(rng.randf() * cumulative[-1]), cumulative.size() - 1)
		var k := cells[at] if not cells.is_empty() else at
		if _clear(_cells[k], out):
			out.append(k)
			return true
	return false


func _clear(cell: Vector3, taken: PackedInt32Array) -> bool:
	for k in taken:
		if Vector2(cell.x, cell.y).distance_to(Vector2(_cells[k].x, _cells[k].y)) < LIE_GAP:
			return false
	return true


## Sets each fish's activity for new conditions on the same water (REQ-0008),
## for the hatch that's on now. `generator` may be null (no stretch, no fish).
static func refresh_activity(generator: FishGenerator, fish: Array[Fish], c: Conditions) -> void:
	for f in (fish if generator != null else []):
		f.activity = generator.activity(f.species, c)


## The debug overlay's lines for a day: the conditions, the spell, the hatch
## and the seed. `generator` may be null (no stretch, so no hatch), and so
## may `year` (a pinned day in a test).
static func describe_day(generator: FishGenerator, c: Conditions, p_seed: int, year: WeatherYear = null) -> PackedStringArray:
	var lines := c.describe()
	if year != null:
		lines[0] += "  (%s)" % year.describe(c)
	var names := PackedStringArray()
	for h in (generator.active_hatch(c) if generator != null else []):
		names.append(h.insect.display_name)
	lines.append("hatch  %s  seed %d" % [", ".join(names) if not names.is_empty() else "none", p_seed])
	return lines


## A new generator seeded with `p_seed`.
static func seeded(p_seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = p_seed
	return r


static func _stream(rng: RandomNumberGenerator) -> RandomNumberGenerator:
	return seeded(rng.randi())
