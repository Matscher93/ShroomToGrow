extends GdUnitTestSuite
## Unit tests for the change-signal batching PlayerData and MyceliumNode share
## with UpgradeSystem (see upgrade_system_test.gd for that one).
##
## What it exists for: the offline catch-up writes nutrients, tick_count and
## every tier's auto_nodes once per tick, tens of thousands of times, and each
## write fans out through the bound ViewModels into rebuilt label strings. The
## contract tested here is that a batch collapses that to one emit per field
## while leaving the state itself readable as it goes.

const EPS := 0.000001

## Counts a change signal without needing a Node to connect from. `last` keeps
## the value the emit carried, since a batch has to report the value the field
## ended on rather than the one it had when the batch opened.
class ChangeCounter extends RefCounted:
	var count := 0
	var last: Variant = null
	func on_changed(value: Variant) -> void:
		count += 1
		last = value

func _watch(emitter: Object, signal_name: StringName) -> ChangeCounter:
	var counter := ChangeCounter.new()
	emitter.connect(signal_name, counter.on_changed)
	return counter

func _node() -> MyceliumNode:
	var node := MyceliumNode.new()
	node.auto_nodes = BigNumber.from_value(0.0)
	return node

# ─── PlayerData ──────────────────────────────────────────────────────────────

func test_a_batch_emits_once_however_many_writes_it_holds() -> void:
	var player := PlayerData.new()
	var counter := _watch(player, &"nutrients_changed")

	player.begin_batch()
	for i in range(10):
		player.nutrients = BigNumber.from_value(float(i + 1))
	assert_int(counter.count).is_zero()
	player.end_batch()

	assert_int(counter.count).is_equal(1)

func test_a_batch_reports_the_value_the_field_ended_on() -> void:
	var player := PlayerData.new()
	var counter := _watch(player, &"nutrients_changed")

	player.begin_batch()
	player.nutrients = BigNumber.from_value(2.0)
	player.nutrients = BigNumber.from_value(50.0)
	player.end_batch()

	assert_float((counter.last as BigNumber).to_float()).is_equal_approx(50.0, EPS)

func test_a_batch_emits_once_per_field_that_moved() -> void:
	var player := PlayerData.new()
	var nutrients := _watch(player, &"nutrients_changed")
	var water := _watch(player, &"water_changed")
	var ticks := _watch(player, &"tick_count_changed")
	var biomass := _watch(player, &"biomass_changed")

	player.begin_batch()
	for i in range(5):
		player.nutrients = BigNumber.from_value(float(i + 1))
		player.water = BigNumber.from_value(float(i + 1))
		player.tick_count += 1
	player.end_batch()

	assert_int(nutrients.count).is_equal(1)
	assert_int(water.count).is_equal(1)
	assert_int(ticks.count).is_equal(1)
	# Untouched, so it must stay silent - a batch flushing every signal would
	# cost more than the one it saved.
	assert_int(biomass.count).is_zero()

func test_a_batch_that_changed_nothing_emits_nothing() -> void:
	var player := PlayerData.new()
	var counter := _watch(player, &"nutrients_changed")
	player.begin_batch()
	player.end_batch()
	assert_int(counter.count).is_zero()

func test_only_the_outermost_batch_emits() -> void:
	var player := PlayerData.new()
	var counter := _watch(player, &"nutrients_changed")

	player.begin_batch()
	player.begin_batch()
	player.nutrients = BigNumber.from_value(7.0)
	player.end_batch()
	assert_int(counter.count).is_zero()
	player.end_batch()

	assert_int(counter.count).is_equal(1)

func test_a_batched_write_is_visible_to_reads_made_inside_the_batch() -> void:
	# The signal is what waits, not the state. The tick cascade reads nutrients
	# straight back after writing them, and must not see a stale value.
	var player := PlayerData.new()
	player.begin_batch()
	player.nutrients = BigNumber.from_value(42.0)
	assert_float(player.nutrients.to_float()).is_equal_approx(42.0, EPS)
	player.end_batch()

func test_writes_outside_a_batch_still_emit_per_write() -> void:
	var player := PlayerData.new()
	var counter := _watch(player, &"nutrients_changed")
	# From 2, since PlayerData starts on 1 nutrient and the setter's same_value()
	# guard would swallow a write of the value already there.
	for i in range(3):
		player.nutrients = BigNumber.from_value(float(i + 2))
	assert_int(counter.count).is_equal(3)

func test_a_second_batch_starts_clean() -> void:
	var player := PlayerData.new()
	var counter := _watch(player, &"nutrients_changed")

	player.begin_batch()
	player.nutrients = BigNumber.from_value(2.0)
	player.end_batch()
	player.begin_batch()
	player.end_batch()

	assert_int(counter.count).is_equal(1)

# ─── MyceliumNode ────────────────────────────────────────────────────────────

func test_a_node_batch_emits_once_however_many_writes_it_holds() -> void:
	var node := _node()
	var counter := _watch(node, &"auto_nodes_changed")

	node.begin_batch()
	for i in range(10):
		node.auto_nodes = BigNumber.from_value(float(i + 1))
	assert_int(counter.count).is_zero()
	node.end_batch()

	assert_int(counter.count).is_equal(1)
	assert_float((counter.last as BigNumber).to_float()).is_equal_approx(10.0, EPS)

func test_a_batched_node_write_is_visible_inside_the_batch() -> void:
	# The cascade writes the tier below and reads it again on the next tick of
	# the same batch, so the value cannot wait on the signal.
	var node := _node()
	node.begin_batch()
	node.auto_nodes = BigNumber.from_value(9.0)
	assert_float(node.auto_nodes.to_float()).is_equal_approx(9.0, EPS)
	node.end_batch()

func test_a_node_batch_leaves_manual_nodes_alone_when_nothing_bought() -> void:
	var node := _node()
	var manual := _watch(node, &"manual_nodes_changed")
	node.begin_batch()
	node.auto_nodes = BigNumber.from_value(3.0)
	node.end_batch()
	assert_int(manual.count).is_zero()

func test_node_writes_outside_a_batch_still_emit_per_write() -> void:
	var node := _node()
	var counter := _watch(node, &"auto_nodes_changed")
	for i in range(3):
		node.auto_nodes = BigNumber.from_value(float(i + 1))
	assert_int(counter.count).is_equal(3)
