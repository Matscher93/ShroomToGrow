extends GdUnitTestSuite
## Unit tests for AutomationSystem (model/automation/gd_automation_system.gd).
##
## Cost and interval rules use hand-built defs so retuning an automation can't
## turn them red. The firing tests run against the real node and biome data,
## because what one firing may buy is exactly the question.

const EPS := 0.000001

var _data: AutomationData
var _player: PlayerData
var _ctx: ResolveContext
var _symbiosis: UpgradeSystem
var _biome_upgrades: UpgradeSystem
var _prestige: UpgradeSystem
var _production: ProductionSystem
var _nodes: Array[MyceliumNode]
var _node_data: Array[MyceliumNodeData]
var _biomes: BiomeList
var _biomes_data: BiomesData
var _biome_system: BiomeSystem

func before_test() -> void:
	_data = AutomationData.new()
	_player = PlayerData.new()
	_ctx = ResolveContext.new()
	_symbiosis = UpgradeSystem.new()
	_biome_upgrades = UpgradeSystem.new()
	_prestige = UpgradeSystem.new()
	_production = ProductionSystem.new(_symbiosis, _biome_upgrades, _prestige, _ctx)

	# Duplicated and zeroed: load() hands back the one cached MyceliumNodes, and
	# every suite that buys a node mutates it in place for the whole run. Without
	# the reset, tier costs here depend on which tests ran first.
	_nodes = []
	for node in (load("res://data/mycelium_nodes/res_all_mycelium_nodes.tres") as MyceliumNodes).mycelium_nodes:
		var copy: MyceliumNode = node.duplicate()
		copy.manual_nodes = 0
		copy.auto_nodes = BigNumber.new(0.0, 0)
		_nodes.append(copy)
	_node_data = []
	for node in _nodes:
		_node_data.append(MyceliumNodeData.new(_player, node, _prestige))

	_biomes = load("res://data/biomes/all_biomes.tres") as BiomeList
	_biomes_data = BiomesData.new()
	_biome_system = BiomeSystem.new(_biomes, _biomes_data, _player, _nodes, _production,
		_symbiosis, _biome_upgrades, _prestige, _ctx)
	_biome_system.unlock_starting_biomes()

func _def(kind: AutomationDef.Kind, max_level: int = 0) -> AutomationDef:
	var def := AutomationDef.new()
	def.id = &"test_automation"
	def.display_name = "Test"
	def.kind = kind
	def.base_cost = BigNumber.from_value(10.0)
	def.cost_growth = 2.0
	def.cost_growth_exponent = 1.0
	def.max_level = max_level
	def.base_runs_per_tick = 0.5
	def.runs_per_level = 0.5
	return def

func _system(def: AutomationDef) -> AutomationSystem:
	var list := AutomationList.new()
	list.automations = [def]
	return AutomationSystem.new(list, _data, _player, _production, _node_data, _symbiosis,
		_biomes, _biomes_data, _biome_system)

# ─── Buying ──────────────────────────────────────────────────────────────────

func test_the_cost_rises_with_each_level() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	assert_float(system.cost(&"test_automation").to_float()).is_equal_approx(10.0, EPS)
	_data.add_level(&"test_automation")
	assert_float(system.cost(&"test_automation").to_float()).is_equal_approx(20.0, EPS)

func test_buying_spends_crystals_not_nutrients() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_player.crystals = BigNumber.from_value(25.0)
	_player.nutrients = BigNumber.from_value(1000.0)
	assert_bool(system.buy(&"test_automation")).is_true()
	assert_float(_player.crystals.to_float()).is_equal_approx(15.0, EPS)
	assert_float(_player.nutrients.to_float()).is_equal_approx(1000.0, EPS)

func test_buying_is_refused_without_the_crystals() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_player.crystals = BigNumber.from_value(9.0)
	assert_bool(system.can_buy(&"test_automation")).is_false()
	assert_bool(system.buy(&"test_automation")).is_false()
	assert_int(system.level(&"test_automation")).is_zero()

