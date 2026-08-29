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
