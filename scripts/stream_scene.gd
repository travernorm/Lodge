extends Node2D
## The river the angler fishes. Two layouts:
## - With a `stretch` (REQ-0002, the demo): a winding river several screens
##   across, with bends, cut banks, point bars, a boulder garden, an eddy and a
##   fallen log. The camera scrolls with the angler, who walks the bank.
## - Without one: the original test screen, a fast riffle on the left feeding a
##   slow pool on the right, with a boulder at the head of the pool.
## This node builds the river field and wires the parts that show it (step
## A2): RiverView draws the ground, streaks and features, Angler walks the bank
## (drawn by AnglerView), and CameraRig follows him on a stretch. Casting and
## fishing read the river and the angler through the helpers below.
##
## The current comes from a RiverField (scripts/river/river_field.gd): the
## thalweg (deepest, fastest line), slow edges, the boulder's cushion, pocket and
## seams, and where trout would hold. The drift, the streaks and the water colour
## all read that one field.
##
## Units (REQ-0001): the river's layout and the field work in metres; this scene
## draws in pixels through WorldScale. Fishing reads river.flow_at() and
## river.is_water() in metres. flow_at() and is_water() below are screen-space
## helpers (pixels in and out) for the things still placed in pixels: the cast's
## fly position and the drifting streaks.
##
## On the test screen the angler stands on the near (bottom) bank facing across
## the water. On a stretch the angler faces the river from wherever they stand:
## facing_angle() turns casting and the rod to match.

## The demo stretch. Leave empty for the one-screen test stream.
@export var stretch: Stretch
## The ways out of this section (REQ-0014), set by the WorldRoot that made it.
## Walking into one's exit emits section_exit once.
var links: Array[SectionLink] = []
## Where the angler starts (m) when he arrives from another section; INF
## starts him at the stretch's angler_start.
var arrive_at := Vector2.INF
signal section_exit(link: SectionLink)

const VIEW := Vector2(320, 200)

# River layout, in metres. One screen is 40 m by 25 m.
const REACH_M := 40.0
const BANK_TOP_M := 7.25  # far bank
const BANK_BOTTOM_M := 18.5  # near bank: about 11 m of water
const RIFFLE_END_M := 16.25  # where the riffle drops into the pool
## Boulders: x, y = centre, z = radius, in metres.
const ROCKS_M: Array[Vector3] = [Vector3(17.75, 11.25, 0.625)]

# The same banks in screen pixels, for drawing and for code not yet in metres.
const BANK_TOP := BANK_TOP_M * WorldScale.PX_PER_M
const BANK_BOTTOM := BANK_BOTTOM_M * WorldScale.PX_PER_M

const ROD_LENGTH := 26.0

var river := _make_river()
var camera: CameraRig
## Where the angler's feet are (px). Tests set it to move him.
var angler_pos: Vector2:
	get:
		return _walker.feet
	set(value):
		_walker.feet = value

## The angler on the bank (scripts/angler.gd), and his sprite.
var _walker := Angler.new()
var _angler: AnglerView = _walker.view
## Draws the ground, water bands, streaks, boulders and logs.
var _view := RiverView.new()
## A streamed section (REQ-0014): keeps the chunks around the camera built and
## painted. Null otherwise.
var _streamer: RiverStreamer
## Whether _ready() has put the angler and the view in the tree.
var _parts_added := false
@onready var _cast: Node = get_node_or_null(^"Cast")
## Paints the water with a WaterLook when it has one (scripts/river/water_view.gd).
@onready var _water: WaterView = get_node_or_null(^"Water")
## The tall grass on the bank (REQ-0012), drawn under the angler.
@onready var _grass: GrassView = get_node_or_null(^"Grass")
## Paints a stretch's land: shoreline, cut banks and ground (REQ-0013).
@onready var _bank: BankView = get_node_or_null(^"Bank")
## Stocks each chunk of a streamed section with fish as it comes into reach.
@onready var _fishing: Node = get_node_or_null(^"Fishing")


## The angler and the river view are made with the scene but only join the
## tree in _ready(); free them too if the scene goes before that (tests).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if not _parts_added:
			_walker.free()
			_view.free()


