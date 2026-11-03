extends Node2D
## Everything after the fly lands: the drift and mending, fish rising, the hook
## set, the fight, the fly box and the catch log. Sits beside the Cast node
## under the stream scene.
##
## Right stick, once the fly is on the water:
##   loop it (half a circle)  mend: flip the line's belly back upstream
##   flick it up             set the hook when a fish takes
##   push and hold           rod pressure while fighting a fish
##
## Shortcuts: X / Square (M on keyboard) mends, the same as a stick loop.
## Each mend feeds out line, as much as the belly had bowed.
## A / Cross / Space sets the hook too, and holding it while fighting is full
## pressure straight up.
##
## Bites follow the Drift past rules (DriftPastRules). The odds for each roll
## show at the top of the screen.

enum Phase { NONE, DRIFT, FIGHT, REEL }

## The fly box. Y (F on keyboard) cycles through it while the line is reeled in.
## The first is tied on at the start.
@export var flies: Array[FlyPattern] = [
	preload("res://data/flies/parachute_adams.tres"),
	preload("res://data/flies/elk_hair_caddis.tres"),
	preload("res://data/flies/royal_wulff.tres"),
]
## One fish is stocked for each entry. Starts with one trout in the pool; more
## species are waiting in data/fish/.
@export var stocking: Array[FishSpecies] = [
	preload("res://data/fish/redband.tres"),
]

## The bite rules: each trout rolls as the fly drifts past it.
@export var take_rules: DriftPastRules = preload("res://data/take_rules/drift_past.tres")

const CARD_SECONDS := 3.5
const ODDS_SECONDS := 3.0  # how long the last roll's odds stay on screen
const SET_ANIM_TIME := 0.3  # rod snaps up and back, then settles
const REEL_DELAY := 0.15  # pause after a missed set before the line comes in
const REEL_SPEED := 18.75  # m/s the fly comes back on a reel-in
const REEL_DONE := 0.375  # m from the rod tip where the reel-in finishes
const RING_SECONDS := 0.9

const COL_LINE := Color("d8cfa6")
const COL_LINE_TIGHT := Color("f2a65a")
const COL_LINE_DANGER := Color("e8553a")
const COL_FISH_SHADOW := Color(0.05, 0.12, 0.14, 0.55)
const COL_WAKE := Color(1, 1, 1, 0.6)
const COL_RING := Color(1, 1, 1, 0.85)
const COL_PANEL := Color(0, 0, 0, 0.55)
const COL_TEXT := Color("f4efe0")
const COL_DIM := Color(0.96, 0.94, 0.88, 0.6)
const COL_BAR_BG := Color(1, 1, 1, 0.15)
const COL_TENSION_OK := Color("8fd16a")
const COL_TENSION_HIGH := Color("f2c35a")
const COL_TENSION_DANGER := Color("e8553a")
const COL_STAMINA := Color("6ec3e0")

var phase := Phase.NONE
## Off in casting practice: landings don't start a drift and fish don't bite.
var enabled := true
var drift := DriftModel.new()
var fight: FightModel
## The drift, the fish and the fight work in metres (REQ-0001). The cast and
## the stream scene still place things in screen pixels, so this converts at
## those edges and when drawing.
var fish: Array[Fish] = []
var hooked: Fish
var fly_index := 0
## Every fish landed this session: {species, length_in, fly}.
var catches: Array[Dictionary] = []

var _gestures := StickGestures.new()
var _rng := RandomNumberGenerator.new()
var _stream: Node2D
var _river: RiverField
var _cast: Node
var _time := 0.0
var _fly_taken := false
var _rings: Array[Vector3] = []
var _card_lines := PackedStringArray()
var _card_at := -100.0
var _set_at := -100.0
## Where the fly landed (m) and how, for the bite rules.
var _landed_at := Vector2.INF
var _landed_presentation := ""
## The last roll's odds, spelled out, and when it was rolled.
var _odds_text := ""
var _odds_at := -100.0


