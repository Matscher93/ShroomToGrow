extends GdUnitTestSuite
## Unit tests for UpgradeSystem (model/upgrades/gd_upgrade_system.gd).
##
## Backs all three upgrade tracks (symbiosis, biome upgrades, perks), so a
## defect here is a defect everywhere at once.

const EPS := 0.000001

func _effect(stat: StringName, per_level: float, op: UpgradeEffectDef.Op,
		scope := UpgradeEffectDef.Scope.GLOBAL, target := &"") -> UpgradeEffectDef:
	var e := UpgradeEffectDef.new()
	e.stat = stat
	e.per_level = per_level
	e.op = op
	e.scope = scope
	e.target = target
	return e

func _upgrade(id: StringName, effects: Array[UpgradeEffectDef], max_level := 0) -> UpgradeDef:
	var d := UpgradeDef.new()
	d.id = id
	d.effects = effects
	d.max_level = max_level
	return d

# ─── Registration and levels ─────────────────────────────────────────────────

func test_register_starts_at_level_zero() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"Thing", []))
	assert_bool(system.has_def(&"Thing")).is_true()
	assert_int(system.level(&"Thing")).is_zero()

func test_unknown_id_has_no_def_and_no_level() -> void:
	var system := UpgradeSystem.new()
	assert_object(system.def(&"Nope")).is_null()
	assert_int(system.level(&"Nope")).is_zero()

func test_total_levels_sums_every_track_entry() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"A", []))
	system.register(_upgrade(&"B", []))
	system.from_save({"A": 3, "B": 4})
	assert_int(system.total_levels()).is_equal(7)

func test_reset_clears_levels_but_keeps_defs() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"A", []))
	system.from_save({"A": 5})
	system.reset()
	assert_int(system.level(&"A")).is_zero()
	assert_bool(system.has_def(&"A")).is_true()

# ─── Buying ──────────────────────────────────────────────────────────────────

func test_buy_deducts_currency_and_levels_up() -> void:
	var player := PlayerData.new()
	player.nutrients = BigNumber.from_value(1000.0)
	var system := UpgradeSystem.new()
	var def := _upgrade(&"Thing", [])
	def.base_cost = BigNumber.from_value(100.0)
	system.register(def)

	assert_bool(system.buy(&"Thing", player)).is_true()
	assert_int(system.level(&"Thing")).is_equal(1)
	assert_float(player.nutrients.to_float()).is_equal_approx(900.0, EPS)

func test_buy_refused_when_unaffordable() -> void:
	var player := PlayerData.new()
	player.nutrients = BigNumber.from_value(10.0)
	var system := UpgradeSystem.new()
	var def := _upgrade(&"Thing", [])
	def.base_cost = BigNumber.from_value(100.0)
	system.register(def)

	assert_bool(system.buy(&"Thing", player)).is_false()
	assert_int(system.level(&"Thing")).is_zero()
	assert_float(player.nutrients.to_float()).is_equal_approx(10.0, EPS)

func test_buy_respects_max_level() -> void:
	var player := PlayerData.new()
	player.nutrients = BigNumber.from_value(1e9)
	var system := UpgradeSystem.new()
	var def := _upgrade(&"Capped", [], 2)
	def.base_cost = BigNumber.from_value(1.0)
	system.register(def)

	assert_bool(system.buy(&"Capped", player)).is_true()
	assert_bool(system.buy(&"Capped", player)).is_true()
	assert_bool(system.buy(&"Capped", player)).is_false()
	assert_int(system.level(&"Capped")).is_equal(2)

func test_buy_with_points_takes_a_bool() -> void:
	# The parameter is a flag, not a point count: the caller owns the budget and
	# does the spending itself.
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"Pointed", [], 2))

	assert_bool(system.buy_with_points(&"Pointed", false)).is_false()
	assert_int(system.level(&"Pointed")).is_zero()
	assert_bool(system.buy_with_points(&"Pointed", true)).is_true()
	assert_int(system.level(&"Pointed")).is_equal(1)

func test_buy_with_points_respects_max_level() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"Pointed", [], 1))
	assert_bool(system.buy_with_points(&"Pointed", true)).is_true()
	assert_bool(system.buy_with_points(&"Pointed", true)).is_false()

func test_cost_grows_with_level() -> void:
	var system := UpgradeSystem.new()
	var def := _upgrade(&"Thing", [])
	def.base_cost = BigNumber.from_value(100.0)
	def.cost_growth = 2.0
	system.register(def)

	# base * growth^(level * exponent^level), and the default exponent of 1 leaves
	# that as the plain base * growth^level.
	assert_float(system.cost(&"Thing").to_float()).is_equal_approx(100.0, 0.001)
	system.from_save({"Thing": 1})
	assert_float(system.cost(&"Thing").to_float()).is_equal_approx(200.0, 0.001)
	system.from_save({"Thing": 2})
	assert_float(system.cost(&"Thing").to_float()).is_equal_approx(400.0, 0.001)

