extends GdUnitTestSuite
## The offline-income popup's snapshot reader (view/offline_income/gd_offline_income.gd).
##
## The popup diffs two App.to_save() snapshots to say what the catch-up produced
## per node tier. That makes it a second reader of the mycelium_nodes bucket,
## sitting in the view layer where none of the save-shape suites look - which is
## how it kept reading the pre-v8 array-by-position shape for a whole version
## after App.mycelium_nodes_to_save() started writing a dictionary keyed by
## node_id. Every launch with a real save threw on it.
##
## So these drive the reader off a genuine App.to_save() rather than a hand-built
## fixture: a fixture would have to be written in whatever shape the reader
## expects, which is exactly the thing that went wrong.

const OfflineIncomeView := preload("res://view/offline_income/gd_offline_income.gd")

func test_node_counts_are_read_out_of_a_real_snapshot() -> void:
	var node: MyceliumNode = App.mycelium_node_data[0].node
	var original := node.auto_nodes
	node.auto_nodes = BigNumber.from_value(4321.0)

	var snapshot := App.to_save()
	assert_bool(OfflineIncomeView.node_count(snapshot, node.node_id)
		.equals(BigNumber.from_value(4321.0))) \
		.override_failure_message(
			"the popup could not read tier %d back out of App.to_save()" % node.node_id
		).is_true()

	node.auto_nodes = original

func test_counts_follow_node_id_not_position() -> void:
	# The array this replaced was read back by index, so inserting or reordering a
	# tier moved every player's counts onto the wrong ones. Two tiers with
	# different counts is what notices if the reader drifts back to position.
	var first: MyceliumNode = App.mycelium_node_data[0].node
	var second: MyceliumNode = App.mycelium_node_data[1].node
	var original_first := first.auto_nodes
	var original_second := second.auto_nodes
	first.auto_nodes = BigNumber.from_value(11.0)
	second.auto_nodes = BigNumber.from_value(22.0)

	var snapshot := App.to_save()
	assert_bool(OfflineIncomeView.node_count(snapshot, second.node_id)
		.equals(BigNumber.from_value(22.0))) \
		.override_failure_message("tier %d read back another tier's count" % second.node_id) \
		.is_true()

	first.auto_nodes = original_first
	second.auto_nodes = original_second

func test_a_tier_missing_from_the_snapshot_reads_as_zero() -> void:
	# A snapshot taken before a tier existed simply has no entry for it, and the
	# first snapshot of a catch-up is compared against the second, so this is the
	# ordinary path for a tier the player has only just unlocked.
	var node: MyceliumNode = App.mycelium_node_data[0].node
	var zero := BigNumber.new(0.0, 0)

	assert_bool(OfflineIncomeView.node_count({}, node.node_id).equals(zero)).is_true()

	var snapshot := App.to_save()
	var saved_nodes: Dictionary = snapshot["mycelium_nodes"]
	saved_nodes.erase(str(node.node_id))
	assert_bool(OfflineIncomeView.node_count(snapshot, node.node_id).equals(zero)).is_true()

func test_a_non_dictionary_entry_reads_as_zero() -> void:
	# Cheap next to what it protects: the reader aborting mid-diff is what left
	# _update_visuals calling .sub() on a null and taking the popup down with it.
	var node: MyceliumNode = App.mycelium_node_data[0].node
	var snapshot := {"mycelium_nodes": {str(node.node_id): "not a dictionary"}}
	assert_bool(OfflineIncomeView.node_count(snapshot, node.node_id)
		.equals(BigNumber.new(0.0, 0))).is_true()
