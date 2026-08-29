extends GdUnitTestSuite
## Unit tests for the expedition reward track - the permanent upgrade finishing
## an expedition grants (model/ruins/gd_expedition_reward_tree.gd, and
## MissionSystem.sync_expedition_rewards()).
##
## Built against a hand-authored list rather than the shipped data, so retuning
## what an expedition grants cannot turn the rules red.
##
## The point being asserted throughout is that the track is a *projection* of
## RuinsData.completed_expeditions and never a second record of it: granting is
## idempotent, a load rebuilds the whole track, and a prestige cannot touch it.

const EPS := 0.000001

var _player: PlayerData
var _biomes_data: BiomesData
var _prestige: UpgradeSystem
var _rewards: UpgradeSystem
var _production: ProductionSystem
var _ctx: ResolveContext
var _data: RuinsData
var _heroes: HeroSystem
var _list: MissionList
var _system: MissionSystem
var _now: float = 1000.0

func before_test() -> void:
	_now = 1000.0
	_player = PlayerData.new()
	_biomes_data = BiomesData.new()
	_biomes_data.unlock(MissionSystem.RUINS_KEY)
	_prestige = UpgradeSystem.new()
	_rewards = UpgradeSystem.new()
	_ctx = ResolveContext.new()
	_production = ProductionSystem.new(UpgradeSystem.new(), UpgradeSystem.new(),
		_prestige, _ctx, UpgradeSystem.new(), UpgradeSystem.new(), UpgradeSystem.new(),
		UpgradeSystem.new(), UpgradeSystem.new(), [], _rewards)
	_data = RuinsData.new()
	_list = _mission_list()
	for def in ExpeditionRewardTree.build(_list):
		_rewards.register(def)
	_heroes = HeroSystem.new(_data, _player, _hero_list(), _production)
	_system = MissionSystem.new(_data, _player, _biomes_data, _production, _heroes,
		_list, _prestige, _rewards)
	_system.now_provider = func() -> float: return _now
	_heroes.recruit(&"digger")
	_system.sync_expedition_rewards()

# ─── Fixtures ────────────────────────────────────────────────────────────────

func _payout() -> MissionPayoutDef:
	var currency := CurrencyDef.new()
	currency.currency_type = CurrencyTypes.Types.RELICS
	currency.currency_name = "Test"
	var payout := MissionPayoutDef.new()
	payout.currency = currency
	payout.gain_stat = &"relic_gain"
	payout.amount = BigNumber.new(1.0, 0)
	return payout

func _reward(stat: StringName, op: UpgradeEffectDef.Op, per_level: float) -> UpgradeEffectDef:
	var effect := UpgradeEffectDef.new()
	effect.stat = stat
	effect.op = op
	effect.per_level = per_level
	effect.level_scaling = UpgradeEffectDef.LevelScaling.LINEAR
	return effect

func _mission_list() -> MissionList:
	# Doubles nutrient production, so the assertion is a number the player would
	# recognise rather than a level count.
	var dig := MissionDef.new()
	dig.id = &"dig"
	dig.hero_id = &"digger"
	dig.display_name = "Dig"
	dig.base_duration_seconds = 100.0
	dig.min_hero_level = 1
	dig.payouts = [_payout()]
	dig.rewards = [_reward(&"node_production", UpgradeEffectDef.Op.MORE, 1.0)]

	var farm := MissionDef.new()
	farm.id = &"farm"
	farm.display_name = "Farm"
	farm.is_farm = true
	farm.base_duration_seconds = 50.0
	farm.min_hero_level = 1
	farm.requires_mission_id = &"dig"
	farm.hero_id = &""
	farm.payouts = [_payout()]

	var list := MissionList.new()
	list.missions = [dig, farm]
	return list

func _hero_list() -> HeroList:
	var currency := CurrencyDef.new()
	currency.currency_type = CurrencyTypes.Types.RELICS

	var digger := HeroDef.new()
	digger.id = &"digger"
	digger.display_name = "Digger"
	digger.speed_per_level = 0.0
	digger.yield_per_level = 0.0
	digger.base_level_cap = 5
	digger.recruit_currency = currency
	digger.recruit_cost = BigNumber.new(0.0, 0)
	digger.level_currency = currency
	digger.level_base_cost = BigNumber.new(0.0, 0)
	digger.level_cost_growth = 1.0

	var list := HeroList.new()
	list.heroes = [digger]
	return list

