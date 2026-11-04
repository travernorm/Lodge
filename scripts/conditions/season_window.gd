class_name SeasonWindow
extends Resource
## A stretch of the year, from one season and day to another, both included
## (REQ-0007). It wraps across the new year, so "Fall 20 to Spring 10" works.
## Where a window is optional, leaving it empty means all year.

@export var from_season := Calendar.Season.SPRING
@export_range(1, 30) var from_day := 1
@export var to_season := Calendar.Season.WINTER
@export_range(1, 30) var to_day := 30


## True when the season and day fall inside the window.
func contains(season: Calendar.Season, day: int) -> bool:
	var d := Calendar.day_of_year(season, day)
	var a := Calendar.day_of_year(from_season, from_day)
	var b := Calendar.day_of_year(to_season, to_day)
	return (d >= a and d <= b) if a <= b else (d >= a or d <= b)


## True when `window` is empty (all year) or contains the day.
static func allows(window: SeasonWindow, season: Calendar.Season, day: int) -> bool:
	return window == null or window.contains(season, day)


func describe() -> String:
	return "%s to %s" % [Calendar.date_name(from_season, from_day), Calendar.date_name(to_season, to_day)]
