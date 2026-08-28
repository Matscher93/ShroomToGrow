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
	_biome_system.unlock_free_biomes()

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
		_biomes, _biomes_data, _biome_system, _prestige)

## Perk levels are set straight on the prestige UpgradeSystem, the way the node
## gate's tests do it: what the perk cost is PerkSystem's rule, not this one's.
func _own_perk(id: StringName, level: int = 1) -> void:
	var def := PerkDef.new()
	def.id = id
	def.max_level = level
	_prestige.register(def)
	_prestige.set_level_for_analysis(id, level)

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

# ─── The prestige gate ───────────────────────────────────────────────────────

func test_an_automation_without_an_unlock_perk_is_open() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	assert_bool(system.is_unlocked(&"test_automation")).is_true()

func test_a_gated_automation_cannot_be_bought_before_its_perk_is_owned() -> void:
	var def := _def(AutomationDef.Kind.BUY_NODES)
	def.unlock_perk_id = &"instinct_reflex"
	var system := _system(def)
	_player.crystals = BigNumber.from_value(1e6)

	assert_bool(system.is_unlocked(&"test_automation")).is_false()
	assert_bool(system.can_buy(&"test_automation")).is_false()
	assert_bool(system.buy(&"test_automation")).is_false()
	assert_int(system.level(&"test_automation")).is_zero()

func test_a_gated_automation_opens_once_its_perk_is_owned() -> void:
	var def := _def(AutomationDef.Kind.BUY_NODES)
	def.unlock_perk_id = &"instinct_reflex"
	var system := _system(def)
	_player.crystals = BigNumber.from_value(1e6)
	_own_perk(&"instinct_reflex")

	assert_bool(system.is_unlocked(&"test_automation")).is_true()
	assert_bool(system.buy(&"test_automation")).is_true()
	assert_int(system.level(&"test_automation")).is_equal(1)

## Levels bought before the gate existed keep running: the gate is on buying, not
## on owning, exactly like the node tiers'.
func test_a_locked_automation_still_fires_the_levels_it_already_owns() -> void:
	var def := _def(AutomationDef.Kind.BUY_NODES)
	def.unlock_perk_id = &"instinct_reflex"
	var system := _system(def)
	_data.add_level(&"test_automation")
	_player.nutrients = BigNumber.from_value(1e6)

	assert_bool(system.is_active(&"test_automation")).is_true()
	assert_bool(system.run(&"test_automation")).is_true()

# ─── The max-level perk ──────────────────────────────────────────────────────

func test_the_ceiling_is_the_authored_one_without_the_perk() -> void:
	var def := _def(AutomationDef.Kind.BUY_NODES, 20)
	def.max_level_perk_id = &"instinct_reflex_cap"
	def.max_level_per_perk_level = 5
	var system := _system(def)
	assert_int(system.max_level(&"test_automation")).is_equal(20)

func test_perk_levels_raise_the_ceiling() -> void:
	var def := _def(AutomationDef.Kind.BUY_NODES, 20)
	def.max_level_perk_id = &"instinct_reflex_cap"
	def.max_level_per_perk_level = 5
	var system := _system(def)
	_own_perk(&"instinct_reflex_cap", 3)
	assert_int(system.max_level(&"test_automation")).is_equal(35)

## A maxed automation becomes buyable again the moment its cap perk is bought,
## with no repurchase or reset in between.
func test_the_raised_ceiling_reopens_a_maxed_automation() -> void:
	var def := _def(AutomationDef.Kind.BUY_NODES, 1)
	def.max_level_perk_id = &"instinct_reflex_cap"
	def.max_level_per_perk_level = 5
	var system := _system(def)
	_player.crystals = BigNumber.from_value(1e6)
	assert_bool(system.buy(&"test_automation")).is_true()
	assert_bool(system.is_maxed(&"test_automation")).is_true()

	_own_perk(&"instinct_reflex_cap")
	assert_bool(system.is_maxed(&"test_automation")).is_false()
	assert_bool(system.buy(&"test_automation")).is_true()

## An automation authored without a ceiling has none to raise, so a cap perk on
## one must not turn "infinite" into a hard limit.
func test_an_uncapped_automation_stays_uncapped() -> void:
	var def := _def(AutomationDef.Kind.BUY_NODES)
	def.max_level_perk_id = &"instinct_reflex_cap"
	def.max_level_per_perk_level = 5
	var system := _system(def)
	_own_perk(&"instinct_reflex_cap", 2)
	assert_int(system.max_level(&"test_automation")).is_zero()
	assert_bool(system.is_maxed(&"test_automation")).is_false()

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

