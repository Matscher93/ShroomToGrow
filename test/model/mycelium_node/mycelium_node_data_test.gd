extends GdUnitTestSuite
## Unit tests for MyceliumNodeData (model/mycelium_node/gd_mycelium_node_data.gd),
## focused on the perk gate on the higher tiers. Built with its dependencies
## injected, no App autoload involved.

var _player: PlayerData
var _prestige: UpgradeSystem

func before_test() -> void:
	_player = PlayerData.new()
	_player.nutrients = BigNumber.from_value(1e12)
	_prestige = UpgradeSystem.new()

func _node(unlock_perk_id: StringName) -> MyceliumNode:
	var node := MyceliumNode.new()
	node.node_id = 3
	node.unlock_perk_id = unlock_perk_id
	node.initial_cost = BigNumber.from_value(1.0)
	return node

func _register_perk(id: StringName) -> void:
	var def := PerkDef.new()
	def.id = id
	def.max_level = 1
	_prestige.register(def)

func test_tier_without_an_unlock_perk_is_unlocked() -> void:
	var data := MyceliumNodeData.new(_player, _node(&""), _prestige)
	assert_bool(data.is_unlocked()).is_true()
	assert_bool(data.can_buy_upgrade()).is_true()

func test_gated_tier_cannot_be_bought_before_its_perk_is_owned() -> void:
	_register_perk(&"reach_4")
	var node := _node(&"reach_4")
	var data := MyceliumNodeData.new(_player, node, _prestige)

	assert_bool(data.is_unlocked()).is_false()
	# Affordability is unaffected — only the gate blocks the purchase.
	assert_bool(data.can_afford_upgrade()).is_true()
	assert_bool(data.can_buy_upgrade()).is_false()
	assert_bool(data.buy_upgrade()).is_false()
	assert_int(node.manual_nodes).is_equal(0)

func test_gated_tier_opens_once_its_perk_is_owned() -> void:
	_register_perk(&"reach_4")
	var node := _node(&"reach_4")
	var data := MyceliumNodeData.new(_player, node, _prestige)
	_prestige.from_save({"reach_4": 1})

	assert_bool(data.is_unlocked()).is_true()
	assert_bool(data.buy_upgrade()).is_true()
	assert_int(node.manual_nodes).is_equal(1)

func test_every_authored_unlock_perk_id_exists_in_the_perk_tree() -> void:
	# The id is the only thing binding a node tier to its perk, so a typo here
	# would lock that tier forever with nothing able to open it.
	var nodes := load("res://data/mycelium_nodes/res_all_mycelium_nodes.tres") as MyceliumNodes
	var branches := load("res://data/prestige/all_branches.tres") as PerkBranchList
	var perk_ids := {}
	for perk in PerkTree.build(branches):
		perk_ids[perk.id] = true

	for node in nodes.mycelium_nodes:
		if node.unlock_perk_id.is_empty():
			continue
		assert_bool(perk_ids.has(node.unlock_perk_id)) \
			.override_failure_message("Node '%s' wants perk '%s', which no branch defines." \
				% [node.name, node.unlock_perk_id]).is_true()

func test_the_first_three_tiers_are_free_and_the_rest_are_gated() -> void:
	var nodes := load("res://data/mycelium_nodes/res_all_mycelium_nodes.tres") as MyceliumNodes
	for node in nodes.mycelium_nodes:
		if node.node_id < 3:
			assert_str(String(node.unlock_perk_id)).is_empty()
		else:
			assert_str(String(node.unlock_perk_id)).is_not_empty()
