class_name FishingHud
extends Node2D
## The fishing HUD's drawing (architecture step A): the catch count, the fight
## meter, the last roll's odds and the catch card. A view helper: each function
## draws onto the canvas item it is given, in screen pixels, from values the
## fishing controller hands it, so the controller keeps one _draw() and the
## HUD stays on top of the line and the fish. Never instanced.

const CARD_SECONDS := 3.5
const ODDS_SECONDS := 3.0  # how long the last roll's odds stay on screen

const COL_PANEL := Color(0, 0, 0, 0.55)
const COL_TEXT := Color("f4efe0")
const COL_DIM := Color(0.96, 0.94, 0.88, 0.6)
const COL_TITLE := Color("f2c35a")
const COL_BAR_BG := Color(1, 1, 1, 0.15)
const COL_TENSION_OK := Color("8fd16a")
const COL_TENSION_HIGH := Color("f2c35a")
const COL_TENSION_DANGER := Color("e8553a")
const COL_STAMINA := Color("6ec3e0")


## Catch log, bottom right: how many landed, and how many of the species in
## `fish` when there's more than one.
static func draw_log(ci: CanvasItem, view: Vector2, caught: int, species: int, fish: Array[Fish]) -> void:
	var seen := {}
	for f in fish:
		seen[f.species.id] = true
	var of_species := seen.size()
	var font := ThemeDB.fallback_font
	var log_text := "%d caught" % caught
	if of_species > 1:
		log_text += "  %d/%d species" % [species, of_species]
	var w := font.get_string_size(log_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var log_box := Rect2(view.x - w - 10, view.y - 17, w + 6, 13)
	ci.draw_rect(log_box, COL_PANEL)
	ci.draw_string(font, log_box.position + Vector2(3, 10), log_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_TEXT)


## Tension and stamina bars, top centre, while fighting.
static func draw_fight_meter(ci: CanvasItem, view: Vector2, fight: FightModel) -> void:
	var font := ThemeDB.fallback_font
	var bar := Rect2(roundf(view.x * 0.5 - 50), 4, 100, 5)
	ci.draw_rect(bar.grow(2), COL_PANEL)
	ci.draw_rect(bar, COL_BAR_BG)
	var col := COL_TENSION_OK
	if fight.tension > 0.85:
		col = COL_TENSION_DANGER
	elif fight.tension > 0.6:
		col = COL_TENSION_HIGH
	ci.draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * clampf(fight.tension, 0, 1)), bar.size.y)), col)
	var stamina := Rect2(bar.position + Vector2(0, 7), Vector2(roundf(bar.size.x * fight.stamina), 2))
	ci.draw_rect(stamina, COL_STAMINA)
	ci.draw_string(font, bar.position + Vector2(bar.size.x + 5, 6), "tension", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_TEXT)


## The last roll's odds, top centre, so the rules are never hidden. `age` is
## seconds since the roll.
static func draw_odds(ci: CanvasItem, view: Vector2, text: String, age: float) -> void:
	if age > ODDS_SECONDS or text == "":
		return
	var font := ThemeDB.fallback_font
	var alpha := clampf((ODDS_SECONDS - age) / 0.4, 0.0, 1.0)
	var width := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x, view.x - 16)
	var lines := ceili(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x / (view.x - 16))
	var rect := Rect2(roundf((view.x - width) * 0.5) - 3, 2, width + 6, 10 * lines + 1)
	ci.draw_rect(rect, Color(COL_PANEL, COL_PANEL.a * alpha))
	ci.draw_multiline_string(font, rect.position + Vector2(3, 9), text, HORIZONTAL_ALIGNMENT_LEFT,
		width, 8, lines, Color(COL_TEXT, alpha))


## The catch card: species, size and fly, and the species' description.
## `age` is seconds since the catch.
static func draw_card(ci: CanvasItem, view: Vector2, lines: PackedStringArray, age: float) -> void:
	if age > CARD_SECONDS or lines.is_empty():
		return
	var font := ThemeDB.fallback_font
	var rect := Rect2(40, 66, view.x - 80, 52)
	var alpha := clampf((CARD_SECONDS - age) / 0.4, 0.0, 1.0)
	ci.draw_rect(rect, Color(0.08, 0.1, 0.09, 0.85 * alpha))
	ci.draw_rect(rect, Color(COL_TEXT, 0.6 * alpha), false, 1.0)
	ci.draw_string(font, rect.position + Vector2(6, 12), lines[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(COL_TITLE, alpha))
	ci.draw_string(font, rect.position + Vector2(6, 22), lines[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(COL_TEXT, alpha))
	ci.draw_multiline_string(font, rect.position + Vector2(6, 33), lines[2], HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 12, 8, 2, Color(COL_DIM, COL_DIM.a * alpha))