## There is no ceiling on actions per tick - a fixed one silently ate the rate
## upgrades that pushed past it. A tick is bounded by time instead, so a rate
## this absurd has to stop somewhere well short of what it asked for, and finish.
func test_a_tick_stops_at_its_time_budget_rather_than_running_forever() -> void:
	var def := _def(AutomationDef.Kind.BUY_NODES)
	def.base_runs_per_tick = 1e6
	var system := _system(def)
	_data.add_level(&"test_automation")
	# Node costs grow super-exponentially with manual_nodes, so the bank has to be
	# absurd for the budget - not the price - to be what stops the run.
	_player.nutrients = BigNumber.new(1.0, 900)

	system.handle_tick()
	assert_int(_total_manual_nodes()).is_greater(0)
	assert_int(_total_manual_nodes()).is_less(int(1e6))

## Actions the budget cut short are owed, not lost: the rate was paid for, so the
## following ticks pick them up.
func test_actions_cut_short_by_the_budget_are_banked_for_the_next_tick() -> void:
	var def := _def(AutomationDef.Kind.BUY_NODES)
	def.base_runs_per_tick = 1e6
	var system := _system(def)
	_data.add_level(&"test_automation")
	_player.nutrients = BigNumber.new(1.0, 900)

	system.handle_tick()
	var after_one := _total_manual_nodes()
	system.handle_tick()
	assert_int(_total_manual_nodes()).is_greater(after_one)

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

# ─── Firing: biome auto-unlock ───────────────────────────────────────────────

## Arms forest's auto-unlock without going through the crystal purchase, which is
## BiomeSystem's business and tested there.
func _arm_forest_auto_unlock() -> void:
	_biomes_data.set_auto_unlock(&"forest")

func test_an_armed_auto_unlock_buys_the_biome_on_the_next_tick() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_arm_forest_auto_unlock()
	var cost := _biome_system.biome_def(&"forest").unlock_cost
	_player.nutrients = cost.scale(2.0)

	system.handle_tick()

	assert_bool(_biomes_data.is_unlocked(&"forest")).is_true()
	assert_float(_player.nutrients.to_float()).is_equal_approx(cost.to_float(), EPS)

func test_an_armed_auto_unlock_waits_until_the_run_can_afford_the_biome() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_arm_forest_auto_unlock()
	_player.nutrients = _biome_system.biome_def(&"forest").unlock_cost.scale(0.5)

	system.handle_tick()
	assert_bool(_biomes_data.is_unlocked(&"forest")).is_false()

	_player.nutrients = _biome_system.biome_def(&"forest").unlock_cost
	system.handle_tick()
	assert_bool(_biomes_data.is_unlocked(&"forest")).is_true()

func test_a_switched_off_auto_unlock_buys_nothing() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_arm_forest_auto_unlock()
	_biomes_data.set_auto_unlock_enabled(&"forest", false)
	_player.nutrients = BigNumber.from_value(1e12)

	system.handle_tick()

	assert_bool(_biomes_data.is_unlocked(&"forest")).is_false()

func test_a_biome_that_never_bought_an_auto_unlock_stays_locked() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_player.nutrients = BigNumber.from_value(1e12)

	system.handle_tick()

	assert_bool(_biomes_data.is_unlocked(&"forest")).is_false()

func test_the_biome_unlock_outranks_the_automations_that_spend_nutrients() -> void:
	# Exactly the unlock price and nothing more, with a node buyer running the
	# same tick. If the nodes went first they would eat into it and the biome
	# would stay shut on a run that could afford it.
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_data.add_level(&"test_automation")
	_data.add_level(&"test_automation")   # 1.0 actions per tick, so it fires
	_arm_forest_auto_unlock()
	_player.nutrients = _biome_system.biome_def(&"forest").unlock_cost

	system.handle_tick()

	assert_bool(_biomes_data.is_unlocked(&"forest")).is_true()

