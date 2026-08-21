extends GdUnitTestSuite
## Unit tests for PlayerLevelSystem (model/growth/gd_player_level_system.gd).
##
## Built against a hand-made producer list rather than data/growth/, so retuning
## an authored per-level rate cannot turn the rules red.

const EPS := 0.000001

var _player: PlayerData
var _upgrades: UpgradeSystem
var _list: GrowthProducerList
var _system: PlayerLevelSystem

func before_test() -> void:
	_player = PlayerData.new()
	_upgrades = UpgradeSystem.new()
	_list = _build_list()
	for def in GrowthTree.build(_list):
		_upgrades.register(def)
	_system = PlayerLevelSystem.new(_player, _upgrades, _list)

func _currency(type: CurrencyTypes.Types, currency_name: String) -> CurrencyDef:
	var def := CurrencyDef.new()
	def.currency_type = type
	def.currency_name = currency_name
	return def

func _producer(type: CurrencyTypes.Types, currency_name: String, stat: StringName) -> GrowthProducerDef:
	var def := GrowthProducerDef.new()
	def.currency = _currency(type, currency_name)
	def.stat = stat
	def.scope = UpgradeEffectDef.Scope.GLOBAL
	def.lp_per_level = 0.05
	def.daily_per_level = 0.02
	return def

func _build_list() -> GrowthProducerList:
	var list := GrowthProducerList.new()
	var producers: Array[GrowthProducerDef] = [
		_producer(CurrencyTypes.Types.NUTRIENTS, "Nutrients", &"nutrient_test"),
		_producer(CurrencyTypes.Types.WATER, "Water", &"water_test"),
	]
	list.producers = producers
	return list

## Puts the player on the given level by handing them the lifetime nutrients it
## takes to be there.
func _set_level(level: int) -> void:
	_player.lifetime_nutrients = PlayerLevelCalculator.requirement(level)

# ---------------------------------------------------------------- budget

func test_a_fresh_save_has_no_points() -> void:
	assert_int(_system.level()).is_equal(0)
	assert_int(_system.available_points()).is_zero()

func test_each_level_grants_one_point() -> void:
	_set_level(4)
	assert_int(_system.level()).is_equal(4)
	assert_int(_system.available_points()).is_equal(4)

func test_investing_spends_a_point() -> void:
	_set_level(3)
	assert_bool(_system.invest(CurrencyTypes.Types.WATER)).is_true()
	assert_int(_system.invested(CurrencyTypes.Types.WATER)).is_equal(1)
	assert_int(_system.available_points()).is_equal(2)

func test_investing_is_refused_with_no_points() -> void:
	assert_bool(_system.invest(CurrencyTypes.Types.WATER)).is_false()
	assert_int(_system.invested(CurrencyTypes.Types.WATER)).is_zero()

func test_investing_is_refused_for_a_producer_that_is_not_authored() -> void:
	_set_level(3)
	assert_bool(_system.invest(CurrencyTypes.Types.CRYSTALS)).is_false()
	assert_int(_system.available_points()).is_equal(3)

func test_the_budget_counts_investments_across_every_producer() -> void:
	_set_level(5)
	assert_bool(_system.invest(CurrencyTypes.Types.NUTRIENTS)).is_true()
	assert_bool(_system.invest(CurrencyTypes.Types.WATER)).is_true()
	assert_int(_system.invested_total()).is_equal(2)
	assert_int(_system.available_points()).is_equal(3)

# ---------------------------------------------------------------- granted points

## Registers one upgrade at `level` adding `per_level` to &"level_points", so a
## test can hand out points without depending on the authored perk web.
func _grant_points(track: UpgradeSystem, per_level: float, level: int) -> void:
	var effect := UpgradeEffectDef.new()
	effect.stat = &"level_points"
	effect.op = UpgradeEffectDef.Op.ADD
	effect.scope = UpgradeEffectDef.Scope.GLOBAL
	effect.per_level = per_level
	effect.level_scaling = UpgradeEffectDef.LevelScaling.LINEAR
	var effects: Array[UpgradeEffectDef] = [effect]
	var def := UpgradeDef.new()
	def.id = &"granted_points"
	def.max_level = 0
	def.effects = effects
	track.register(def)
	for _i in level:
		assert_bool(track.buy_with_points(&"granted_points", true)).is_true()

## A system whose budget also reads the &"level_points" stat off `perks`.
func _with_perks(perks: UpgradeSystem) -> PlayerLevelSystem:
	var production := ProductionSystem.new(UpgradeSystem.new(), UpgradeSystem.new(), perks,
		ResolveContext.new())
	return PlayerLevelSystem.new(_player, _upgrades, _list, production)

func test_a_granting_upgrade_adds_points_at_level_zero() -> void:
	var perks := UpgradeSystem.new()
	_grant_points(perks, 1.0, 3)
	var system := _with_perks(perks)
	assert_int(system.level()).is_zero()
	assert_int(system.available_points()).is_equal(3)

func test_granted_points_add_to_the_level_derived_ones() -> void:
	var perks := UpgradeSystem.new()
	_grant_points(perks, 1.0, 2)
	var system := _with_perks(perks)
	_set_level(4)
	assert_int(system.available_points()).is_equal(6)

