extends GdUnitTestSuite
## Unit tests for MissionBoostSystem and the MissionBoostTree expansion behind
## it (model/ruins/).
##
## Built against a hand-authored three-rung ladder rather than the shipped data,
## so retuning a rung's curve or gate cannot turn the rules red.

const EPS := 0.000001

var _player: PlayerData
var _upgrades: UpgradeSystem
var _ctx: ResolveContext
var _data: RuinsData
var _list: MissionBoostList
var _system: MissionBoostSystem

func before_test() -> void:
	_player = PlayerData.new()
	_player.relics = BigNumber.from_value(1000.0)
	_player.glyphs = BigNumber.from_value(1000.0)
	_upgrades = UpgradeSystem.new()
	_ctx = ResolveContext.new()
	_data = RuinsData.new()
	_list = _boost_list()
	for def in MissionBoostTree.build(_list):
		_upgrades.register(def)
	_system = MissionBoostSystem.new(_player, _upgrades, _data, _list)

# ─── Fixtures ────────────────────────────────────────────────────────────────

func _currency(type: CurrencyTypes.Types) -> CurrencyDef:
	var def := CurrencyDef.new()
	def.currency_type = type
	return def

func _rung(id: StringName, currency: CurrencyTypes.Types, stat: StringName,
		op: UpgradeEffectDef.Op, per_level: float, base_cost: float, growth: float,
		max_level: int, gate: int) -> MissionBoostDef:
	var effect := UpgradeEffectDef.new()
	effect.stat = stat
	effect.op = op
	effect.per_level = per_level
	effect.level_scaling = UpgradeEffectDef.LevelScaling.LINEAR
	var def := MissionBoostDef.new()
	def.id = id
	def.display_name = String(id)
	def.currency = _currency(currency)
	def.base_cost = BigNumber.from_value(base_cost)
	def.cost_growth = growth
	def.max_level = max_level
	def.min_missions_completed = gate
	def.effects = [effect]
	return def

func _boost_list() -> MissionBoostList:
	var list := MissionBoostList.new()
	list.boosts = [
		# Control: reaches only the board.
		_rung(&"swift", CurrencyTypes.Types.RELICS, &"mission_speed",
			UpgradeEffectDef.Op.MORE, 0.10, 10.0, 2.0, 0, 0),
		# Control, capped.
		_rung(&"wider", CurrencyTypes.Types.GLYPHS, &"mission_slots",
			UpgradeEffectDef.Op.ADD, 1.0, 50.0, 2.0, 2, 0),
		# General: reaches the colony, and gated behind the board being worked.
		_rung(&"roots", CurrencyTypes.Types.RELICS, &"node_production",
			UpgradeEffectDef.Op.MORE, 0.25, 10.0, 2.0, 0, 3),
	]
	return list

# ─── The tree ────────────────────────────────────────────────────────────────

func test_every_authored_rung_becomes_one_upgrade_def() -> void:
	var defs := MissionBoostTree.build(_list)
	assert_int(defs.size()).is_equal(3)
	var ids: Array = []
	for def in defs:
		ids.append(def.id)
	assert_array(ids).contains([&"swift", &"wider", &"roots"])

func test_a_rung_with_no_effects_is_skipped_rather_than_registered() -> void:
	var empty := MissionBoostDef.new()
	empty.id = &"inert"
	var list := MissionBoostList.new()
	list.boosts = [empty]
	assert_int(MissionBoostTree.build(list).size()).is_equal(0)

func test_a_null_list_builds_nothing() -> void:
	assert_int(MissionBoostTree.build(null).size()).is_equal(0)

func test_the_authored_effects_are_carried_across_untouched() -> void:
	var defs := MissionBoostTree.build(_list)
	for def in defs:
		if def.id != &"roots":
			continue
		assert_int(def.effects.size()).is_equal(1)
		# The whole reason a general boost needs no wiring: the stat survives the
		# expansion, so ProductionSystem stacks it like any other upgrade.
		assert_str(String(def.effects[0].stat)).is_equal("node_production")