func test_an_auto_unlock_is_not_charged_again_once_the_biome_is_open() -> void:
	var system := _system(_def(AutomationDef.Kind.BUY_NODES))
	_arm_forest_auto_unlock()
	var cost := _biome_system.biome_def(&"forest").unlock_cost
	_player.nutrients = cost.scale(3.0)

	system.handle_tick()
	system.handle_tick()

	assert_float(_player.nutrients.to_float()).is_equal_approx(cost.scale(2.0).to_float(), EPS)

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

## The meadow upgrades reachable from a standing start, i.e. gated behind zero
## points spent. Anything else cannot be the first step of a sequence.
func _reachable_meadow_ids() -> Array[StringName]:
	var reachable: Array[StringName] = []
	for id in _biome_system.biome_def(&"meadow").upgrade_ids:
		if _biome_upgrades.def(id).min_biome_points_spent == 0:
			reachable.append(id)
	return reachable

func test_replaying_follows_the_recorded_order() -> void:
	_register_biome_upgrades()
	var reachable := _reachable_meadow_ids()
	assert_int(reachable.size()).is_greater(1)
	# Reversed against the authored grid order, so buying the grid-first upgrade
	# would mean the sequence was ignored.
	_data.upgrade_sequences[&"meadow"] = [reachable[reachable.size() - 1], reachable[0]]

	_grant_points(&"meadow", 1)
	var system := _system(_def(AutomationDef.Kind.SPEND_BIOME_POINTS))
	_data.add_level(&"test_automation")

	assert_bool(system.run(&"test_automation")).is_true()
	assert_int(_biome_upgrades.level(reachable[reachable.size() - 1])).is_equal(1)
	assert_int(_biome_upgrades.level(reachable[0])).is_zero()

func test_a_repeated_step_is_how_a_sequence_asks_for_a_second_level() -> void:
	_register_biome_upgrades()
	var reachable := _reachable_meadow_ids()
	var first := reachable[0]
	var second := reachable[1]
	_data.upgrade_sequences[&"meadow"] = [first, first, second]

	_grant_points(&"meadow", 5)
	var system := _system(_def(AutomationDef.Kind.SPEND_BIOME_POINTS))
	_data.add_level(&"test_automation")
	for i in range(3):
		system.run(&"test_automation")

	assert_int(_biome_upgrades.level(first)).is_equal(2)
	assert_int(_biome_upgrades.level(second)).is_equal(1)

func test_a_finished_sequence_buys_nothing_more() -> void:
	_register_biome_upgrades()
	var first := _reachable_meadow_ids()[0]
	_data.upgrade_sequences[&"meadow"] = [first]

	_grant_points(&"meadow", 5)
	var system := _system(_def(AutomationDef.Kind.SPEND_BIOME_POINTS))
	_data.add_level(&"test_automation")
	assert_bool(system.run(&"test_automation")).is_true()

	assert_bool(system.run(&"test_automation")).is_false()
	assert_int(_biome_upgrades.level(first)).is_equal(1)

func test_a_biome_with_no_sequence_is_left_alone() -> void:
	# Nothing was asked for, so nothing is bought. Falling back to grid order
	# would spend the player's points on a build they never picked.
	_register_biome_upgrades()
	_grant_points(&"meadow", 5)
	var system := _system(_def(AutomationDef.Kind.SPEND_BIOME_POINTS))
	_data.add_level(&"test_automation")

	assert_bool(system.run(&"test_automation")).is_false()
	assert_int(_biomes_data.points_spent(&"meadow")).is_zero()

func test_replay_resumes_from_the_start_after_a_prestige() -> void:
	# The whole point of counting rather than storing a cursor: a reset puts
	# every level back to zero, and the same walk rebuilds the same order.
	_register_biome_upgrades()
	var first := _reachable_meadow_ids()[0]
	_data.upgrade_sequences[&"meadow"] = [first, first]

	_grant_points(&"meadow", 9)
	var system := _system(_def(AutomationDef.Kind.SPEND_BIOME_POINTS))
	_data.add_level(&"test_automation")
	system.run(&"test_automation")
	system.run(&"test_automation")
	assert_int(_biome_upgrades.level(first)).is_equal(2)

	_biome_upgrades.reset()
	_biome_system.reset()
	_grant_points(&"meadow", 9)

	assert_bool(system.run(&"test_automation")).is_true()
	assert_int(_biome_upgrades.level(first)).is_equal(1)

