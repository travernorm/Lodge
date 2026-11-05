class_name SectionField
extends RiverField
## A long section of river (REQ-0014) held as chunks about one screen across,
## each a RiverField built from the section's one RiverChannel, so the water
## matches at every seam. It answers the same questions as a RiverField
## (is_water, flow_at, depth_at, lies ...) by asking the chunk under the point,
## so casting, the drift and the fish don't know the river is chunked.
##
## The stream scene asks for the chunks around the camera with want() and
## calls step() while its frame budget lasts; each step builds a row of the
## nearest chunk waiting (the web build has one thread) and returns the chunk
## when it finishes, for the scene to draw. drop_outside() forgets far chunks. A question about a chunk
## not built yet builds it at once, so a test or a far cast still gets the
## right water, only with a pause. Metres.

## A chunk's own area (m): one screen.
const CHUNK := Vector2(40, 25)
## Extra water (m) each chunk builds past its edges, so the seams, lies,
## sampling and the water view's foam lines (3 m) near an edge see the same
## neighbours as a whole build.
const MARGIN := 3.0
## No chunk.
const NONE := Vector2i(-1, -1)

## Finished chunks, by key: Vector2i -> RiverField.
var _chunks := {}
## Chunks being built: Vector2i -> RiverFieldBuilder; and their fields.
var _jobs := {}
var _job_fields := {}
## Keys waiting to start, nearest first.
var _queue: Array[Vector2i] = []


func setup(p_stretch: Stretch) -> void:
	stretch = p_stretch
	channel = RiverChannel.new(stretch)
	left = 0.0
	top = 0.0
	width = stretch.size_m.x
	bottom = stretch.size_m.y
	features = stretch.features
	centre = channel.points
	centre_dir = channel.tang
	thalweg = PackedVector2Array()
	for tp in channel.thalweg():
		if bounds().has_point(tp):
			thalweg.append(tp)


# --- Chunks -------------------------------------------------------------------

## The key of the chunk holding p (m), clamped to the section.
func key_of(p: Vector2) -> Vector2i:
	var last := key_count() - Vector2i.ONE
	return Vector2i(clampi(floori(p.x / CHUNK.x), 0, last.x), clampi(floori(p.y / CHUNK.y), 0, last.y))


## How many chunks across and down.
func key_count() -> Vector2i:
	return Vector2i(maxi(ceili(width / CHUNK.x), 1), maxi(ceili(bottom / CHUNK.y), 1))


## A chunk's own area (m), without its margin.
func chunk_rect(key: Vector2i) -> Rect2:
	return Rect2(Vector2(key) * CHUNK, CHUNK).intersection(bounds())


## The chunk under p (m), built now if it isn't yet.
func chunk_at(p: Vector2) -> RiverField:
	return chunk(key_of(p))


func chunk(key: Vector2i) -> RiverField:
	if _chunks.has(key):
		return _chunks[key]
	if not _jobs.has(key):
		_start(key)
	(_jobs[key] as RiverFieldBuilder).run()
	_finish(key)
	return _chunks[key]


func is_built(key: Vector2i) -> bool:
	return _chunks.has(key)


## The finished chunks' keys.
func built_keys() -> Array:
	return _chunks.keys()


## Queues every chunk touching `area` (m) that isn't built or building, the
## ones nearest the area's centre first.
func want(area: Rect2) -> void:
	var a := key_of(area.position)
	var b := key_of(area.end)
	var mid := area.get_center()
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var key := Vector2i(x, y)
			if not _chunks.has(key) and not _jobs.has(key) and not _queue.has(key):
				_queue.append(key)
	_queue.sort_custom(func(k1: Vector2i, k2: Vector2i) -> bool:
		return chunk_rect(k1).get_center().distance_squared_to(mid) < chunk_rect(k2).get_center().distance_squared_to(mid))


## Does `units` pieces of work (a row of cells each, about a millisecond) on
## the nearest chunk waiting. Returns the key it finished, or (-1, -1).
func step(units := 1) -> Vector2i:
	if _jobs.is_empty():
		if _queue.is_empty():
			return NONE
		_start(_queue.pop_front())
	var key: Vector2i = _jobs.keys()[0]
	if (_jobs[key] as RiverFieldBuilder).step(units):
		_finish(key)
		return key
	return NONE


## True while chunks are queued or building.
func busy() -> bool:
	return not _jobs.is_empty() or not _queue.is_empty()


## Forgets chunks (and queued ones) that don't touch `keep` (m). Returns the
## keys dropped, for the scene to free their views.
func drop_outside(keep: Rect2) -> Array[Vector2i]:
	var gone: Array[Vector2i] = []
	for key: Vector2i in _chunks.keys():
		if not chunk_rect(key).intersects(keep):
			_chunks.erase(key)
			gone.append(key)
	_queue = _queue.filter(func(k: Vector2i) -> bool: return chunk_rect(k).intersects(keep))
	return gone


func _start(key: Vector2i) -> void:
	_queue.erase(key)
	var area := chunk_rect(key).grow(MARGIN).intersection(bounds())
	var f := RiverField.new()
	_job_fields[key] = f
	_jobs[key] = f.start_chunk(stretch, channel, area)


func _finish(key: Vector2i) -> void:
	_chunks[key] = _job_fields[key]
	_jobs.erase(key)
	_job_fields.erase(key)


# --- The same questions as a RiverField, asked of the chunk under p ----------

func is_water(p: Vector2) -> bool:
	return bounds().has_point(p) and chunk_at(p).is_water(p)


func flow_frame(p: Vector2) -> Array:
	return chunk_at(p).flow_frame(p)


func flow_at(p: Vector2) -> Vector2:
	return chunk_at(p).flow_at(p) if bounds().has_point(p) else Vector2.ZERO


func depth_at(p: Vector2) -> float:
	return chunk_at(p).depth_at(p) if bounds().has_point(p) else 0.0


func seam_at(p: Vector2) -> float:
	return chunk_at(p).seam_at(p) if bounds().has_point(p) else 0.0


func lie_at(p: Vector2) -> float:
	return chunk_at(p).lie_at(p) if bounds().has_point(p) else 0.0


## The best lie among the built chunks, optionally only inside `area`.
func best_lie(area := Rect2()) -> Vector3:
	var best := Vector3(0, 0, -1.0)
	for key: Vector2i in _chunks.keys():
		var own := chunk_rect(key)
		var clip := own.intersection(area) if area.has_area() else own
		if not clip.has_area():
			continue
		var b: Vector3 = _chunks[key].best_lie(clip)
		if b.z > best.z:
			best = b
	return best


## A lie inside `area`, from the chunks it touches (built now if need be), with
## better lies more likely, as RiverField.pick_lie().
func pick_lie(area: Rect2, rng: RandomNumberGenerator, min_score := 0.4,
		avoid := PackedVector2Array(), gap := 0.0) -> Vector2:
	var cells: Array[Vector2] = []
	var weights := PackedFloat32Array()
	var total := 0.0
	var a := key_of(area.position)
	var b := key_of(area.end)
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var key := Vector2i(x, y)
			var clip := chunk_rect(key).intersection(area)
			if clip.has_area():
				total += chunk(key).lie_cells(clip, min_score, avoid, gap, cells, weights)
	return RiverField.pick_weighted(cells, weights, total, rng)