func test_buying_stops_at_max_level() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES, 1))
	_player.crystals = BigNumber.from_value(1e6)
	assert_bool(system.buy(&"test_automation")).is_true()
	assert_bool(system.is_maxed(&"test_automation")).is_true()
	assert_bool(system.buy(&"test_automation")).is_false()

# ─── Timing ──────────────────────────────────────────────────────────────────

func test_an_unowned_automation_has_no_rate() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	assert_float(system.runs_per_tick(&"test_automation")).is_zero()

func test_levels_raise_the_actions_per_tick() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_data.add_level(&"test_automation")
	assert_float(system.runs_per_tick(&"test_automation")).is_equal_approx(0.5, EPS)
	_data.add_level(&"test_automation")
	assert_float(system.runs_per_tick(&"test_automation")).is_equal_approx(1.0, EPS)
	_data.add_level(&"test_automation")
	assert_float(system.runs_per_tick(&"test_automation")).is_equal_approx(1.5, EPS)

func test_automation_rate_upgrades_multiply_the_actions_per_tick() -> void:
	var upgrade := UpgradeDef.new()
	upgrade.id = &"RateTest"
	var effect := UpgradeEffectDef.new()
	effect.stat = &"automation_rate"
	effect.op = UpgradeEffectDef.Op.INCREASED
	effect.scope = UpgradeEffectDef.Scope.GLOBAL
	effect.per_level = 1.0   # +100% rate, so twice the actions
	upgrade.effects = [effect]
	_biome_upgrades.register(upgrade)
	_biome_upgrades.buy_with_points(&"RateTest", true)

	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_data.add_level(&"test_automation")
	assert_float(system.runs_per_tick(&"test_automation")).is_equal_approx(1.0, EPS)

func test_a_sub_one_rate_reads_as_a_tick_countdown() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_data.add_level(&"test_automation")
	assert_int(system.ticks_per_run(&"test_automation")).is_equal(2)
	_data.add_level(&"test_automation")
	assert_int(system.ticks_per_run(&"test_automation")).is_zero()

# ─── Tick driving ────────────────────────────────────────────────────────────

func test_a_fractional_rate_banks_up_instead_of_rounding_away() -> void:
	# At 0.5 actions a tick, rounding down every tick would mean it never fires.
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_data.add_level(&"test_automation")
	_player.nutrients = BigNumber.from_value(1e12)

	system.handle_tick()
	assert_int(_total_manual_nodes()).is_zero()
	system.handle_tick()
	assert_int(_total_manual_nodes()).is_equal(1)
	system.handle_tick()
	assert_int(_total_manual_nodes()).is_equal(1)
	system.handle_tick()
	assert_int(_total_manual_nodes()).is_equal(2)

func test_a_rate_above_one_acts_several_times_in_a_tick() -> void:
	var def := _def(AutomationDef.Kind.BUY_NODES)
	def.base_runs_per_tick = 3.0
	var system := _system(def)
	_data.add_level(&"test_automation")
	_player.nutrients = BigNumber.from_value(1e12)

	system.handle_tick()
	assert_int(_total_manual_nodes()).is_equal(3)

func test_actions_per_tick_are_capped() -> void:
	# An uncapped &"automation_rate" stack would otherwise stall the frame, since
	# each action walks every node tier.
	var def := _def(AutomationDef.Kind.BUY_NODES)
	def.base_runs_per_tick = 1e6
	var system := _system(def)
	_data.add_level(&"test_automation")
	_player.nutrients = BigNumber.from_value(1e30)

	system.handle_tick()
	assert_int(_total_manual_nodes()).is_equal(AutomationSystem.MAX_RUNS_PER_TICK)