func _ready() -> void:
	add_to_group(&"fishing")
	_rng.randomize()
	_stream = get_parent() as Node2D
	_cast = _stream.get_node(^"Cast")
	_cast.model.landed.connect(_on_landed)
	_river = _stream.get(&"river")
	# A stretch brings its own trout, spread over the whole river.
	var stretch: Stretch = _stream.get(&"stretch")
	var area := Rect2()
	if stretch != null and not stretch.trout.is_empty():
		stocking = stretch.trout
		area = Rect2(Vector2.ZERO, stretch.size_m)
	for species in stocking:
		fish.append(Fish.new(species, _rng, _river, area, _lies_except))


## The lies (m) of every trout but `me`, so trout spread out over the water.
func _lies_except(me: Fish) -> PackedVector2Array:
	var out := PackedVector2Array()
	for f in fish:
		if f != me:
			out.append(f.lie)
	return out


func current_fly() -> FlyPattern:
	return flies[fly_index]


func can_pick_up() -> bool:
	return phase != Phase.FIGHT


## Where the line ends, in screen pixels: the fish while fighting, otherwise the fly.
func line_target() -> Vector2:
	if phase == Phase.FIGHT and hooked != null:
		return WorldScale.vec_to_px(hooked.pos)
	return WorldScale.vec_to_px(drift.fly) if phase == Phase.DRIFT else _cast.fly_pos


func species_caught() -> int:
	var seen := {}
	for c in catches:
		seen[c.species.id] = true
	return seen.size()


func debug_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	match phase:
		Phase.DRIFT:
			lines.append("drift  drag %.2f  slip %.1f m/s  bow %.1f m" % [drift.drag, drift.slip, drift.bow()])
		Phase.FIGHT:
			lines.append("fight  tension %.2f  stamina %.2f  %s" % [fight.tension, fight.stamina, "RUN" if fight.running else "rest"])
	var states := PackedStringArray()
	for f in fish:
		states.append("%s:%s" % [String(f.species.id).left(3), Fish.State.keys()[f.state].left(4).to_lower()])
	lines.append(" ".join(states))
	lines.append("bites  %s" % take_rules.display_name)
	lines.append("line out  %.1f m" % drift.line_length)
	return lines


func _process(delta: float) -> void:
	_time += delta
	var stick := Controls.rod_vector()
	_gestures.update(_time, stick)

	if Input.is_action_just_pressed(Controls.CHANGE_FLY):
		_change_fly()

	match phase:
		Phase.DRIFT:
			_update_drift(delta)
		Phase.REEL:
			_update_reel(delta)
		Phase.FIGHT:
			if Input.is_action_pressed(Controls.INTERACT) and stick.length() < 0.5:
				stick = Vector2(0, -1)
			_update_fight(delta, stick)

	var on_water := phase == Phase.DRIFT and not _fly_taken
	for f in fish:
		if f == hooked:
			continue
		_on_fish_event(f, f.update(delta, drift.fly, on_water))
	queue_redraw()


func _change_fly() -> void:
	if flies.size() < 2:
		_cast.show_message("Just the one fly in Dad's box for now.", 0.5)
		return
	if _cast.model.state != CastModel.State.IDLE:
		_cast.show_message("Reel in first (B) to change flies.", 0.5)
		return
	fly_index = (fly_index + 1) % flies.size()
	var fly := current_fly()
	var kinds := fly.kinds_text()
	_cast.show_message("Tied on a %s%s." % [fly.display_name, " (%s)" % kinds if kinds != "" else ""], 1.0)


# --- Drift -----------------------------------------------------------------

func _on_landed(_presentation: String, _quality: float) -> void:
	var at := WorldScale.vec_to_m(_cast.fly_pos)
	if not enabled or not _river.is_water(at):
		return
	phase = Phase.DRIFT
	_fly_taken = false
	drift.start(_tip_m(), at)
	drift.downstream = _downstream_at(at)
	var presentation: String = _cast.model.presentation
	_landed_at = at
	_landed_presentation = presentation
	for f in fish:
		f.reset_pass()
	_cast.show_message("%s landing." % presentation, _cast.model.last_cast_quality)


## Each fish the fly drifts past rolls once per pass.
func _watch_passes(delta: float) -> void:
	if _fly_taken:
		return
	for f in fish:
		if f == hooked or not f.watch_pass(drift.fly, drift.slip, take_rules.window(), delta):
			continue
		var odds := take_rules.pass_odds(f, _landed_at, _landed_presentation, f.pass_worst_slip, current_fly())
		f.roll(odds.chance, take_rules.rise_delay())
		_show_odds(odds.text)