func test_a_step_that_is_gated_is_stepped_over_not_waited_on() -> void:
	# Waiting would deadlock: the gate is opened by spending points, and the
	# later step is the only thing left that can spend them.
	_register_biome_upgrades()
	var meadow := _biome_system.biome_def(&"meadow")
	var gated := &""
	for id in meadow.upgrade_ids:
		if _biome_upgrades.def(id).min_biome_points_spent > 0:
			gated = id
			break
	assert_str(String(gated)).is_not_empty()
	var reachable := _reachable_meadow_ids()[0]
	_data.upgrade_sequences[&"meadow"] = [gated, reachable]

	_grant_points(&"meadow", 1)
	var system := _system(_def(AutomationDef.Kind.SPEND_BIOME_POINTS))
	_data.add_level(&"test_automation")

	assert_bool(system.run(&"test_automation")).is_true()
	assert_int(_biome_upgrades.level(reachable)).is_equal(1)

func test_spending_points_reports_nothing_done_without_points() -> void:
	_register_biome_upgrades()
	_data.upgrade_sequences[&"meadow"] = [_reachable_meadow_ids()[0]]
	var system := _system(_def(AutomationDef.Kind.SPEND_BIOME_POINTS))
	_data.add_level(&"test_automation")
	assert_bool(system.run(&"test_automation")).is_false()

# ─── The sequence itself ─────────────────────────────────────────────────────

func test_a_biome_starts_with_no_sequence() -> void:
	var meadow := _biome_system.biome_def(&"meadow")
	assert_array(_data.sequence_for(&"meadow", meadow.upgrade_ids)).is_empty()

func test_appending_records_a_step_per_tap() -> void:
	var meadow := _biome_system.biome_def(&"meadow")
	var first := meadow.upgrade_ids[0]
	_data.append_to_sequence(&"meadow", first)
	_data.append_to_sequence(&"meadow", first)

	var sequence := _data.sequence_for(&"meadow", meadow.upgrade_ids)
	assert_int(sequence.size()).is_equal(2)
	assert_str(String(sequence[0])).is_equal(String(first))

func test_a_stored_sequence_drops_upgrades_the_biome_no_longer_has() -> void:
	# A renamed or deleted UpgradeDef must not leave a step the automation can
	# never satisfy, which would stall everything behind it.
	var meadow := _biome_system.biome_def(&"meadow")
	_data.upgrade_sequences[&"meadow"] = [&"GoneForever", meadow.upgrade_ids[2]]

	var sequence := _data.sequence_for(&"meadow", meadow.upgrade_ids)

	assert_int(sequence.size()).is_equal(1)
	assert_str(String(sequence[0])).is_equal(String(meadow.upgrade_ids[2]))

func test_a_new_upgrade_is_not_added_to_an_existing_sequence() -> void:
	# The sequence is the player's. Silently appending would spend their points
	# on something they never picked.
	var meadow := _biome_system.biome_def(&"meadow")
	_data.upgrade_sequences[&"meadow"] = [meadow.upgrade_ids[0]]

	assert_int(_data.sequence_for(&"meadow", meadow.upgrade_ids).size()).is_equal(1)

## Removal only ever takes the tail. Taking one out of the middle would pull
## every step below it up past the gate it was recorded against, and the replay
## would then skip it without saying so - which is the whole reason reordering
## and mid-list removal do not exist.
func test_removing_takes_the_last_step_and_leaves_the_rest_in_place() -> void:
	var meadow := _biome_system.biome_def(&"meadow")
	_data.append_to_sequence(&"meadow", meadow.upgrade_ids[0])
	_data.append_to_sequence(&"meadow", meadow.upgrade_ids[1])

	assert_bool(_data.remove_last_from_sequence(&"meadow")).is_true()
	assert_int(_data.upgrade_sequences[&"meadow"].size()).is_equal(1)
	assert_str(String(_data.upgrade_sequences[&"meadow"][0])) \
		.is_equal(String(meadow.upgrade_ids[0]))

func test_removing_from_an_empty_sequence_is_refused() -> void:
	assert_bool(_data.remove_last_from_sequence(&"meadow")).is_false()

func test_clearing_empties_the_sequence() -> void:
	var meadow := _biome_system.biome_def(&"meadow")
	_data.append_to_sequence(&"meadow", meadow.upgrade_ids[0])
	_data.append_to_sequence(&"meadow", meadow.upgrade_ids[1])

	_data.clear_sequence(&"meadow")
	assert_array(_data.upgrade_sequences[&"meadow"]).is_empty()