func test_ticking_a_switched_off_automation_does_nothing() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_data.add_level(&"test_automation")
	_data.set_enabled(&"test_automation", false)
	_player.nutrients = BigNumber.from_value(1e12)

	for i in range(10):
		system.handle_tick()
	assert_int(_total_manual_nodes()).is_zero()

func test_switching_off_drops_banked_progress_rather_than_deferring_it() -> void:
	# Otherwise switching an automation off and back on fires it instantly with
	# whatever it banked before, which reads as the toggle not working.
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_data.add_level(&"test_automation")
	_player.nutrients = BigNumber.from_value(1e12)

	system.handle_tick()                                  # banks 0.5
	_data.set_enabled(&"test_automation", false)
	system.handle_tick()                                  # clears the bank
	_data.set_enabled(&"test_automation", true)
	system.handle_tick()                                  # banks 0.5 again
	assert_int(_total_manual_nodes()).is_zero()

func test_an_unowned_automation_is_never_driven_by_the_tick() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_player.nutrients = BigNumber.from_value(1e12)
	for i in range(10):
		system.handle_tick()
	assert_int(_total_manual_nodes()).is_zero()

func _total_manual_nodes() -> int:
	var total := 0
	for node in _nodes:
		total += node.manual_nodes
	return total

# ─── Firing: gating ──────────────────────────────────────────────────────────

func test_an_unowned_automation_never_fires() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_player.nutrients = BigNumber.from_value(1e12)
	assert_bool(system.run(&"test_automation")).is_false()

func test_a_switched_off_automation_never_fires() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_data.add_level(&"test_automation")
	_data.set_enabled(&"test_automation", false)
	_player.nutrients = BigNumber.from_value(1e12)
	assert_bool(system.run(&"test_automation")).is_false()

func test_an_owned_automation_defaults_to_switched_on() -> void:
	assert_bool(_data.is_enabled(&"anything")).is_true()

# ─── Firing: nodes ───────────────────────────────────────────────────────────

func test_buying_nodes_takes_the_highest_affordable_tier() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_data.add_level(&"test_automation")
	_player.nutrients = BigNumber.from_value(1e12)

	# Read the expected tier off the fixture rather than writing it in: which
	# tier 1e12 nutrients reaches is a balance number, "the highest one it can
	# reach" is the rule.
	var expected := -1
	for i in range(_node_data.size() - 1, -1, -1):
		if _node_data[i].can_buy_upgrade():
			expected = i
			break
	assert_int(expected) \
		.override_failure_message("Fixture affords no tier at all, so this test proves nothing.") \
		.is_greater(0)

	var before: Array[int] = []
	for node in _nodes:
		before.append(node.manual_nodes)
	assert_bool(system.run(&"test_automation")).is_true()

	var bought := -1
	for i in range(_nodes.size()):
		if _nodes[i].manual_nodes > before[i]:
			bought = i
	assert_int(bought).is_equal(expected)

func test_buying_nodes_falls_back_to_a_tier_it_can_afford() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_data.add_level(&"test_automation")
	_player.nutrients = _node_data[0].upgrade_cost()
	assert_bool(system.run(&"test_automation")).is_true()
	assert_int(_nodes[0].manual_nodes).is_greater(0)

func test_buying_nodes_reports_nothing_bought_when_broke() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_data.add_level(&"test_automation")
	_player.nutrients = BigNumber.new(0.0, 0)
	assert_bool(system.run(&"test_automation")).is_false()

# ─── Firing: biome size ──────────────────────────────────────────────────────

func test_buying_biome_size_picks_the_cheapest_unlocked_biome() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_BIOME_SIZE))
	_data.add_level(&"test_automation")
	_biomes_data.unlock(&"forest")
	_player.nutrients = BigNumber.from_value(1e12)

	assert_bool(system.run(&"test_automation")).is_true()
	# Meadow is authored cheapest to grow, and only unlocked biomes are eligible.
	assert_int(_biome_system.size(&"meadow")).is_equal(1)
	assert_int(_biome_system.size(&"permafrost")).is_zero()