# ─── modify() stacking ───────────────────────────────────────────────────────

func test_add_op_is_flat() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"Flat", [_effect(&"stat", 5.0, UpgradeEffectDef.Op.ADD)]))
	system.from_save({"Flat": 2})
	var out := system.modify(&"stat", BigNumber.from_value(1.0), ResolveContext.new())
	assert_float(out.to_float()).is_equal_approx(11.0, EPS)   # 1 + (5*2)

func test_increased_ops_are_additive_with_each_other() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"A", [_effect(&"stat", 0.5, UpgradeEffectDef.Op.INCREASED)]))
	system.register(_upgrade(&"B", [_effect(&"stat", 0.5, UpgradeEffectDef.Op.INCREASED)]))
	system.from_save({"A": 1, "B": 1})
	var out := system.modify(&"stat", BigNumber.from_value(1.0), ResolveContext.new())
	assert_float(out.to_float()).is_equal_approx(2.0, EPS)    # 1 * (1 + 0.5 + 0.5)

func test_more_ops_are_multiplicative_with_each_other() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"A", [_effect(&"stat", 1.0, UpgradeEffectDef.Op.MORE)]))
	system.register(_upgrade(&"B", [_effect(&"stat", 1.0, UpgradeEffectDef.Op.MORE)]))
	system.from_save({"A": 1, "B": 1})
	var out := system.modify(&"stat", BigNumber.from_value(1.0), ResolveContext.new())
	assert_float(out.to_float()).is_equal_approx(4.0, EPS)    # 1 * 2 * 2

func test_node_scope_only_applies_to_its_target() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"NodeOnly", [_effect(&"stat", 1.0,
		UpgradeEffectDef.Op.INCREASED, UpgradeEffectDef.Scope.NODE, &"3")]))
	system.from_save({"NodeOnly": 1})
	var ctx := ResolveContext.new()

	assert_float(system.modify(&"stat", BigNumber.from_value(1.0), ctx, [], &"3").to_float()) \
		.is_equal_approx(2.0, EPS)
	assert_float(system.modify(&"stat", BigNumber.from_value(1.0), ctx, [], &"7").to_float()) \
		.is_equal_approx(1.0, EPS)

func test_unrelated_stat_is_untouched() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"A", [_effect(&"one", 1.0, UpgradeEffectDef.Op.INCREASED)]))
	system.from_save({"A": 1})
	var out := system.modify(&"other", BigNumber.from_value(1.0), ResolveContext.new())
	assert_float(out.to_float()).is_equal_approx(1.0, EPS)

func test_level_zero_upgrades_contribute_nothing() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"A", [_effect(&"stat", 1.0, UpgradeEffectDef.Op.INCREASED)]))
	var out := system.modify(&"stat", BigNumber.from_value(1.0), ResolveContext.new())
	assert_float(out.to_float()).is_equal_approx(1.0, EPS)

func test_dependency_scales_the_effect() -> void:
	var source := ScalingSourceDef.new()
	source.kind = ScalingSourceDef.Kind.NODE_COUNT
	source.key = &"3"
	var e := _effect(&"stat", 1.0, UpgradeEffectDef.Op.INCREASED)
	e.dependency = source

	var ctx := ResolveContext.new()
	ctx.manual_counts[&"3"] = 4
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"Scaled", [e]))
	system.from_save({"Scaled": 1})

	# +100% per level, scaled by 4 hand-bought nodes -> 1 * (1 + 4)
	assert_float(system.modify(&"stat", BigNumber.from_value(1.0), ctx).to_float()) \
		.is_equal_approx(5.0, EPS)

# ─── Batching ────────────────────────────────────────────────────────────────

## Counts upgrades_changed without needing a Node to connect from.
class ChangeCounter extends RefCounted:
	var count := 0
	func on_changed() -> void:
		count += 1

func _counter(system: UpgradeSystem) -> ChangeCounter:
	var counter := ChangeCounter.new()
	system.upgrades_changed.connect(counter.on_changed)
	return counter

func test_a_batch_emits_once_however_many_purchases_it_holds() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"Thing", []))
	var counter := _counter(system)

	system.begin_batch()
	for i in range(10):
		system.buy_with_points(&"Thing", true)
	assert_int(counter.count).is_zero()
	system.end_batch()

	assert_int(counter.count).is_equal(1)
	assert_int(system.level(&"Thing")).is_equal(10)