func _show_odds(text: String) -> void:
	_odds_text = text
	_odds_at = _time


func _update_drift(delta: float) -> void:
	if _cast.model.state != CastModel.State.LANDED:
		_end_drift()  # picked up for another cast, or reeled in
		return
	drift.tip = _tip_m()
	if (_gestures.looped or Input.is_action_just_pressed(Controls.MEND)) and not _fly_taken:
		drift.mend()
		if drift.over_mended:
			_cast.show_message("Mended too soon. The fly skated.", 0.3)
		elif drift.fed > 0.0:
			_cast.show_message("Mend +%.1f m (%.1f m out)" % [drift.fed, drift.line_length], 1.0)
		else:
			_cast.show_message("Mend. No more line to feed.", 1.0)
	drift.update(delta, _river.flow_at)
	_cast.fly_pos = WorldScale.vec_to_px(drift.fly)
	_cast.model.line_out = clampf(drift.tip.distance_to(drift.fly), _cast.tuning.line_start, _cast.tuning.line_max)
	_watch_passes(delta)

	if _gestures.flicked or Input.is_action_just_pressed(Controls.INTERACT):
		_try_set()
		if phase != Phase.DRIFT:
			return
	if not _stream.in_play(WorldScale.vec_to_px(drift.fly)):
		_cast.reel_in_line("Drift's done. Reeled in.")
		_end_drift()


func _end_drift() -> void:
	phase = Phase.NONE
	_fly_taken = false
	drift.drag = 0.0


## The rod snaps up whatever happens. Hook a fish and the fight starts;
## otherwise the fly rips off the water and the line reels in.
func _try_set() -> void:
	_set_at = _time
	Controls.rumble(0.15, 0.0, 0.06)
	_burst(WorldScale.vec_to_px(drift.fly), 6.0)
	for f in fish:
		if f.state != Fish.State.RISING and f.state != Fish.State.TAKEN:
			continue
		match f.try_set():
			Fish.SetResult.HOOKED:
				_start_fight(f)
				return
			Fish.SetResult.TOO_EARLY:
				_cast.show_message("Too soon! You pulled it away from the fish.", 0.2)
			Fish.SetResult.TOO_LATE:
				_cast.show_message("Too late. It spat the fly.", 0.3)
		_start_reel()
		return
	_cast.show_message("Nothing there. Reeling in.", 0.6)
	_start_reel()


func _start_reel() -> void:
	phase = Phase.REEL
	_fly_taken = false
	drift.drag = 0.0


func _update_reel(delta: float) -> void:
	if _cast.model.state != CastModel.State.LANDED:
		phase = Phase.NONE  # picked straight up into another cast
		return
	if _time - _set_at < REEL_DELAY:
		return
	var tip := _tip_m()
	drift.fly = drift.fly.move_toward(tip, REEL_SPEED * delta)
	_cast.fly_pos = WorldScale.vec_to_px(drift.fly)
	if drift.fly.distance_to(tip) < REEL_DONE:
		_cast.reel_in_line("")
		phase = Phase.NONE


## While the hook-set animation plays: the rod's direction (it snaps sideways and
## downstream in a sweep set, then settles part way). ZERO when it isn't playing.
func hook_set_pose() -> Vector2:
	var t := (_time - _set_at) / SET_ANIM_TIME
	if t < 0.0 or t > 1.0:
		return Vector2.ZERO
	var k := t / 0.3 if t < 0.3 else lerpf(1.0, 0.45, (t - 0.3) / 0.7)
	var turn: float = _cast.model.facing_angle
	return Vector2(0.0, -1.0).slerp(Vector2(0.95, -0.3).normalized(), clampf(k, 0.0, 1.0)).rotated(turn)


func _on_fish_event(f: Fish, event: StringName) -> void:
	match event:
		&"take":
			_fly_taken = true
			_ring_at(f.pos, _time)
			Controls.rumble(0.25, 0.0, 0.08)
		&"spat":
			_fly_taken = false
			_cast.show_message("Too late. It spat the fly.", 0.3)
		&"dimple":
			_ring_at(f.lie, _time - 0.3)
		&"rising":
			_cast.show_message("Here it comes...", 1.0)