func test_buying_biome_size_announces_the_change() -> void:
	# Every size display binds to App's signal, which is re-emitted off this one.
	var system := _system(_def(AutomationDef.Kind.BUY_BIOME_SIZE))
	_data.add_level(&"test_automation")
	_player.nutrients = BigNumber.from_value(1e12)
	var announced: Array[StringName] = []
	system.biome_size_bought.connect(func(key: StringName) -> void: announced.append(key))

	system.run(&"test_automation")
	assert_array(announced).has_size(1)
	assert_str(String(announced[0])).is_equal("meadow")

func test_buying_biome_size_skips_locked_biomes() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_BIOME_SIZE))
	_data.add_level(&"test_automation")
	_player.nutrients = BigNumber.from_value(1e12)
	system.run(&"test_automation")
	assert_int(_biome_system.size(&"forest")).is_zero()

# ─── Firing: symbiosis ───────────────────────────────────────────────────────

func _register_symbiosis() -> void:
	for def in UpgradeDefLoader.load_all(UpgradeDefLoader.SYMBIOSIS_PATH):
		_symbiosis.register(def)

func test_buying_symbiosis_takes_the_cheapest_affordable_upgrade() -> void:
	_register_symbiosis()
	var system := _system(_def(AutomationDef.Kind.BUY_SYMBIOSIS))
	_data.add_level(&"test_automation")
	_player.nutrients = BigNumber.from_value(1e12)

	assert_bool(system.run(&"test_automation")).is_true()
	assert_int(_symbiosis.level(&"NodePotency0")).is_equal(1)

func test_buying_symbiosis_leaves_synergy_alone_until_forest_is_unlocked() -> void:
	# Mirrors the UI gate: the synergy track is hidden until Forest, so buying it
	# behind the player's back would be a purchase they cannot see.
	_register_symbiosis()
	var system := _system(_def(AutomationDef.Kind.BUY_SYMBIOSIS))
	_data.add_level(&"test_automation")
	_player.nutrients = BigNumber.from_value(1e12)
	for i in range(30):
		system.run(&"test_automation")
	assert_int(_symbiosis.level(&"NodeSynergy0")).is_zero()

	_biomes_data.unlock(&"forest")
	for i in range(30):
		system.run(&"test_automation")
	assert_int(_symbiosis.level(&"NodeSynergy0")).is_greater(0)

# ─── Firing: biome points ────────────────────────────────────────────────────

func _register_biome_upgrades() -> void:
	for def in UpgradeDefLoader.load_all(UpgradeDefLoader.BIOME_PATH):
		_biome_upgrades.register(def)

## Enough biome level for `points` upgrade points, granted through the
## &"biome_points" stat rather than by faking XP.
func _grant_points(biome_key: StringName, points: int) -> void:
	var upgrade := UpgradeDef.new()
	upgrade.id = &"PointGrant"
	var effect := UpgradeEffectDef.new()
	effect.stat = &"biome_points"
	effect.op = UpgradeEffectDef.Op.ADD
	effect.scope = UpgradeEffectDef.Scope.NODE
	effect.target = biome_key
	effect.per_level = float(points)
	upgrade.effects = [effect]
	_prestige.register(upgrade)
	_prestige.buy_with_points(&"PointGrant", true)

func test_spending_points_follows_the_plan_order() -> void:
	_register_biome_upgrades()
	var meadow := _biome_system.biome_def(&"meadow")
	# Reversed, so buying the authored-first upgrade would mean the plan was
	# ignored. Only entries needing 0 points spent are reachable from a standing
	# start, so the reversal is applied within that reachable set.
	var reachable: Array[StringName] = []
	for id in meadow.upgrade_ids:
		if _biome_upgrades.def(id).min_biome_points_spent == 0:
			reachable.append(id)
	assert_int(reachable.size()).is_greater(1)
	var plan: Array = []
	for i in range(reachable.size() - 1, -1, -1):
		plan.append({"id": reachable[i], "target": 0})
	_data.point_plan[&"meadow"] = plan

	_grant_points(&"meadow", 1)
	var system := _system(_def(AutomationDef.Kind.SPEND_BIOME_POINTS))
	_data.add_level(&"test_automation")

	assert_bool(system.run(&"test_automation")).is_true()
	assert_int(_biome_upgrades.level(reachable[reachable.size() - 1])).is_equal(1)
	assert_int(_biome_upgrades.level(reachable[0])).is_zero()