## Sends the expedition, waits it out and brings it home.
func _run_expedition() -> void:
	assert_int(_system.send(&"dig", &"digger")).is_greater(0)
	_now += 100.0
	assert_bool(_system.collect(_first_instance())).is_true()

func _first_instance() -> int:
	return int(_data.active[0]["instance_id"])

func _node_production() -> float:
	return _production.stack(&"node_production", BigNumber.from_value(1.0)).to_float()

# ─── Granting ────────────────────────────────────────────────────────────────

func test_a_fresh_board_grants_nothing() -> void:
	assert_int(_rewards.level(&"dig")).is_zero()
	assert_float(_node_production()).is_equal_approx(1.0, EPS)

func test_collecting_an_expedition_grants_its_reward() -> void:
	_run_expedition()
	assert_int(_rewards.level(&"dig")).is_equal(1)

## The whole point of the reward: it has to reach the colony, through the same
## stack every other upgrade resolves through.
func test_the_reward_reaches_production() -> void:
	assert_float(_node_production()).is_equal_approx(1.0, EPS)
	_run_expedition()
	assert_float(_node_production()).is_equal_approx(2.0, EPS)

## A grant is not a purchase, so it must not move the count of levels bought -
## which the biome XP sources and the balance tools read.
func test_granting_does_not_count_as_a_purchase() -> void:
	_run_expedition()
	assert_int(_rewards.lifetime_levels).is_zero()

# ─── One-shot ────────────────────────────────────────────────────────────────

func test_a_collected_expedition_does_not_open_again() -> void:
	_run_expedition()
	assert_bool(_system.is_completed(&"dig")).is_true()
	assert_bool(_system.is_unlocked(&"dig")).is_false()
	assert_bool(_system.can_send(&"dig", &"digger")).is_false()

## Two collects of the same expedition would be two grants of a permanent
## upgrade. The entry is removed on the first, so this is a guard against the
## list itself gaining a duplicate.
func test_the_ladder_records_an_expedition_once() -> void:
	_run_expedition()
	_data.mark_expedition_done(&"dig")
	assert_int(_data.completed_expeditions.size()).is_equal(1)

func test_finishing_an_expedition_opens_the_farm_that_waits_on_it() -> void:
	assert_bool(_system.is_unlocked(&"farm")).is_false()
	_run_expedition()
	assert_bool(_system.is_unlocked(&"farm")).is_true()

# ─── The projection ──────────────────────────────────────────────────────────

## Re-syncing must be idempotent: it runs after every collect and again on every
## load, and a grant that stacked would double the reward on the second call.
func test_re_syncing_does_not_stack_the_grant() -> void:
	_run_expedition()
	_system.sync_expedition_rewards()
	_system.sync_expedition_rewards()
	assert_int(_rewards.level(&"dig")).is_equal(1)
	assert_float(_node_production()).is_equal_approx(2.0, EPS)

## The track holds no save data of its own, so a load has to rebuild it from the
## list of expeditions that came back.
func test_a_load_rebuilds_the_track_from_the_saved_expeditions() -> void:
	_run_expedition()
	var saved := _data.to_save()

	var fresh := RuinsData.new()
	fresh.load_from_save(saved)
	var track := UpgradeSystem.new()
	for def in ExpeditionRewardTree.build(_list):
		track.register(def)
	var system := MissionSystem.new(fresh, PlayerData.new(), _biomes_data, _production,
		_heroes, _list, _prestige, track)
	system.sync_expedition_rewards()

	assert_int(track.level(&"dig")).is_equal(1)

## The mirror of the above: an expedition missing from the list loses its reward
## with it, rather than the track keeping a level nothing accounts for.
func test_the_track_follows_the_list_back_down() -> void:
	_run_expedition()
	_data.completed_expeditions.clear()
	_system.sync_expedition_rewards()
	assert_int(_rewards.level(&"dig")).is_zero()
	assert_float(_node_production()).is_equal_approx(1.0, EPS)

## A farm loops, so a reward on one could be earned over and over. The tree
## refuses to register it at all.
func test_a_farm_is_never_registered_for_a_reward() -> void:
	var farm := MissionDef.new()
	farm.id = &"greedy_farm"
	farm.is_farm = true
	farm.rewards = [_reward(&"node_production", UpgradeEffectDef.Op.MORE, 1.0)]
	var list := MissionList.new()
	list.missions = [farm]

	# The push_error this raises is the point: the authored data is the mistake.
	assert_int(ExpeditionRewardTree.build(list).size()).is_zero()
