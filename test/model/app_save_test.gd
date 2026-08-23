extends GdUnitTestSuite
## App's save wiring (autoload/gd_app.gd).
##
## to_save() and load_from_save() are two hand-maintained lists of the same
## sixteen keys, sitting twenty lines apart. CODING_STANDARDS.md asks for one
## field list precisely because two drift: a track added to the writer and missed
## in the reader saves perfectly and never comes back, and nothing in play looks
## wrong until a relaunch. Until the two are driven off one list, this suite is
## what notices.
##
## Driven through the live App autoload, which is what SaveManager serialises.
## Nothing here mutates game state beyond what it puts back.

## Keys to_save() writes that load_from_save() is not expected to read back.
## Empty on purpose - every bucket in the save has a loader. A new entry here
## needs a comment saying why that key is write-only.
const WRITE_ONLY: Array[String] = []

# ─── to_save() / load_from_save() parity ─────────────────────────────────────

func test_every_saved_key_is_read_back_on_load() -> void:
	# The reader fetches each bucket as game.get("<key>", ...), so its source is
	# the list of keys it actually consumes.
	var source := FileAccess.get_file_as_string("res://autoload/gd_app.gd")
	var body := source.substr(source.find("func load_from_save("))
	for key: String in App.to_save():
		if WRITE_ONLY.has(key):
			continue
		assert_bool(body.contains('game.get("%s"' % key)) \
			.override_failure_message(
				"to_save() writes \"%s\" but load_from_save() never reads it, so it is saved and silently dropped on every relaunch." % key
			).is_true()

func test_the_save_round_trips_through_a_real_load() -> void:
	# The blunt version of the check above: whatever to_save() produces has to be
	# something load_from_save() accepts without erroring, and re-saving after the
	# load has to land on the same dictionary.
	var before := App.to_save()
	App.load_from_save(before)
	assert_dict(App.to_save()).is_equal(before)

# ─── Mycelium nodes ──────────────────────────────────────────────────────────

func test_node_counts_are_keyed_by_node_id_not_by_position() -> void:
	# The array this replaced was read back by index, so inserting or reordering a
	# tier in the authored list moved every player's counts onto the wrong tiers.
	var saved := App.mycelium_nodes_to_save()
	for node_data in App.mycelium_node_data:
		assert_bool(saved.has(str(node_data.node.node_id))) \
			.override_failure_message("node %d is missing from the save" % node_data.node.node_id) \
			.is_true()

func test_a_tier_loads_its_own_counts_back() -> void:
	var original := App.mycelium_nodes_to_save()
	var node_data: MyceliumNodeData = App.mycelium_node_data[0]
	var key := str(node_data.node.node_id)

	App.mycelium_nodes_from_save({key: {"manual_nodes": 7,
		"auto_nodes": BigNumber.from_value(1234.0).to_save()}})

	assert_int(node_data.node.manual_nodes).is_equal(7)
	assert_float(node_data.node.auto_nodes.to_float()).is_equal_approx(1234.0, 0.001)
	App.mycelium_nodes_from_save(original)

func test_a_tier_the_save_omits_keeps_what_it_had() -> void:
	# A save written before a tier existed must leave that tier alone rather than
	# reading a neighbour's numbers into it.
	var original := App.mycelium_nodes_to_save()
	var untouched: MyceliumNodeData = App.mycelium_node_data[1]
	untouched.node.manual_nodes = 42

	App.mycelium_nodes_from_save({str(App.mycelium_node_data[0].node.node_id):
		{"manual_nodes": 3, "auto_nodes": {}}})

	assert_int(untouched.node.manual_nodes).is_equal(42)
	App.mycelium_nodes_from_save(original)

func test_a_corrupt_entry_is_skipped_rather_than_taking_the_load_down() -> void:
	var original := App.mycelium_nodes_to_save()
	var node_data: MyceliumNodeData = App.mycelium_node_data[0]
	node_data.node.manual_nodes = 5

	App.mycelium_nodes_from_save({str(node_data.node.node_id): "not a dictionary"})

	assert_int(node_data.node.manual_nodes).is_equal(5)
	App.mycelium_nodes_from_save(original)

# ─── v7 -> v8 migration ──────────────────────────────────────────────────────

func test_v7_node_array_becomes_a_dictionary_keyed_by_position() -> void:
	# Position and id agree for every save written before v8, because the array
	# was always built by walking the authored list in order.
	var data := {"version": 7, "game": {"mycelium_nodes": [
		{"manual_nodes": 1, "auto_nodes": {"m": 1.0, "e": 0}},
		{"manual_nodes": 2, "auto_nodes": {"m": 2.0, "e": 0}},
	]}}

	assert_bool(SaveManager._migrate(data)).is_true()

	assert_int(int(data["version"])).is_equal(SaveManager.SAVE_VERSION)
	assert_dict(data["game"]["mycelium_nodes"]).is_equal({
		"0": {"manual_nodes": 1, "auto_nodes": {"m": 1.0, "e": 0}},
		"1": {"manual_nodes": 2, "auto_nodes": {"m": 2.0, "e": 0}},
	})

func test_the_migration_drops_entries_that_are_not_dictionaries() -> void:
	var data := {"version": 7, "game": {"mycelium_nodes": [
		"junk", {"manual_nodes": 2, "auto_nodes": {"m": 2.0, "e": 0}},
	]}}

	assert_bool(SaveManager._migrate(data)).is_true()

	assert_dict(data["game"]["mycelium_nodes"]).is_equal({
		"1": {"manual_nodes": 2, "auto_nodes": {"m": 2.0, "e": 0}},
	})

func test_the_migration_leaves_a_save_that_is_already_v8_alone() -> void:
	var already := {"3": {"manual_nodes": 9, "auto_nodes": {"m": 1.0, "e": 0}}}
	var data := {"version": 8, "game": {"mycelium_nodes": already.duplicate(true)}}

	assert_bool(SaveManager._migrate(data)).is_true()

	assert_dict(data["game"]["mycelium_nodes"]).is_equal(already)

func test_the_migration_tolerates_a_save_with_no_nodes_at_all() -> void:
	var data := {"version": 7, "game": {}}
	assert_bool(SaveManager._migrate(data)).is_true()