# --- Fight -----------------------------------------------------------------

func _start_fight(f: Fish) -> void:
	phase = Phase.FIGHT
	hooked = f
	var tip := _tip_m()
	fight = FightModel.new(f.species, tip.distance_to(drift.fly), (drift.fly - tip).angle(), _rng)
	_cast.show_message("Fish on! Hold Space or push the stick to pull.", 1.0)
	Controls.rumble(0.3, 0.8, 0.25)


func _update_fight(delta: float, stick: Vector2) -> void:
	var was_running := fight.running
	var result := fight.update(delta, stick)
	hooked.pos = _fish_position()
	_cast.fly_pos = WorldScale.vec_to_px(hooked.pos)
	if fight.running and not was_running:
		_cast.show_message("It's running! Ease off.", 0.5)
		Controls.rumble(0.2, 0.6, 0.3)
	elif fight.tension > 0.8:
		Controls.rumble(0.0, 0.3 * fight.tension, 0.05)
	if fight.running and _rng.randf() < delta * 6.0:
		_burst(WorldScale.vec_to_px(hooked.pos), 4.0)

	match result:
		FightModel.Result.LANDED:
			_land_fish()
		FightModel.Result.SNAPPED:
			_end_fight("Snap! Too much pressure broke the tippet.", 0.0)
			Controls.rumble(0.8, 0.0, 0.15)
		FightModel.Result.THREW_HOOK:
			_end_fight("Slack line. It threw the hook.", 0.2)


## Where the hooked fish is (m), kept on screen and in the water.
func _fish_position() -> Vector2:
	var p: Vector2 = _stream.rod_tip() + Vector2.from_angle(fight.angle) * WorldScale.to_px(fight.distance)
	return WorldScale.vec_to_m(_stream.keep_in_water(p, WorldScale.vec_to_px(hooked.pos)))


## Which way the water runs at `at` (m), for the drift's bow and mends. The
## test screen's river runs +x; on a stretch it's the local current, so a fly
## in an eddy mends against the eddy's reversed current.
func _downstream_at(at: Vector2) -> Vector2:
	if _river == null or _river.stretch == null:
		return Vector2.RIGHT
	var v := _river.flow_at(at)
	if v.length() > 0.05:
		return v.normalized()
	var k := _river.nearest_centre(at)
	return _river.centre_dir[k] if k >= 0 else Vector2.RIGHT


## The rod tip in metres.
func _tip_m() -> Vector2:
	return WorldScale.vec_to_m(_stream.rod_tip())


## A rise ring at a world position (m).
func _ring_at(at: Vector2, start: float) -> void:
	var p := WorldScale.vec_to_px(at)
	_rings.append(Vector3(p.x, p.y, start))


func _land_fish() -> void:
	var record := {"species": hooked.species, "length_in": hooked.length_in, "fly": current_fly()}
	catches.append(record)
	_card_lines = PackedStringArray([
		hooked.species.display_name,
		"%.1f in  on a %s" % [hooked.length_in, current_fly().display_name],
		hooked.species.description,
	])
	_card_at = _time
	Controls.rumble(0.4, 0.4, 0.12)
	_end_fight("Landed it! Released to fight another day.", 1.0)


func _end_fight(message: String, quality: float) -> void:
	hooked.leave()
	hooked = null
	fight = null
	phase = Phase.NONE
	_cast.reel_in_line("")
	_cast.show_message(message, quality)


# --- Drawing ---------------------------------------------------------------

func _burst(at: Vector2, size: float) -> void:
	_rings.append(Vector3(at.x, at.y, _time - (1.0 - size / 14.0) * RING_SECONDS * 0.5))


