extends SceneTree
## Runs the fish generator (REQ-0007) on any stretch and prints what it makes:
## the day, the hatch that's on, and one row per fish. With --runs it rolls
## many seeds and prints a summary instead, for tuning a stretch's abundance
## and fish_per_100m before you play it.
##
##   godot --headless --path . --script res://tools/generate_fish.gd -- \
##     --stretch demo_freestone --season summer --day 12 --slot dusk \
##     --weather overcast --high 80 --seed 42
##   godot --headless --path . --script res://tools/generate_fish.gd -- --runs 100
##
## Every option is optional. Leave out the day's options to roll them from the
## seed, the way the game does; give some to pin those and roll the rest.
## --stretch is a stretch id from the catalog (the first one if left out).
## --high is the day's air high before the weather, as a band's lower °F.

const CALENDAR := "res://data/calendar.tres"


func _initialize() -> void:
	var out := run(OS.get_cmdline_user_args())
	for line in out:
		print(line)
	quit(1 if not out.is_empty() and out[0].begins_with("error") else 0)


## Runs the tool with command-line style arguments and returns its lines.
## The first line starts with "error" when the arguments are wrong.
static func run(args: PackedStringArray) -> PackedStringArray:
	var opts := _parse(args)
	if opts.has("error"):
		return PackedStringArray(["error: " + opts.error])
	var catalog := Catalog.shared()
	var stretch: Stretch = null
	for st in catalog.stretches:
		if opts.get("stretch", "") in ["", st.resource_path.get_file().get_basename()]:
			stretch = st
			break
	if stretch == null:
		return PackedStringArray(["error: no stretch '%s' in the catalog" % opts.get("stretch", "")])
	var calendar := load(CALENDAR) as Calendar
	var field := RiverField.new()
	field.build_stretch(stretch)
	var generator := FishGenerator.new(stretch, field, calendar)
	var name := stretch.resource_path.get_file().get_basename()
	var first_seed := int(opts.get("seed", "1"))
	var runs := int(opts.get("runs", "1"))
	if runs <= 1:
		return _one(generator, calendar, opts, first_seed, name)
	return _summary(generator, calendar, opts, first_seed, runs, name)


static func _one(generator: FishGenerator, calendar: Calendar, opts: Dictionary, p_seed: int, name: String) -> PackedStringArray:
	var rng := FishGenerator.seeded(p_seed)
	var day := _day(calendar, opts, rng, generator.stretch.spring_fed)
	var plans := generator.generate(day, rng)
	var lines := PackedStringArray(["%s  (%.0f m of river, %d lie cells)" % [name, generator.stretch.river_length_m(), generator.lie_cells()]])
	lines.append_array(FishGenerator.describe_day(generator, day, p_seed))
	lines.append("%d fish" % plans.size())
	lines.append("  %-20s %8s  %-14s %6s %9s" % ["species", "length", "lie (m)", "score", "activity"])
	for p in plans:
		lines.append("  %-20s %6.1f in  (%5.1f, %5.1f)  %5.2f %9.2f" % [p.species.display_name, p.length_in, p.lie.x, p.lie.y, p.lie_score, p.activity])
	return lines


static func _summary(generator: FishGenerator, calendar: Calendar, opts: Dictionary, first_seed: int,
		runs: int, name: String) -> PackedStringArray:
	var by_species := {}
	var total := 0
	for n in runs:
		var rng := FishGenerator.seeded(first_seed + n)
		var day := _day(calendar, opts, rng, generator.stretch.spring_fed)
		for p in generator.generate(day, rng):
			total += 1
			var s: Dictionary = by_species.get(p.species.display_name, {"count": 0, "sum": 0.0, "max": 0.0, "act": 0.0})
			s.count += 1
			s.sum += p.length_in
			s.max = maxf(s.max, p.length_in)
			s.act += p.activity
			by_species[p.species.display_name] = s
	var lines := PackedStringArray(["%s  %d runs from seed %d: %.1f fish a day" % [name, runs, first_seed, float(total) / runs]])
	lines.append("  %-20s %6s %10s %9s %9s" % ["species", "share", "avg len", "biggest", "activity"])
	for sp in by_species:
		var s: Dictionary = by_species[sp]
		lines.append("  %-20s %5.0f%% %7.1f in %6.1f in %9.2f" % [sp, 100.0 * s.count / maxi(total, 1), s.sum / s.count, s.max, s.act / s.count])
	return lines


## The day from the options: each one given is pinned, the rest rolled in
## the same order as Conditions.roll(), so with none pinned a seed gives the
## same day as in the game. Then it skips the game's take-roll seed, so the
## fish match too.
static func _day(calendar: Calendar, opts: Dictionary, rng: RandomNumberGenerator, spring_fed: bool) -> Conditions:
	var season: int = opts.get("season", rng.randi_range(0, 3))
	var day := int(opts.get("day", rng.randi_range(1, Calendar.DAYS_PER_SEASON)))
	var slot: int = opts.get("slot", rng.randi_range(0, Calendar.Slot.size() - 1))
	var weather: int = opts.get("weather", Conditions.pick_weather(calendar.weather_odds(season), rng))
	var bands := (calendar.high_max_f[season] - calendar.high_min_f[season]) / Calendar.BAND
	var high := int(opts.get("high", calendar.high_min_f[season] + rng.randi_range(0, bands) * Calendar.BAND))
	rng.randi()
	return Conditions.at(calendar, season, day, slot, weather, high, spring_fed)


## "--key value" pairs. Season, slot and weather names become their enums.
static func _parse(args: PackedStringArray) -> Dictionary:
	var opts := {}
	var enums := {"season": Calendar.Season, "slot": Calendar.Slot, "weather": Calendar.Weather}
	var i := 0
	while i < args.size():
		var key := args[i].trim_prefix("--")
		if not args[i].begins_with("--") or i + 1 >= args.size():
			return {"error": "expected --option value, got '%s'" % args[i]}
		var value := args[i + 1]
		if enums.has(key):
			var names: Array = enums[key].keys()
			var at := names.find(value.to_upper())
			if at < 0:
				return {"error": "%s must be one of %s" % [key, ", ".join(names).to_lower()]}
			opts[key] = at
		elif key in ["stretch", "seed", "runs", "day", "high"]:
			opts[key] = value
		else:
			return {"error": "unknown option --%s" % key}
		i += 2
	return opts