# ─── Amount bought per tick ──────────────────────────────────────────────────
# The card states a rate to the player - AutomationViewModel._rate_at() reads it
# straight off runs_per_tick_at(). These tests are the other half of that
# promise: that a tick actually buys the count it advertises, for every kind,
# over long runs, and at the levels the authored automations reach.

## Each counter below sums exactly what one action of the matching kind writes,
## so "how many did this tick buy" is one subtraction. Nodes already have one,
## _total_manual_nodes().

func _total_biome_size() -> int:
	var total := 0
	for def in _biomes.biomes:
		total += _biome_system.size(def.key)
	return total

func _total_symbiosis_levels() -> int:
	var total := 0
	for node_data in _node_data:
		total += _symbiosis.level(StringName("NodePotency%d" % node_data.node.node_id))
		total += _symbiosis.level(StringName("NodeSynergy%d" % node_data.node.node_id))
	return total

func _total_meadow_upgrade_levels() -> int:
	var total := 0
	for id in _biome_system.biome_def(&"meadow").upgrade_ids:
		total += _biome_upgrades.level(id)
	return total

## A def that fires a flat `rate` actions a tick at level 1, so a test can name
## the count it expects instead of deriving it from the level curve.
func _def_at_rate(kind: AutomationDef.Kind, rate: float) -> AutomationDef:
	var def := _def(kind)
	def.base_runs_per_tick = rate
	def.runs_per_level = 0.0
	return def

## The rate shape every authored res_*.tres uses: level L promises L actions.
func _def_per_level(kind: AutomationDef.Kind) -> AutomationDef:
	var def := _def(kind)
	def.base_runs_per_tick = 1.0
	def.runs_per_level = 1.0
	return def

func _own_levels(count: int) -> void:
	for i in range(count):
		_data.add_level(&"test_automation")

func _repeat(id: StringName, count: int) -> Array[StringName]:
	var steps: Array[StringName] = []
	for i in range(count):
		steps.append(id)
	return steps

## Enough nutrients that price is never what stops a run. Node costs grow
## super-exponentially, so the pile has to be absurd rather than merely large.
func _fund_everything() -> void:
	_player.nutrients = BigNumber.new(1.0, 900)

## What the cheapest tier costs to take `count` levels up from where it stands,
## without moving it.
func _cost_of_first_nodes(count: int) -> BigNumber:
	var before := _nodes[0].manual_nodes
	var total := BigNumber.new(0.0, 0)
	for i in range(count):
		total = total.add(_node_data[0].upgrade_cost())
		_nodes[0].manual_nodes += 1
	_nodes[0].manual_nodes = before
	return total

func test_a_tick_buys_the_promised_count_of_nodes() -> void:
	var system := _system(_def_at_rate(AutomationDef.Kind.BUY_NODES, 3.0))
	_own_levels(1)
	_fund_everything()

	system.handle_tick()

	assert_int(_total_manual_nodes()).is_equal(3)

func test_a_tick_buys_the_promised_count_of_biome_size() -> void:
	var system := _system(_def_at_rate(AutomationDef.Kind.BUY_BIOME_SIZE, 3.0))
	_own_levels(1)
	_fund_everything()

	system.handle_tick()

	assert_int(_total_biome_size()).is_equal(3)

func test_a_tick_buys_the_promised_count_of_symbiosis_levels() -> void:
	_register_symbiosis()
	var system := _system(_def_at_rate(AutomationDef.Kind.BUY_SYMBIOSIS, 3.0))
	_own_levels(1)
	_fund_everything()

	system.handle_tick()

	assert_int(_total_symbiosis_levels()).is_equal(3)

func test_a_tick_buys_the_promised_count_of_biome_upgrades() -> void:
	_register_biome_upgrades()
	_data.upgrade_sequences[&"meadow"] = _repeat(_reachable_meadow_ids()[0], 3)
	_grant_points(&"meadow", 10)
	var system := _system(_def_at_rate(AutomationDef.Kind.SPEND_BIOME_POINTS, 3.0))
	_own_levels(1)

	system.handle_tick()

	assert_int(_total_meadow_upgrade_levels()).is_equal(3)

