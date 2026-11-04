class_name Calendar
extends Resource
## The game year's rules, as data (REQ-0007, docs/SPECIES_AND_CONDITIONS.md):
## four 30-day seasons, six time slots, five weathers, and temperature in 10°F
## bands. Its one file is data/calendar.tres. A region's weather is its
## Climate (REQ-0008); the calendar keeps how slots cool the air, how the water
## follows it, and the fish generator's activity factors.
##
## Temperatures are the lower °F of a band: 50 means "the 50s".

enum Season { SPRING, SUMMER, FALL, WINTER }
enum Slot { DAWN, MORNING, NOON, AFTERNOON, DUSK, NIGHT }
enum Weather { SUNNY, OVERCAST, RAIN, SNOW, STORM }

const DAYS_PER_SEASON := 30
const BAND := 10
const AIR_MIN_F := 30
const AIR_MAX_F := 100
## Water never leaves these bands; spring-fed water stays in the second range.
const WATER_RANGE_F := Vector2i(30, 70)
const SPRING_FED_RANGE_F := Vector2i(40, 50)

@export_group("Temperature")
## Bands below the day's high, per slot (Dawn ... Night).
@export var slot_drop := PackedInt32Array([2, 1, 0, 0, 1, 2])
## Water is the day's high minus this many bands, kept in WATER_RANGE_F.
@export var water_drop := 2

@export_group("Fish activity")
## How keen fish are to rise in each slot (Dawn ... Night), 0 to 1.
@export var slot_activity := PackedFloat32Array([0.8, 0.9, 0.6, 0.7, 1.0, 0.3])
## And in each weather (Sunny ... Storm).
@export var weather_activity := PackedFloat32Array([0.7, 1.0, 0.9, 0.5, 0.4])
## A fish with no hatch to eat still has this much appetite, before the slot
## and weather factors.
@export_range(0.0, 1.0) var base_appetite := 0.3
## Activity never drops below this, so every fish rises now and then.
@export_range(0.0, 1.0) var min_activity := 0.1


## The day of the year, 0 (Spring 1) to 119 (Winter 30).
static func day_of_year(season: Season, day: int) -> int:
	return int(season) * DAYS_PER_SEASON + clampi(day, 1, DAYS_PER_SEASON) - 1


## "Summer 12".
static func date_name(season: Season, day: int) -> String:
	return "%s %d" % [String(Season.keys()[season]).capitalize(), day]
