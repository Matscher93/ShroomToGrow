extends GdUnitTestSuite
## Unit tests for ScopeLabel (viewmodel/gd_scope_label.gd).
##
## Driven through the live App autoload, because naming a node means looking it
## up in the authored node list, which is what the real callers do. Nothing here
## writes game state.

func _effect(scope: UpgradeEffectDef.Scope, target: StringName) -> UpgradeEffectDef:
	var e := UpgradeEffectDef.new()
	e.stat = &"node_production"
	e.scope = scope
	e.target = target
	return e

func test_a_global_key_has_no_name() -> void:
	# Most effects are global, and "global" on every row is noise.
	assert_str(ScopeLabel.of_key("g")).is_empty()
	assert_str(ScopeLabel.of_effect(_effect(UpgradeEffectDef.Scope.GLOBAL, &""))).is_empty()

func test_a_node_key_becomes_the_tier_name() -> void:
	var node: MyceliumNode = App.nodes.mycelium_nodes[0]
	assert_str(ScopeLabel.of_key("n:%d" % node.node_id)).is_equal(node.name)
	assert_str(ScopeLabel.of_effect(_effect(UpgradeEffectDef.Scope.NODE, node.id_key))) \
		.is_equal(node.name)

func test_a_node_key_no_tier_answers_to_falls_back_to_the_id() -> void:
	# A drifted target reads as a mistake rather than as nothing.
	assert_str(ScopeLabel.of_key("n:99")).is_equal("node 99")

func test_a_tag_key_becomes_the_group_name() -> void:
	assert_str(ScopeLabel.of_key("t:canopy")).is_equal("Canopy")
	assert_str(ScopeLabel.of_effect(_effect(UpgradeEffectDef.Scope.TAG, &"canopy"))) \
		.is_equal("Canopy")

func test_effects_sharing_a_scope_report_it() -> void:
	assert_str(ScopeLabel.of_effects([
		_effect(UpgradeEffectDef.Scope.TAG, &"canopy"),
		_effect(UpgradeEffectDef.Scope.TAG, &"canopy"),
	])).is_equal("Canopy")

func test_effects_with_different_scopes_share_none() -> void:
	# An upgrade whose effects disagree has no one scope to append to its name.
	assert_str(ScopeLabel.of_effects([
		_effect(UpgradeEffectDef.Scope.TAG, &"canopy"),
		_effect(UpgradeEffectDef.Scope.TAG, &"lower"),
	])).is_empty()
	assert_str(ScopeLabel.of_effects([
		_effect(UpgradeEffectDef.Scope.TAG, &"canopy"),
		_effect(UpgradeEffectDef.Scope.GLOBAL, &""),
	])).is_empty()

func test_keys_that_disagree_share_none() -> void:
	assert_str(ScopeLabel.of_keys([{"key": "t:canopy"}, {"key": "g"}])).is_empty()
	assert_str(ScopeLabel.of_keys([{"key": "t:canopy"}, {"key": "t:canopy"}])).is_equal("Canopy")

func test_a_suffix_is_only_added_to_a_named_scope() -> void:
	assert_str(ScopeLabel.suffix("")).is_empty()
	assert_str(ScopeLabel.suffix("Canopy")).is_equal(" on Canopy")

# ─── Reach ───────────────────────────────────────────────────────────────────

func _stat_effect(stat: StringName, scope: UpgradeEffectDef.Scope,
		target: StringName) -> UpgradeEffectDef:
	var e := _effect(scope, target)
	e.stat = stat
	return e

## The one number nothing else in the code says out loud: the card counts tiers
## from one and node_id counts from zero. res_node_l7.tres is Grove and the Reach
## perk that opens it says "Level 8 nodes (Grove)".
func test_a_tier_is_named_with_the_level_the_player_counts_from() -> void:
	var node: MyceliumNode = App.nodes.mycelium_nodes[7]
	assert_str(ScopeLabel.node_phrase(String(node.id_key))) \
		.is_equal("%s (Level %d)" % [node.name, node.node_id + 1])

func test_a_target_that_is_not_a_tier_has_no_phrase() -> void:
	# A biome key goes through node_name() instead, and picking up a level number
	# on the way would invent a tier that does not exist.
	assert_str(ScopeLabel.node_phrase("permafrost")).is_empty()