func test_levels_scale_the_count_a_tick_buys() -> void:
	var system := _system(_def_per_level(AutomationDef.Kind.BUY_NODES))
	_own_levels(4)
	_fund_everything()

	system.handle_tick()
	assert_int(_total_manual_nodes()).is_equal(4)

	_own_levels(3)
	system.handle_tick()
	assert_int(_total_manual_nodes()).is_equal(11)

func test_a_rate_upgrade_scales_the_count_a_tick_buys() -> void:
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

	var system := _system(_def_per_level(AutomationDef.Kind.BUY_NODES))
	_own_levels(4)
	_fund_everything()

	system.handle_tick()

	assert_int(_total_manual_nodes()).is_equal(8)

## A rate below one is a promise about the long run, not about any one tick, so
## the total is what has to hold. The one-action slack is float accumulation in
## the bank - 0.3 is not exactly representable - not a policy of rounding down.
func test_a_fractional_rate_totals_the_promised_count_over_many_ticks() -> void:
	var system := _system(_def_at_rate(AutomationDef.Kind.BUY_NODES, 0.3))
	_own_levels(1)
	_fund_everything()

	for tick in range(100):
		system.handle_tick()

	assert_int(_total_manual_nodes()).is_between(29, 30)

## Every authored automation, driven by one AutomationSystem the way App drives
## it. Each has to deliver its own count in the same tick: the run budget is per
## automation, and all three nutrient spenders draw on one balance, so one of
## them working through its actions must not cut the next one short.
func test_the_authored_automations_each_deliver_their_own_count_in_one_tick() -> void:
	_register_symbiosis()
	_register_biome_upgrades()
	_grant_points(&"meadow", 50)
	_data.upgrade_sequences[&"meadow"] = _repeat(_reachable_meadow_ids()[0], 10)
	_fund_everything()

	var list := load("res://data/automation/all_automations.tres") as AutomationList
	var system := AutomationSystem.new(list, _data, _player, _production, _node_data,
		_symbiosis, _biomes, _biomes_data, _biome_system, _prestige)
	# Levels go straight in: the perk gate is on buying, not on firing, and what
	# a perk costs is PerkSystem's rule rather than this one's.
	for def in list.automations:
		for i in range(3):
			_data.add_level(def.id)
		assert_float(system.runs_per_tick(def.id)) \
			.override_failure_message("%s is authored off the 1.0/1.0 rate shape these counts assume." % [def.id]) \
			.is_equal_approx(3.0, EPS)

	system.handle_tick()

	assert_int(_total_manual_nodes()).is_equal(3)
	assert_int(_total_biome_size()).is_equal(3)
	assert_int(_total_symbiosis_levels()).is_equal(3)
	assert_int(_total_meadow_upgrade_levels()).is_equal(3)

## The rate is a ceiling, not a debt: a tick buys what the run can pay for and
## stops there, and the actions it could not afford are dropped rather than
## carried into the next tick.
func test_a_tick_buys_only_what_the_run_can_afford_and_owes_nothing_after() -> void:
	var system := _system(_def_at_rate(AutomationDef.Kind.BUY_NODES, 5.0))
	_own_levels(1)
	# A hair over two levels of the cheapest tier, because the balance is
	# BigNumber: paying the exact sum back out leaves a float crumb short of the
	# second price. Still nowhere near a third level, nor a level of tier 1.
	_player.nutrients = _cost_of_first_nodes(2).scale(1.0001)
	assert_bool(_player.nutrients.gte(_cost_of_first_nodes(3))) \
		.override_failure_message("The budget stretches to three nodes, so it does not pin the count at 2.") \
		.is_false()

	system.handle_tick()
	assert_int(_total_manual_nodes()).is_equal(2)

	_fund_everything()
	system.handle_tick()
	# 5, not 8: the three the last tick could not afford are gone, not owed.
	assert_int(_total_manual_nodes()).is_equal(7)

