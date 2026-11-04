class_name FishGenerator
extends RefCounted
## Stocks a stretch for one day (REQ-0007, FISH_LOGIC.md step 1). Give it any
## stretch and its river field once; then generate() turns a day's Conditions
## and a seeded RNG into fish: which species, how big, and which lie each one
## holds. The same stretch, day and seed always give the same fish.
##
##   1. Who can be here: spawn entries in season whose species suits the water.
##   2. How many: the stretch's fish_count(), as far as the lies allow.
##   3. Which species: each fish picks one, weighted by abundance.
##   4. Size and lie: lengths lean small, and the biggest fish get the best
##      lies, with a little noise.
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
## Every cell that could hold a fish: x, y (m) and the lie score.
var _cells := PackedVector3Array()
## Running total of score², for picking better lies more often.
var _cumulative := PackedFloat32Array()


## Scans the river field once for lies. With no field there are no lies, so
## generate() gives no fish.
func _init(p_stretch: Stretch, field: RiverField, p_calendar: Calendar) -> void:
	stretch = p_stretch
	calendar = p_calendar
	if field == null or stretch == null:
		return
	var bounds := Rect2(Vector2.ZERO, stretch.size_m)
	var total := 0.0
	for j in field.rows:
		for i in field.cols:
			var score := field.lie[j * field.cols + i]
			if score < MIN_LIE_SCORE:
				continue
			var p := field.cell_pos(i, j)
			if bounds.has_point(p) and field.is_water(p):
				_cells.append(Vector3(p.x, p.y, score))
				total += score * score
				_cumulative.append(total)


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
	var lies := _pick_lies(stretch.fish_count(), lie_rng)
	# Best lie first, with a little luck, then the biggest fish into it.
	var keyed: Array[Vector4] = []
	for l in lies:
		keyed.append(Vector4(l.x, l.y, l.z, l.z + lie_rng.randf_range(-LIE_NOISE, LIE_NOISE)))
	keyed.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.w > b.w)
	for n in keyed.size():
		var sp := pick_species(entries, species_rng)
		out.append(FishPlan.new(sp, roll_length(sp, size_rng), Vector2.ZERO, 0.0, activity(sp, c)))
	out.sort_custom(func(a: FishPlan, b: FishPlan) -> bool: return a.length_in > b.length_in)
	for n in out.size():
		out[n].lie = Vector2(keyed[n].x, keyed[n].y)
		out[n].lie_score = keyed[n].z
	return out


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


## A length (in, to the half inch) in the species' range, leaning small.
static func roll_length(sp: FishSpecies, rng: RandomNumberGenerator) -> float:
	var u := pow(rng.randf(), SIZE_SKEW)
	return snappedf(lerpf(sp.min_length_in, sp.max_length_in, u), 0.5)


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


## Up to `count` lies, better ones more likely (score²), each at least
## LIE_GAP from the others. Fewer if the water runs out.
func _pick_lies(count: int, rng: RandomNumberGenerator) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _cells.is_empty():
		return out
	var total := _cumulative[-1]
	for n in count:
		for t in LIE_TRIES:
			var k := mini(_cumulative.bsearch(rng.randf() * total), _cells.size() - 1)
			var cell := _cells[k]
			if _clear(cell, out):
				out.append(cell)
				break
	return out


static func _clear(cell: Vector3, taken: PackedVector3Array) -> bool:
	for o in taken:
		if Vector2(cell.x, cell.y).distance_to(Vector2(o.x, o.y)) < LIE_GAP:
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