func test_a_batch_that_changed_nothing_emits_nothing() -> void:
	var system := UpgradeSystem.new()
	var counter := _counter(system)
	system.begin_batch()
	system.end_batch()
	assert_int(counter.count).is_zero()

func test_only_the_outermost_batch_emits() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"Thing", []))
	var counter := _counter(system)

	system.begin_batch()
	system.begin_batch()
	system.buy_with_points(&"Thing", true)
	system.end_batch()
	assert_int(counter.count).is_zero()
	system.end_batch()
	assert_int(counter.count).is_equal(1)

func test_a_batched_purchase_is_visible_to_reads_made_inside_the_batch() -> void:
	# The signal is what waits, not the state: an automation buys and then reads
	# back within the same tick, and must not see a stale cache.
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"A", [_effect(&"stat", 1.0, UpgradeEffectDef.Op.INCREASED)]))
	var ctx := ResolveContext.new()

	system.begin_batch()
	system.buy_with_points(&"A", true)
	assert_float(system.modify(&"stat", BigNumber.from_value(1.0), ctx).to_float()) \
		.is_equal_approx(2.0, EPS)
	system.end_batch()

func test_purchases_outside_a_batch_still_emit_per_purchase() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"Thing", []))
	var counter := _counter(system)
	system.buy_with_points(&"Thing", true)
	system.buy_with_points(&"Thing", true)
	assert_int(counter.count).is_equal(2)

# ─── Persistence ─────────────────────────────────────────────────────────────

func test_save_only_records_bought_levels() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"Bought", []))
	system.register(_upgrade(&"Untouched", []))
	system.from_save({"Bought": 2})
	var saved := system.to_save()
	assert_dict(saved).contains_keys(["Bought"])
	assert_dict(saved).has_size(1)

func test_lifetime_levels_counts_both_purchase_paths() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"Points", []))
	system.register(_upgrade(&"Currency", []))
	var player := PlayerData.new()
	player.nutrients = BigNumber.from_value(1e9)

	system.buy_with_points(&"Points", true)
	system.buy(&"Currency", player)
	system.buy(&"Currency", player)

	assert_int(system.lifetime_levels).is_equal(3)

func test_lifetime_levels_ignores_refused_purchases() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"Thing", []))
	var player := PlayerData.new()
	player.nutrients = BigNumber.new(0.0, 0)

	assert_bool(system.buy(&"Thing", player)).is_false()
	assert_bool(system.buy_with_points(&"Thing", false)).is_false()
	assert_int(system.lifetime_levels).is_zero()

func test_lifetime_levels_survives_a_reset() -> void:
	# A prestige clears what the player holds, it does not un-buy what they
	# bought. The symbiosis achievement measures this.
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"Thing", []))
	system.buy_with_points(&"Thing", true)
	system.buy_with_points(&"Thing", true)

	system.reset()

	assert_int(system.total_levels()).is_zero()
	assert_int(system.lifetime_levels).is_equal(2)

func test_lifetime_levels_round_trips_without_becoming_an_upgrade() -> void:
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"Thing", []))
	system.buy_with_points(&"Thing", true)

	var restored := UpgradeSystem.new()
	restored.register(_upgrade(&"Thing", []))
	restored.from_save(system.to_save())

	assert_int(restored.lifetime_levels).is_equal(1)
	assert_int(restored.level(&"Thing")).is_equal(1)
	# The reserved key must not be read back as an upgrade id.
	assert_int(restored.level(StringName(UpgradeSystem.LIFETIME_KEY))).is_zero()

func test_loading_a_save_does_not_count_as_buying() -> void:
	# from_save() writes levels directly, and counting those would inflate the
	# achievement by the whole save on every launch.
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"Thing", []))
	system.from_save({"Thing": 12})
	assert_int(system.lifetime_levels).is_zero()

func test_load_drops_unknown_ids_instead_of_crashing() -> void:
	# A renamed or deleted UpgradeDef must not leave an id in _levels that
	# _rebuild() has no def for, which errors on every cache rebuild.
	var system := UpgradeSystem.new()
	system.register(_upgrade(&"Known", [_effect(&"stat", 1.0, UpgradeEffectDef.Op.INCREASED)]))
	system.from_save({"Known": 1, "DeletedUpgrade": 7})

	assert_int(system.level(&"Known")).is_equal(1)
	assert_int(system.level(&"DeletedUpgrade")).is_zero()
	# The rebuild that would error on an unknown id.
	var out := system.modify(&"stat", BigNumber.from_value(1.0), ResolveContext.new())
	assert_float(out.to_float()).is_equal_approx(2.0, EPS)
