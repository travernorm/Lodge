extends SceneTree
## The catalog (REQ-0004 C1): lookups by id, the order tools/build_catalog.gd
## keeps between rebuilds, and that a new fly file reaches the fly box with no
## code change.
##   godot --headless --path . --script res://tests/catalog_test.gd

const BUILD := preload("res://tools/build_catalog.gd")

var _failures := 0


func _initialize() -> void:
	_test_lookups()
	_test_merge_order()
	_test_new_fly_reaches_fly_box()
	if _failures == 0:
		print("Catalog tests passed.")
		quit(0)
	else:
		printerr("%d catalog test(s) failed." % _failures)
		quit(1)


func _test_lookups() -> void:
	var cat := Catalog.shared()
	_check(cat != null and cat == Catalog.shared(), "shared() loads data/catalog.tres once")
	var adams := cat.fly(&"parachute_adams")
	_check(adams != null and adams.display_name != "", "fly(id) finds the Parachute Adams")
	_check(cat.species(&"redband") != null, "species(id) finds the redband")
	_check(cat.insect(&"caddis") != null, "insect(id) finds the caddis")
	_check(cat.fly(&"no_such_fly") == null, "an unknown id gives null")
	_check(cat.flies.size() > 0 and cat.flies[0] == adams, "the Parachute Adams is first, so it's tied on at the start")
	for kind in [&"fly", &"fish", &"insect", &"stretch"]:
		_check(cat.of_kind(kind).size() > 0, "of_kind(%s) isn't empty" % kind)


func _test_merge_order() -> void:
	var before: Array[String] = ["res://b.tres", "res://a.tres", "res://gone.tres"]
	var disk: Array[String] = ["res://a.tres", "res://b.tres", "res://c.tres"]
	var got := BUILD.merge_order(before, disk)
	_check(got == ["res://b.tres", "res://a.tres", "res://c.tres"],
		"rebuild keeps the order, drops deleted files, adds new ones at the end (%s)" % [got])
	var text := "[ext_resource type=\"Script\" path=\"res://f.gd\" id=\"1_s\"]\n" \
		+ "[ext_resource type=\"Resource\" path=\"res://b.tres\" id=\"2_b\"]\n" \
		+ "[ext_resource type=\"Resource\" path=\"res://a.tres\" id=\"3_a\"]\n" \
		+ "flies = Array[ExtResource(\"1_s\")]([ExtResource(\"2_b\"), ExtResource(\"3_a\")])\n"
	_check(BUILD.listed_paths(text, "flies") == ["res://b.tres", "res://a.tres"],
		"the old order is read from the file's text, so a deleted file can't break a rebuild")
	_check(BUILD.listed_paths(text, "fish").is_empty(), "a field the file doesn't list reads as empty")
	var fresh := BUILD.merge_order([] as Array[String], disk)
	_check(fresh == disk, "a first build lists files in name order")


## A fly that's only data shows up in the fly box of a scene built from a
## catalog that lists it.
func _test_new_fly_reaches_fly_box() -> void:
	var fly := FlyPattern.new()
	fly.id = &"test_hopper"
	fly.display_name = "Test Hopper"
	var cat := Catalog.new()
	cat.flies.append_array(Catalog.shared().flies)
	cat.flies.append(fly)
	_check(cat.fly(&"test_hopper") == fly, "a new fly is found by its id")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	var fishing := main.get_node(^"Fishing")
	_check(fishing.flies == Catalog.shared().flies, "the fly box is the catalog's fly list")
	main.free()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