func test_a_global_node_effect_reaches_every_node() -> void:
	assert_str(ScopeLabel.reach([
		_stat_effect(&"node_production", UpgradeEffectDef.Scope.GLOBAL, &""),
	])).is_equal("all nodes")

func test_a_global_effect_on_another_stat_reaches_nothing_worth_saying() -> void:
	# "Affects all nodes" on a tick perk would be a promise about the wrong thing.
	assert_str(ScopeLabel.reach([
		_stat_effect(&"tick_rate", UpgradeEffectDef.Scope.GLOBAL, &""),
	])).is_empty()
	assert_str(ScopeLabel.reach_sentence([
		_stat_effect(&"tick_rate", UpgradeEffectDef.Scope.GLOBAL, &""),
	])).is_empty()

func test_one_tier_is_named_and_levelled() -> void:
	var node: MyceliumNode = App.nodes.mycelium_nodes[3]
	assert_str(ScopeLabel.reach_sentence([
		_effect(UpgradeEffectDef.Scope.NODE, node.id_key),
	])).is_equal("Affects %s (Level %d)." % [node.name, node.node_id + 1])

## Well projects author their boons in funding order, which is not tier order.
func test_several_tiers_are_listed_in_tier_order() -> void:
	var nodes: Array[MyceliumNode] = App.nodes.mycelium_nodes
	var text := ScopeLabel.reach([
		_effect(UpgradeEffectDef.Scope.NODE, nodes[4].id_key),
		_effect(UpgradeEffectDef.Scope.NODE, nodes[1].id_key),
		_effect(UpgradeEffectDef.Scope.NODE, nodes[2].id_key),
	])
	assert_str(text).is_equal("%s (Level 2), %s (Level 3) and %s (Level 5)" \
		% [nodes[1].name, nodes[2].name, nodes[4].name])

## The Well's shape: one boon on every node, two more on tiers it was funded for.
## Saying only "all nodes" would hide the tiers, listing only the tiers would hide
## the rest of the payout.
func test_a_global_effect_and_tiers_say_both() -> void:
	var nodes: Array[MyceliumNode] = App.nodes.mycelium_nodes
	assert_str(ScopeLabel.reach([
		_stat_effect(&"node_production", UpgradeEffectDef.Scope.GLOBAL, &""),
		_effect(UpgradeEffectDef.Scope.NODE, nodes[1].id_key),
		_effect(UpgradeEffectDef.Scope.NODE, nodes[4].id_key),
	])).is_equal("all nodes, with extra on %s (Level 2) and %s (Level 5)" \
		% [nodes[1].name, nodes[4].name])

func test_a_repeated_tier_is_named_once() -> void:
	var node: MyceliumNode = App.nodes.mycelium_nodes[0]
	assert_str(ScopeLabel.reach([
		_effect(UpgradeEffectDef.Scope.NODE, node.id_key),
		_stat_effect(&"potency_production", UpgradeEffectDef.Scope.NODE, node.id_key),
	])).is_equal("%s (Level 1)" % node.name)

## Bounty's perks land on a biome, not a tier, so there is no level to name.
func test_a_biome_target_is_named_without_a_level() -> void:
	assert_str(ScopeLabel.reach([
		_stat_effect(&"biome_points", UpgradeEffectDef.Scope.NODE, &"permafrost"),
	])).is_equal(ScopeLabel.node_name("permafrost"))

## An expedition reward targets a farm. Before the farms were looked up this read
## as "node farm_tap_the_seeps" - the id, on a card the player is reading.
func test_a_farm_target_is_named() -> void:
	assert_str(ScopeLabel.node_name("farm_tap_the_seeps")).is_equal("Tap the Seeps")

func test_a_boost_scope_reaches_the_tier_it_is_kept_to() -> void:
	var node: MyceliumNode = App.nodes.mycelium_nodes[0]
	assert_str(ScopeLabel.reach_of(UpgradeEffectDef.Scope.NODE, node.id_key,
		&"node_production")).is_equal("%s (Level 1)" % node.name)

func test_a_reach_of_nothing_is_no_sentence() -> void:
	assert_str(ScopeLabel.reach([])).is_empty()
	assert_str(ScopeLabel.sentence("")).is_empty()
	assert_str(ScopeLabel.sentence("all nodes")).is_equal("Affects all nodes.")