func _enter_tree() -> void:
	# Built here, not in _ready(), because the casting and fishing nodes read
	# the river in their own _ready(), which runs before this node's.
	if not _parts_added:
		_walker.setup(river, VIEW, false, Vector2(160, BANK_BOTTOM + 16))
	if stretch == null or river.stretch == stretch:
		return
	if stretch.streamed:
		var section := SectionField.new()
		section.setup(stretch)
		river = section
	else:
		river.build_stretch(stretch)
	_walker.setup(river, world_size(), true, WorldScale.vec_to_px(stretch.angler_start if arrive_at == Vector2.INF else arrive_at))
	camera = CameraRig.new()
	camera.setup(world_size(), _walker.feet, _walker.facing)
	add_child(camera)


func _ready() -> void:
	add_to_group(&"stream")
	# Drawn bottom to top: the ground, the grass, the angler.
	add_child(_view)
	move_child(_view, 0)
	add_child(_walker)
	_parts_added = true
	if _grass != null:
		_grass.setup(river)
		move_child(_grass, 1)
	move_child(_walker, 2 if _grass != null else 1)
	if camera != null:
		camera.make_current()
		camera.reset_smoothing()
	if river is SectionField:
		_setup_streamer()
	else:
		if stretch != null and _water != null:
			_water.setup(river)
		if stretch != null and _bank != null:
			_bank.setup(river)
	_view.setup(river, stretch, VIEW, Vector2(BANK_TOP, BANK_BOTTOM),
		stretch != null and _water != null and _water.is_active(), visible_rect(),
		stretch != null and _bank != null and _bank.is_active())


func _process(delta: float) -> void:
	var walking: bool = _cast == null or _cast.allows_walking()
	_walker.step(delta, Controls.move_vector(), walking)
	if camera != null:
		camera.follow(_walker.feet, _walker.facing)
	if _grass != null:
		_grass.angler_at(_walker.feet)
	if _streamer != null:
		_streamer.update(visible_rect())
	for link in links:
		if link.exit.has_point(WorldScale.vec_to_m(_walker.feet)):
			links = []
			section_exit.emit(link)
			break
	_view.tick(delta, visible_rect())
	_walker.show_rod(rod_tip(), _cast.rod_butt() * ROD_LENGTH if _cast != null else Vector2.ZERO,
		_cast != null and _cast.shows_arm())


## A streamed section: the streamer draws the ground under everything and hands
## each chunk to the water, bank and grass views as it is ready.
func _setup_streamer() -> void:
	_streamer = RiverStreamer.new()
	add_child(_streamer)
	move_child(_streamer, 0)
	var water_on := _water != null and _water.is_active()
	var land_on := _bank != null and _bank.is_active()
	if _water != null:
		_streamer.chunk_shown.connect(func(key: Vector2i, field: RiverField, area: Rect2, painter: ChunkPainter) -> void:
			_water.add_chunk(key, field, Rect2(WorldScale.vec_to_px(area.position), WorldScale.vec_to_px(area.size)),
				painter.field_img, painter.edge_img))
		_streamer.chunk_hidden.connect(_water.drop_chunk)
	if land_on:
		_streamer.chunk_shown.connect(func(key: Vector2i, field: RiverField, area: Rect2, painter: ChunkPainter) -> void:
			_bank.add_chunk(key, field, Rect2(WorldScale.vec_to_px(area.position), WorldScale.vec_to_px(area.size)),
				painter.bank_img))
		_streamer.chunk_hidden.connect(_bank.drop_chunk)
	if _grass != null:
		_streamer.chunk_shown.connect(func(key: Vector2i, field: RiverField, area: Rect2, _p: ChunkPainter) -> void:
			_grass.add_chunk(key, field, area))
		_streamer.chunk_hidden.connect(_grass.drop_chunk)
	if _fishing != null:
		_streamer.chunk_shown.connect(func(key: Vector2i, field: RiverField, area: Rect2, _p: ChunkPainter) -> void:
			_fishing.add_chunk(key, field, area))
		_streamer.chunk_hidden.connect(_fishing.drop_chunk)
	# The camera has not moved yet: build what is around the angler.
	_streamer.setup(river as SectionField, water_on, _bank.look if land_on else null,
		Rect2(_walker.feet - VIEW, VIEW * 2.0))