func test_spending_points_stops_an_entry_at_its_target_level() -> void:
	_register_biome_upgrades()
	var meadow := _biome_system.biome_def(&"meadow")
	var first := meadow.upgrade_ids[0]
	var second := meadow.upgrade_ids[1]
	_data.point_plan[&"meadow"] = [
		{"id": first, "target": 2},
		{"id": second, "target": 0},
	]

	_grant_points(&"meadow", 5)
	var system := _system(_def(AutomationDef.Kind.SPEND_BIOME_POINTS))
	_data.add_level(&"test_automation")
	for i in range(3):
		system.run(&"test_automation")

	assert_int(_biome_upgrades.level(first)).is_equal(2)
	assert_int(_biome_upgrades.level(second)).is_equal(1)

func test_spending_points_reports_nothing_done_without_points() -> void:
	_register_biome_upgrades()
	var system := _system(_def(AutomationDef.Kind.SPEND_BIOME_POINTS))
	_data.add_level(&"test_automation")
	assert_bool(system.run(&"test_automation")).is_false()

# ─── The point plan itself ───────────────────────────────────────────────────

func test_a_plan_is_seeded_from_the_biomes_grid_order() -> void:
	var meadow := _biome_system.biome_def(&"meadow")
	var plan := _data.plan_for(&"meadow", meadow.upgrade_ids)
	assert_int(plan.size()).is_equal(meadow.upgrade_ids.size())
	for i in range(plan.size()):
		assert_str(String(plan[i]["id"])).is_equal(String(meadow.upgrade_ids[i]))
		assert_int(plan[i]["target"]).is_zero()

func test_a_stored_plan_reconciles_with_the_biomes_current_upgrades() -> void:
	# A saved plan naming an upgrade that no longer exists must not strand the
	# automation, and an upgrade added since has to become reachable.
	var meadow := _biome_system.biome_def(&"meadow")
	_data.point_plan[&"meadow"] = [
		{"id": &"GoneForever", "target": 3},
		{"id": meadow.upgrade_ids[2], "target": 1},
	]
	var plan := _data.plan_for(&"meadow", meadow.upgrade_ids)

	assert_int(plan.size()).is_equal(meadow.upgrade_ids.size())
	assert_str(String(plan[0]["id"])).is_equal(String(meadow.upgrade_ids[2]))
	assert_int(plan[0]["target"]).is_equal(1)
	for entry: Dictionary in plan:
		assert_bool(meadow.upgrade_ids.has(StringName(entry["id"]))).is_true()

func test_moving_an_entry_reorders_the_plan() -> void:
	var meadow := _biome_system.biome_def(&"meadow")
	_data.plan_for(&"meadow", meadow.upgrade_ids)
	var second: StringName = _data.point_plan[&"meadow"][1]["id"]

	assert_bool(_data.move_entry(&"meadow", 1, 0)).is_true()
	assert_str(String(_data.point_plan[&"meadow"][0]["id"])).is_equal(String(second))

func test_moving_off_either_end_is_refused() -> void:
	var meadow := _biome_system.biome_def(&"meadow")
	_data.plan_for(&"meadow", meadow.upgrade_ids)
	assert_bool(_data.move_entry(&"meadow", 0, -1)).is_false()
	assert_bool(_data.move_entry(&"meadow", 9, 10)).is_false()