func test_granted_points_can_be_spent_like_any_other() -> void:
	var perks := UpgradeSystem.new()
	_grant_points(perks, 1.0, 2)
	var system := _with_perks(perks)
	assert_bool(system.invest(CurrencyTypes.Types.WATER)).is_true()
	assert_bool(system.invest(CurrencyTypes.Types.NUTRIENTS)).is_true()
	assert_int(system.available_points()).is_zero()
	assert_bool(system.invest(CurrencyTypes.Types.WATER)).is_false()

## Granted points count towards a doubling exactly as earned ones do - the
## doubling is measured off what has been invested, not off where it came from.
func test_granted_points_count_towards_a_doubling() -> void:
	var perks := UpgradeSystem.new()
	_grant_points(perks, 1.0, PlayerLevelSystem.LP_PER_DOUBLE)
	var system := _with_perks(perks)
	for _i in range(PlayerLevelSystem.LP_PER_DOUBLE):
		assert_bool(system.invest(CurrencyTypes.Types.WATER)).is_true()
	assert_int(system.doublings()).is_equal(1)

## Without a ProductionSystem the budget is the level alone, which is what the
## three-argument construction every other test here uses relies on.
func test_a_system_without_production_ignores_granted_points() -> void:
	_set_level(2)
	assert_int(_system.available_points()).is_equal(2)

# ---------------------------------------------------------------- doubling

func test_no_doubling_before_the_tenth_point() -> void:
	_set_level(30)
	for _i in range(PlayerLevelSystem.LP_PER_DOUBLE - 1):
		assert_bool(_system.invest(CurrencyTypes.Types.WATER)).is_true()
	assert_int(_system.doublings()).is_zero()
	assert_float(_system.global_double().to_float()).is_equal_approx(1.0, EPS)

func test_the_tenth_point_doubles_everything() -> void:
	_set_level(30)
	for _i in range(PlayerLevelSystem.LP_PER_DOUBLE):
		assert_bool(_system.invest(CurrencyTypes.Types.WATER)).is_true()
	assert_int(_system.doublings()).is_equal(1)
	assert_float(_system.global_double().to_float()).is_equal_approx(2.0, EPS)

func test_doublings_keep_compounding_every_ten_points() -> void:
	_set_level(30)
	for _i in range(PlayerLevelSystem.LP_PER_DOUBLE * 2):
		assert_bool(_system.invest(CurrencyTypes.Types.WATER)).is_true()
	assert_int(_system.doublings()).is_equal(2)
	assert_float(_system.global_double().to_float()).is_equal_approx(4.0, EPS)

## Ten points is ten points, whichever producers they went into.
func test_a_doubling_counts_points_spread_across_producers() -> void:
	_set_level(30)
	for _i in range(5):
		assert_bool(_system.invest(CurrencyTypes.Types.NUTRIENTS)).is_true()
	for _i in range(5):
		assert_bool(_system.invest(CurrencyTypes.Types.WATER)).is_true()
	assert_int(_system.doublings()).is_equal(1)

func test_points_to_the_next_doubling_counts_down() -> void:
	_set_level(30)
	assert_int(_system.points_to_next_double()).is_equal(PlayerLevelSystem.LP_PER_DOUBLE)
	assert_bool(_system.invest(CurrencyTypes.Types.WATER)).is_true()
	assert_int(_system.points_to_next_double()).is_equal(PlayerLevelSystem.LP_PER_DOUBLE - 1)

# ---------------------------------------------------------------- sync

func test_sync_tops_a_missing_doubling_up() -> void:
	_set_level(30)
	# Straight into the track, the way a save load fills it: no invest() call, so
	# nothing has kept the doubling in step.
	for _i in range(PlayerLevelSystem.LP_PER_DOUBLE * 3):
		assert_bool(_upgrades.buy_with_points(GrowthTree.invest_id(CurrencyTypes.Types.WATER),
			true)).is_true()
	assert_int(_system.doublings()).is_zero()
	_system.sync_global_double()
	assert_int(_system.doublings()).is_equal(3)

func test_sync_is_idempotent() -> void:
	_set_level(30)
	for _i in range(PlayerLevelSystem.LP_PER_DOUBLE):
		assert_bool(_system.invest(CurrencyTypes.Types.WATER)).is_true()
	_system.sync_global_double()
	_system.sync_global_double()
	assert_int(_system.doublings()).is_equal(1)

## buy_with_points only ever increments, so a level above its target is reported
## and left rather than silently corrected. Reaching it takes a hand-edited save.
func test_sync_never_takes_a_doubling_away() -> void:
	assert_bool(_upgrades.buy_with_points(GrowthTree.GLOBAL_DOUBLE_ID, true)).is_true()
	_system.sync_global_double()
	assert_int(_system.doublings()).is_equal(1)

## Daily stacks live in the same track. Counting them as investments would hand
## the player a free doubling for turning up ten days running.
func test_daily_stacks_do_not_count_towards_a_doubling() -> void:
	for _i in range(PlayerLevelSystem.LP_PER_DOUBLE * 2):
		assert_bool(_upgrades.buy_with_points(GrowthTree.daily_id(CurrencyTypes.Types.WATER),
			true)).is_true()
	assert_int(_system.invested_total()).is_zero()
	_system.sync_global_double()
	assert_int(_system.doublings()).is_zero()