## The heavy kind at the level the card actually reaches. SPEND_BIOME_POINTS
## walks the recorded sequence on every single action, so this is where
## RUN_BUDGET_USEC starts ending ticks early: measured against a full 100-step
## meadow plan at level 20, the first three ticks paid the promised 20 and the
## next two came up one and two short, at ~2.1ms each, leaving the last three
## levels to a sixth tick - ten seconds late for a count the card sells per tick.
##
## The frames between the ticks are what closes that gap now, so the plan has to
## finish in the five ticks the rate asks for.
func test_a_top_level_steward_delivers_its_full_rate_every_tick() -> void:
	_register_biome_upgrades()
	var plan: Array[StringName] = []
	for id in _biome_system.biome_def(&"meadow").upgrade_ids:
		plan.append_array(_repeat(id, _biome_upgrades.def(id).max_level))
	_data.upgrade_sequences[&"meadow"] = plan
	_grant_points(&"meadow", plan.size())

	var system := _system(_def_per_level(AutomationDef.Kind.SPEND_BIOME_POINTS))
	_own_levels(20)
	assert_float(system.runs_per_tick(&"test_automation")).is_equal_approx(20.0, EPS)

	for tick in range(plan.size() / 20):
		system.handle_tick()
		_run_frames(system)

	assert_int(_total_meadow_upgrade_levels()).is_equal(plan.size())

## The frames App spends between two ticks, or as many of them as the debt needs.
## The count is a ceiling rather than a measurement: at 60fps a tick is hundreds
## of frames, and the loop stops as soon as nothing is owed.
func _run_frames(system: AutomationSystem, limit: int = 60) -> int:
	var frames := 0
	while system.has_owed() and frames < limit:
		system.handle_frame()
		frames += 1
	return frames

# ─── Paying off what a tick could not run ────────────────────────────────────

## The debt is paid on the frames after the tick, not on the next tick. Ten
## seconds is the base tick, and a card advertising a per-tick count cannot mean
## "next tick" by it.
func test_actions_the_budget_cut_short_are_paid_off_by_the_following_frames() -> void:
	var def := _def(AutomationDef.Kind.BUY_NODES)
	def.base_runs_per_tick = 1e6
	var system := _system(def)
	_data.add_level(&"test_automation")
	# Node costs grow super-exponentially, so the bank has to be absurd for the
	# budget - not the price - to be what stops the run.
	_player.nutrients = BigNumber.new(1.0, 900)

	system.handle_tick()
	var after_the_tick := _total_manual_nodes()
	var owed_after_the_tick := system.owed(&"test_automation")
	assert_int(owed_after_the_tick).is_greater(0)

	# No second tick anywhere in here.
	system.handle_frame()

	assert_int(_total_manual_nodes()).is_greater(after_the_tick)
	assert_int(system.owed(&"test_automation")).is_less(owed_after_the_tick)

## A frame is not a second tick: it only pays off what a tick already charged
## for, so an automation nothing has ticked has nothing to run.
func test_a_frame_buys_nothing_on_its_own() -> void:
	var system := _system(_def_per_level(AutomationDef.Kind.BUY_NODES))
	_own_levels(4)
	_fund_everything()

	for frame in range(10):
		system.handle_frame()

	assert_bool(system.has_owed()).is_false()
	assert_int(_total_manual_nodes()).is_zero()

## Same rule as the banked fraction: switching an automation off stops it rather
## than deferring it, so the debt goes with it instead of firing as a burst on
## the first frame after it is switched back on.
func test_switching_off_drops_the_owed_actions_too() -> void:
	var def := _def(AutomationDef.Kind.BUY_NODES)
	def.base_runs_per_tick = 1e6
	var system := _system(def)
	_data.add_level(&"test_automation")
	_player.nutrients = BigNumber.new(1.0, 900)

	system.handle_tick()
	assert_int(system.owed(&"test_automation")).is_greater(0)
	var after_the_tick := _total_manual_nodes()

	_data.set_enabled(&"test_automation", false)
	system.handle_frame()
	assert_bool(system.has_owed()).is_false()

	_data.set_enabled(&"test_automation", true)
	system.handle_frame()
	assert_int(_total_manual_nodes()).is_equal(after_the_tick)

## A frame that runs out of things it can afford drops the rest of the debt, the
## same way a tick does. Otherwise an automation that idled through a poor tick
## would empty the balance the moment one arrived.
func test_a_frame_that_cannot_afford_an_action_drops_the_rest_of_the_debt() -> void:
	var def := _def(AutomationDef.Kind.BUY_NODES)
	def.base_runs_per_tick = 1e6
	var system := _system(def)
	_data.add_level(&"test_automation")
	_player.nutrients = _cost_of_first_nodes(1).scale(1.0001)

	system.handle_tick()
	assert_int(_total_manual_nodes()).is_equal(1)
	assert_bool(system.has_owed()).is_false()

	_fund_everything()
	system.handle_frame()
	assert_int(_total_manual_nodes()).is_equal(1)