func _draw() -> void:
	for f in fish:
		if f != hooked:
			_draw_fish(f)
	var tip: Vector2 = _stream.rod_tip()
	match phase:
		Phase.DRIFT:
			_draw_drift(tip)
		Phase.FIGHT:
			_draw_fight(tip)
		Phase.REEL:
			var fly_px := WorldScale.vec_to_px(drift.fly)
			draw_line(tip.floor() + Vector2(0.5, 0.5), fly_px.floor() + Vector2(0.5, 0.5), COL_LINE, 1.0)
			current_fly().draw_at(self, fly_px)
		Phase.NONE:
			if _cast.model.state == CastModel.State.LANDED:
				_draw_line(tip, (tip + _cast.fly_pos) * 0.5, _cast.fly_pos, COL_LINE)
				current_fly().draw_at(self, _cast.fly_pos)
	_draw_rings()
	draw_set_transform(_stream.screen_origin())  # HUD: fixed on screen
	_draw_hud()
	if phase == Phase.FIGHT:
		_draw_fight_meter()
	else:
		_draw_odds()
	_draw_card()
	draw_set_transform(Vector2.ZERO)


func _draw_fish(f: Fish) -> void:
	if not f.is_present():
		return
	var p := WorldScale.vec_to_px(f.pos).floor()
	var col := COL_FISH_SHADOW
	if f.state == Fish.State.RISING or f.state == Fish.State.TAKEN:
		col = f.species.color
	# Trout hold facing into the current, so the tail trails downstream. In an
	# eddy the current runs back upstream, so they face downstream there.
	draw_set_transform(p, _facing_into_current(f.lie))
	draw_rect(Rect2(Vector2(-3, 0), Vector2(6, 2)), col)
	draw_rect(Rect2(Vector2(3, 0), Vector2(2, 1)), col)
	draw_rect(Rect2(Vector2(4, 1), Vector2(1, 1)), col)
	draw_set_transform(Vector2.ZERO)


## Rotation for a trout drawn head-left so it faces into the current at `at` (m),
## in 45-degree steps to keep the pixels crisp.
func _facing_into_current(at: Vector2) -> float:
	var v := _river.flow_at(at) if _river != null else Vector2.ZERO
	if v.length() < 0.01:
		return 0.0
	return snappedf(wrapf(v.angle(), -PI, PI), PI / 4.0)


func _draw_drift(tip: Vector2) -> void:
	var fly_px := WorldScale.vec_to_px(drift.fly)
	_draw_line(tip, WorldScale.vec_to_px(drift.belly), fly_px, COL_LINE)
	if _fly_taken:
		return
	if drift.drag > 0.3:
		var back := fly_px.floor()
		var a := minf(1.0, drift.drag) * COL_WAKE.a
		var col := Color(COL_WAKE, a)
		draw_line(back + Vector2(-1, -1), back + Vector2(-4, -3), col, 1.0)
		draw_line(back + Vector2(-1, 2), back + Vector2(-4, 4), col, 1.0)
	current_fly().draw_at(self, fly_px)


func _draw_fight(tip: Vector2) -> void:
	var col := COL_LINE
	if fight.tension > 0.85:
		col = COL_LINE_DANGER
	elif fight.tension > 0.6:
		col = COL_LINE_TIGHT
	var fish_px := WorldScale.vec_to_px(hooked.pos)
	var mid := (tip + fish_px) * 0.5
	var sag := (1.0 - fight.tension) * 10.0
	_draw_line(tip, mid + Vector2(0, sag), fish_px, col)
	var p := fish_px.floor()
	draw_rect(Rect2(p + Vector2(-3, -1), Vector2(6, 3)), hooked.species.color)
	draw_rect(Rect2(p + Vector2(-5 if fight.run_dir > 0 else 3, -1), Vector2(2, 3)), hooked.species.color)