# ─── Buying ──────────────────────────────────────────────────────────────────

func test_buying_spends_the_rungs_own_currency() -> void:
	assert_bool(_system.buy(&"swift")).is_true()
	assert_int(_system.level(&"swift")).is_equal(1)
	assert_bool(_player.relics.equals(BigNumber.from_value(990.0))).is_true()
	# The glyph balance is untouched: that is a different rung's price.
	assert_bool(_player.glyphs.equals(BigNumber.from_value(1000.0))).is_true()

	assert_bool(_system.buy(&"wider")).is_true()
	assert_bool(_player.glyphs.equals(BigNumber.from_value(950.0))).is_true()

func test_a_short_balance_refuses_the_buy_and_charges_nothing() -> void:
	_player.relics = BigNumber.from_value(1.0)
	assert_bool(_system.can_buy(&"swift")).is_false()
	assert_bool(_system.buy(&"swift")).is_false()
	assert_int(_system.level(&"swift")).is_equal(0)
	assert_bool(_player.relics.equals(BigNumber.from_value(1.0))).is_true()

func test_a_capped_rung_stops_at_its_ceiling() -> void:
	assert_bool(_system.buy(&"wider")).is_true()
	assert_bool(_system.buy(&"wider")).is_true()
	assert_bool(_system.is_maxed(&"wider")).is_true()
	assert_bool(_system.buy(&"wider")).is_false()
	assert_bool(_system.cost(&"wider").equals(BigNumber.new(0.0, 0))).is_true()

func test_an_uncapped_rung_never_maxes() -> void:
	assert_int(_system.max_level(&"swift")).is_equal(0)
	assert_bool(_system.is_maxed(&"swift")).is_false()

# ─── Gates ───────────────────────────────────────────────────────────────────

func test_a_gated_rung_opens_on_the_mission_tally() -> void:
	assert_bool(_system.is_unlocked(&"roots")).is_false()
	assert_int(_system.missions_until_unlock(&"roots")).is_equal(3)
	assert_bool(_system.buy(&"roots")).is_false()
	_data.missions_completed = 3
	assert_bool(_system.is_unlocked(&"roots")).is_true()
	assert_int(_system.missions_until_unlock(&"roots")).is_equal(0)
	assert_bool(_system.buy(&"roots")).is_true()

## Only buying is blocked. A level bought before a threshold moved keeps paying.
func test_a_gate_closing_behind_a_level_does_not_take_it_away() -> void:
	_data.missions_completed = 3
	assert_bool(_system.buy(&"roots")).is_true()
	_data.missions_completed = 0
	assert_bool(_system.is_unlocked(&"roots")).is_false()
	assert_int(_system.level(&"roots")).is_equal(1)

# ─── Reading back ────────────────────────────────────────────────────────────

func test_the_amount_is_what_the_effect_actually_contributes() -> void:
	_system.buy(&"swift")
	_system.buy(&"swift")
	# MORE + LINEAR: two levels contribute 0.20 above the identity.
	assert_float(_system.amount(&"swift", _ctx).to_float()).is_equal_approx(0.20, EPS)
	assert_float(_system.next_level_delta(&"swift", _ctx).to_float()).is_equal_approx(0.10, EPS)

func test_total_levels_sums_the_whole_ladder() -> void:
	_system.buy(&"swift")
	_system.buy(&"wider")
	assert_int(_system.total_levels()).is_equal(2)

func test_the_currency_field_is_derived_from_the_authored_currency() -> void:
	assert_str(String(_system.currency_field(&"swift"))).is_equal("relics")
	assert_str(String(_system.currency_field(&"wider"))).is_equal("glyphs")

func test_an_unknown_rung_is_answered_rather_than_crashed() -> void:
	assert_bool(_system.can_buy(&"nothing")).is_false()
	assert_bool(_system.is_unlocked(&"nothing")).is_false()
	assert_int(_system.level(&"nothing")).is_equal(0)