## The fishing node, so a WorldRoot can carry the day into the next section.
func fishing() -> Node:
	return get_node_or_null(^"Fishing")


## The section and the chunk under the angler, for the debug overlay.
func debug_lines() -> PackedStringArray:
	if stretch == null:
		return PackedStringArray()
	var line := "section  %s" % stretch.display_name
	if river is SectionField:
		line += "  chunk %s" % (river as SectionField).key_of(WorldScale.vec_to_m(_walker.feet))
	return PackedStringArray([line])


## Current velocity (px/s) at a point on screen (px).
## Pixel helper over river.flow_at() (metres), for screen-space callers.
func flow_at(p: Vector2) -> Vector2:
	return WorldScale.vec_to_px(river.flow_at(WorldScale.vec_to_m(p)))


## Pixel helper over river.is_water() (metres), for screen-space callers.
func is_water(p: Vector2) -> bool:
	return river.is_water(WorldScale.vec_to_m(p))


## Size of the world in pixels: the stretch, or one screen.
func world_size() -> Vector2:
	return WorldScale.vec_to_px(stretch.size_m) if stretch != null else VIEW


## Top-left of what's on screen, in world pixels. HUD drawing offsets by this
## so it stays put while the camera scrolls.
func screen_origin() -> Vector2:
	return camera.screen_origin(VIEW) if camera != null else Vector2.ZERO


## The part of the world on screen (px).
func visible_rect() -> Rect2:
	return Rect2(screen_origin(), VIEW)


## Which way the angler faces, as an angle from straight up the screen. 0 on
## the test screen. Casting aims, rod poses and practice targets turn by this.
func facing_angle() -> float:
	return _walker.facing_angle()


## Whether a fly (px) is still in play: on the test screen, until it drifts off
## the right edge; on a stretch, until it leaves the world.
func in_play(p: Vector2) -> bool:
	if stretch == null:
		return p.x <= VIEW.x - 4.0
	return Rect2(Vector2(4, 4), world_size() - Vector2(8, 8)).has_point(p)


## Where a hooked fish (px) can be: kept in the water. `prev` is where it was.
func keep_in_water(p: Vector2, prev: Vector2) -> Vector2:
	if stretch == null:
		return Vector2(clampf(p.x, 4.0, VIEW.x - 4.0), clampf(p.y, BANK_TOP + 3.0, BANK_BOTTOM - 3.0))
	return p if is_water(p) else prev


## Where the deepest, fastest line runs (m): it drifts from the far side of the
## riffle toward the near bank through the pool.
func thalweg_y(x: float) -> float:
	return lerpf(11.75, 13.25, smoothstep(7.5, 30.0, x))


## How deep the thalweg is (1 = deepest) at x (m): a shallow riffle dropping into
## the pool, which shallows again into a tail-out at the right edge.
func thalweg_depth(x: float) -> float:
	return lerpf(0.35, 1.0, smoothstep(RIFFLE_END_M - 3.75, RIFFLE_END_M + 5.0, x)) \
		- 0.2 * smoothstep(33.75, 41.25, x)


func _make_river() -> RiverField:
	var r := RiverField.new()
	r.build(BANK_TOP_M, BANK_BOTTOM_M, REACH_M, thalweg_y, thalweg_depth, ROCKS_M)
	return r


func rod_tip() -> Vector2:
	return hand_position() + _rod_direction() * ROD_LENGTH


func hand_position() -> Vector2:
	return _walker.hand_position()


## The casting controller poses the rod during a cast; otherwise the right stick
## aims the tip.
func _rod_direction() -> Vector2:
	if _cast != null:
		var pose: Vector2 = _cast.rod_pose()
		if pose != Vector2.ZERO:
			return pose
	var stick := Controls.rod_vector()
	if stick.length() > 0.25:
		return stick.normalized()
	return Vector2(0.45, -1.0).normalized().rotated(facing_angle())
