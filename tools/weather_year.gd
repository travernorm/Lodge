extends SceneTree
## Prints a year of weather from a climate (REQ-0008): one row per day with
## its weather, intensity, high and spell, then a summary per season (each
## weather's share of the days and the average spell), so a climate can be
## tuned before you play it. With --years it summarises many seeds instead.
##
##   godot --headless --path . --script res://tools/weather_year.gd -- --seed 42
##   godot --headless --path . --script res://tools/weather_year.gd -- --climate central_oregon --years 100
##
## --climate is a file name in data/climates/ (the first one if left out).

const CLIMATES := "res://data/climates/"
const CALENDAR := "res://data/calendar.tres"


func _initialize() -> void:
	var out := run(OS.get_cmdline_user_args())
	for line in out:
		print(line)
	quit(1 if not out.is_empty() and out[0].begins_with("error") else 0)


## The climate files in data/climates/, by name.
static func climates() -> PackedStringArray:
	var names := PackedStringArray()
	for f in DirAccess.get_files_at(CLIMATES):
		if f.ends_with(".tres"):
			names.append(f.get_basename())
	names.sort()
	return names


## Runs the tool with command-line style arguments and returns its lines.
## The first line starts with "error" when the arguments are wrong.
static func run(args: PackedStringArray) -> PackedStringArray:
	var opts := {}
	for i in range(0, args.size(), 2):
		var key := args[i].trim_prefix("--")
		if not args[i].begins_with("--") or i + 1 >= args.size() or not key in ["climate", "seed", "years"]:
			return PackedStringArray(["error: expected --climate, --seed or --years with a value, got '%s'" % args[i]])
		opts[key] = args[i + 1]
	var names := climates()
	var name: String = opts.get("climate", names[0] if not names.is_empty() else "")
	if not name in names:
		return PackedStringArray(["error: no climate '%s' in %s" % [name, CLIMATES]])
	var climate := load(CLIMATES + name + ".tres") as Climate
	var calendar := load(CALENDAR) as Calendar
	var first_seed := int(opts.get("seed", "1"))
	var years := maxi(int(opts.get("years", "1")), 1)
	var all: Array[WeatherYear] = []
	for n in years:
		all.append(WeatherGenerator.year(climate, calendar, first_seed + n))
	var lines := PackedStringArray()
	if years == 1:
		lines.append("%s  seed %d" % [name, first_seed])
		lines.append("  %-10s %-9s %9s %5s  %s" % ["day", "weather", "intensity", "high", "spell"])
		for d in all[0].days:
			var storm := "  storm from %s" % _slot_name(d) if d.weather == Calendar.Weather.STORM else ""
			lines.append("  %-10s %-9s %9.1f %4ds  %d of %d%s" % [Calendar.date_name(d.season, d.day),
				_weather_name(d.weather), d.intensity, d.high_f, d.spell_day, d.spell_length, storm])
	else:
		lines.append("%s  %d years from seed %d" % [name, years, first_seed])
	lines.append_array(summary(all))
	return lines


## Per season: each weather's share of the days, the average spell, and the
## average high on days 1 to 10 and 21 to 30.
static func summary(years: Array[WeatherYear]) -> PackedStringArray:
	var head := "  %-7s" % "season"
	for w in Calendar.Weather.size():
		head += " %8s" % _weather_name(w)
	var lines := PackedStringArray([head + "   spell  early  late"])
	for s in Calendar.Season.size():
		var counts := PackedInt32Array()
		counts.resize(Calendar.Weather.size())
		var spells := 0
		var days := 0
		var early := 0.0
		var late := 0.0
		for y in years:
			for d in y.days:
				if d.season != s:
					continue
				days += 1
				counts[d.weather] += 1
				spells += 1 if d.spell_day == 1 or d.day == 1 else 0
				early += d.high_f if d.day <= 10 else 0
				late += d.high_f if d.day > 20 else 0
		var row := "  %-7s" % String(Calendar.Season.keys()[s]).capitalize()
		for w in Calendar.Weather.size():
			row += " %7.0f%%" % (100.0 * counts[w] / maxi(days, 1))
		var per_year := 10.0 * years.size()
		row += "  %4.1f d  %4.0f  %4.0f" % [float(days) / maxi(spells, 1), early / per_year, late / per_year]
		lines.append(row)
	return lines


static func _weather_name(w: int) -> String:
	return String(Calendar.Weather.keys()[w]).capitalize()


static func _slot_name(d: WeatherDay) -> String:
	for s in Calendar.Slot.size():
		if d.weather_in(s) == Calendar.Weather.STORM:
			return String(Calendar.Slot.keys()[s]).capitalize()
	return "-"
