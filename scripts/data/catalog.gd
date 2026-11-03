class_name Catalog
extends Resource
## Every piece of content in the game, by kind: the one place code looks up
## "all flies" or "the fish with id X" (REQ-0004 C1, ARCHITECTURE.md 2).
##
## It lives in data/catalog.tres and is written by tools/build_catalog.gd from
## the data/<kind>/ folders, so a new .tres there joins the game without a code
## change. It's a list rather than a folder scan because exported builds rename
## data files to .remap. tests/data_test.gd fails if it and the folders
## disagree. The order is kept between rebuilds (new files go at the end), and
## the fly box shows flies in this order, so the first fly is tied on first.

const PATH := "res://data/catalog.tres"

@export var flies: Array[FlyPattern] = []
@export var fish: Array[FishSpecies] = []
@export var insects: Array[Insect] = []
@export var stretches: Array[Stretch] = []

static var _shared: Catalog
var _index := {}


## The game's catalog, loaded once.
static func shared() -> Catalog:
	if _shared == null:
		_shared = load(PATH) as Catalog
	return _shared


func fly(p_id: StringName) -> FlyPattern:
	return _find(&"fly", p_id) as FlyPattern


func species(p_id: StringName) -> FishSpecies:
	return _find(&"fish", p_id) as FishSpecies


func insect(p_id: StringName) -> Insect:
	return _find(&"insect", p_id) as Insect


## Every entry of one kind, in catalog order.
func of_kind(kind: StringName) -> Array:
	match kind:
		&"fly": return flies
		&"fish": return fish
		&"insect": return insects
		&"stretch": return stretches
	return []


func _find(kind: StringName, p_id: StringName) -> Resource:
	if _index.is_empty():
		for k in [&"fly", &"fish", &"insect"]:
			var by_id := {}
			for res in of_kind(k):
				if res != null:
					by_id[res.id] = res
			_index[k] = by_id
	return _index.get(kind, {}).get(p_id)