## A line from a through b to c (b is where the curve bends, not a control point).
func _draw_line(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	var control := 2.0 * b - (a + c) * 0.5
	var points := PackedVector2Array()
	for i in 15:
		var t := float(i) / 14.0
		var p := a.lerp(control, t).lerp(control.lerp(c, t), t)
		points.append(p.floor() + Vector2(0.5, 0.5))
	draw_polyline(points, color, 1.0)


func _draw_rings() -> void:
	var alive: Array[Vector3] = []
	for r in _rings:
		var age := _time - r.z
		if age > RING_SECONDS:
			continue
		alive.append(r)
		var t := clampf(age / RING_SECONDS, 0.0, 1.0)
		draw_arc(Vector2(r.x, r.y), 1.0 + 9.0 * t, 0.0, TAU, 16, Color(COL_RING, COL_RING.a * (1.0 - t)), 1.0)
	_rings = alive


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var view: Vector2 = _stream.VIEW
	# Fly box, bottom left.
	var fly := current_fly()
	var box := Rect2(4, view.y - 17, font.get_string_size(fly.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 20, 13)
	draw_rect(box, COL_PANEL)
	fly.draw_at(self, box.position + Vector2(5, 5), 2.0)
	draw_string(font, box.position + Vector2(14, 10), fly.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_TEXT)
	if flies.size() > 1:
		draw_string(font, box.position + Vector2(0, -3), "Y: fly box", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_DIM)
	# Catch log, bottom right.
	var log_text := "%d caught" % catches.size()
	if _unique_species() > 1:
		log_text += "  %d/%d species" % [species_caught(), _unique_species()]
	var w := font.get_string_size(log_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var log_box := Rect2(view.x - w - 10, view.y - 17, w + 6, 13)
	draw_rect(log_box, COL_PANEL)
	draw_string(font, log_box.position + Vector2(3, 10), log_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_TEXT)


func _unique_species() -> int:
	var seen := {}
	for s in stocking:
		seen[s.id] = true
	return seen.size()


func _draw_fight_meter() -> void:
	var font := ThemeDB.fallback_font
	var view: Vector2 = _stream.VIEW
	var bar := Rect2(roundf(view.x * 0.5 - 50), 4, 100, 5)
	draw_rect(bar.grow(2), COL_PANEL)
	draw_rect(bar, COL_BAR_BG)
	var col := COL_TENSION_OK
	if fight.tension > 0.85:
		col = COL_TENSION_DANGER
	elif fight.tension > 0.6:
		col = COL_TENSION_HIGH
	draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * clampf(fight.tension, 0, 1)), bar.size.y)), col)
	var stamina := Rect2(bar.position + Vector2(0, 7), Vector2(roundf(bar.size.x * fight.stamina), 2))
	draw_rect(stamina, COL_STAMINA)
	draw_string(font, bar.position + Vector2(bar.size.x + 5, 6), "tension", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_TEXT)


## The last roll's odds, top centre, so the rules are never hidden.
func _draw_odds() -> void:
	var age := _time - _odds_at
	if age > ODDS_SECONDS or _odds_text == "":
		return
	var font := ThemeDB.fallback_font
	var view: Vector2 = _stream.VIEW
	var alpha := clampf((ODDS_SECONDS - age) / 0.4, 0.0, 1.0)
	var width := minf(font.get_string_size(_odds_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x, view.x - 16)
	var lines := ceili(font.get_string_size(_odds_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x / (view.x - 16))
	var rect := Rect2(roundf((view.x - width) * 0.5) - 3, 2, width + 6, 10 * lines + 1)
	draw_rect(rect, Color(COL_PANEL, COL_PANEL.a * alpha))
	draw_multiline_string(font, rect.position + Vector2(3, 9), _odds_text, HORIZONTAL_ALIGNMENT_LEFT,
		width, 8, lines, Color(COL_TEXT, alpha))


func _draw_card() -> void:
	var age := _time - _card_at
	if age > CARD_SECONDS or _card_lines.is_empty():
		return
	var font := ThemeDB.fallback_font
	var view: Vector2 = _stream.VIEW
	var rect := Rect2(40, 66, view.x - 80, 52)
	var alpha := clampf((CARD_SECONDS - age) / 0.4, 0.0, 1.0)
	draw_rect(rect, Color(0.08, 0.1, 0.09, 0.85 * alpha))
	draw_rect(rect, Color(COL_TEXT, 0.6 * alpha), false, 1.0)
	draw_string(font, rect.position + Vector2(6, 12), _card_lines[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("f2c35a", alpha))
	draw_string(font, rect.position + Vector2(6, 22), _card_lines[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(COL_TEXT, alpha))
	draw_multiline_string(font, rect.position + Vector2(6, 33), _card_lines[2], HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 12, 8, 2, Color(COL_DIM, COL_DIM.a * alpha))
