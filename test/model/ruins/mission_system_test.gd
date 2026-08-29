extends GdUnitTestSuite
## Unit tests for MissionSystem (model/ruins/gd_mission_system.gd).
##
## Built against a hand-authored two-mission list rather than the shipped data,
## so retuning a mission's duration or payouts cannot turn the rules red.
##
## The clock is injected everywhere. A mission measured in wall-clock seconds is
## exactly the thing a test cannot wait out, and the whole offline story - that a
## mission finishes while the game is closed - is a statement about two
## timestamps, which is only assertable with a clock you can move.

const EPS := 0.000001

var _player: PlayerData
var _biomes_data: BiomesData
var _upgrades: UpgradeSystem
var _prestige: UpgradeSystem
var _production: ProductionSystem
var _ctx: ResolveContext
var _data: RuinsData
var _heroes: HeroSystem
var _system: MissionSystem
var _now: float = 1000.0

func before_test() -> void:
	# Reset before every test: the clock is a plain field, and a test that jumps a
	# day forward would otherwise hand the next one a start time in the past.
	_now = 1000.0
	_player = PlayerData.new()
	_player.relics = BigNumber.from_value(0.0)
	_biomes_data = BiomesData.new()
	_biomes_data.unlock(MissionSystem.RUINS_KEY)
	_upgrades = UpgradeSystem.new()
	_prestige = UpgradeSystem.new()
	_ctx = ResolveContext.new()
	_production = ProductionSystem.new(UpgradeSystem.new(), UpgradeSystem.new(),
		_prestige, _ctx, UpgradeSystem.new(), UpgradeSystem.new(), UpgradeSystem.new(),
		UpgradeSystem.new(), _upgrades)
	_data = RuinsData.new()
	_heroes = HeroSystem.new(_data, _player, _hero_list(), _production)
	_system = MissionSystem.new(_data, _player, _biomes_data, _production, _heroes,
		_mission_list(), _prestige)
	_system.now_provider = func() -> float: return _now
	_heroes.recruit(&"digger")

# ─── Fixtures ────────────────────────────────────────────────────────────────

func _payout(currency_type: CurrencyTypes.Types, gain_stat: StringName,
		mantissa: float, exponent: int) -> MissionPayoutDef:
	var currency := CurrencyDef.new()
	currency.currency_type = currency_type
	currency.currency_name = "Test"
	var payout := MissionPayoutDef.new()
	payout.currency = currency
	payout.gain_stat = gain_stat
	payout.amount = BigNumber.new(mantissa, exponent)
	return payout

func _mission_list() -> MissionList:
	# Digger's chain is two steps, the second behind a level gate - which is the
	# whole shape of a real chain in miniature.
	var short_run := MissionDef.new()
	short_run.id = &"short_run"
	short_run.display_name = "Short Run"
	short_run.hero_id = &"digger"
	short_run.base_duration_seconds = 100.0
	short_run.min_hero_level = 1
	short_run.payouts = [_payout(CurrencyTypes.Types.RELICS, &"relic_gain", 1.0, 1)]

	var deep_run := MissionDef.new()
	deep_run.id = &"deep_run"
	deep_run.display_name = "Deep Run"
	deep_run.hero_id = &"digger"
	deep_run.base_duration_seconds = 400.0
	deep_run.min_hero_level = 3
	deep_run.payouts = [_payout(CurrencyTypes.Types.GLYPHS, &"glyph_gain", 5.0, 0)]

	# Idler's chain, so the board can hold two expeditions at once.
	var side_run := MissionDef.new()
	side_run.id = &"side_run"
	side_run.display_name = "Side Run"
	side_run.hero_id = &"idler"
	side_run.base_duration_seconds = 200.0
	side_run.min_hero_level = 1
	side_run.payouts = [_payout(CurrencyTypes.Types.RELICS, &"relic_gain", 2.0, 0)]

	var list := MissionList.new()
	list.missions = [short_run, deep_run, side_run]
	return list

## Walks digger past the first step of its chain, which is what opens the second.
func _finish_short_run() -> void:
	assert_int(_system.send(&"short_run", &"digger")).is_greater(0)
	_now += 100.0
	assert_bool(_system.collect(_data.active[0]["instance_id"])).is_true()

func _hero_list() -> HeroList:
	var currency := CurrencyDef.new()
	currency.currency_type = CurrencyTypes.Types.RELICS

	var digger := HeroDef.new()
	digger.id = &"digger"
	digger.display_name = "Digger"
	digger.speed_per_level = 0.0     # level 1 is a clean x1.0, so durations read as authored
	digger.yield_per_level = 0.0
	digger.base_level_cap = 5
	digger.recruit_currency = currency
	digger.recruit_cost = BigNumber.new(0.0, 0)
	digger.level_currency = currency
	digger.level_base_cost = BigNumber.new(0.0, 0)
	digger.level_cost_growth = 1.0

	var idler := HeroDef.new()
	idler.id = &"idler"
	idler.display_name = "Idler"
	idler.speed_per_level = 0.0
	idler.yield_per_level = 0.0
	idler.base_level_cap = 5
	idler.recruit_currency = currency
	idler.recruit_cost = BigNumber.new(0.0, 0)
	idler.level_currency = currency
	idler.level_base_cost = BigNumber.new(0.0, 0)
	idler.level_cost_growth = 1.0

	var list := HeroList.new()
	list.heroes = [digger, idler]
	return list

## Levels a stat on the mission track, the way a boost rung does.
func _grant_stat(id: StringName, stat: StringName, op: UpgradeEffectDef.Op,
		per_level: float, levels: int) -> void:
	var effect := UpgradeEffectDef.new()
	effect.stat = stat
	effect.op = op
	effect.per_level = per_level
	effect.level_scaling = UpgradeEffectDef.LevelScaling.LINEAR
	var def := UpgradeDef.new()
	def.id = id
	def.max_level = levels
	def.effects = [effect]
	_upgrades.register(def)
	for _i in levels:
		assert_bool(_upgrades.buy_with_points(id, true)).is_true()

# ─── Sending ─────────────────────────────────────────────────────────────────

func test_sending_snapshots_the_duration_and_puts_the_hero_out() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	assert_int(instance_id).is_greater(0)
	assert_int(_system.expeditions_out()).is_equal(1)
	var entry := _data.find(instance_id)
	assert_float(entry["duration"]).is_equal_approx(100.0, EPS)
	assert_float(entry["started_at"]).is_equal_approx(1000.0, EPS)

## The board is uncapped: the roster is the only limit, so a second free hero
## can always go out alongside the first.
func test_the_board_takes_as_many_expeditions_as_there_are_heroes() -> void:
	_heroes.recruit(&"idler")
	assert_int(_system.send(&"short_run", &"digger")).is_greater(0)
	assert_int(_system.send(&"side_run", &"idler")).is_greater(0)
	assert_int(_system.expeditions_out()).is_equal(2)

## Two of the same one-shot expedition out at once would pay its one-time reward
## twice. Only reachable since the board stopped being capped.
func test_the_same_expedition_cannot_be_sent_twice_at_once() -> void:
	_heroes.recruit(&"idler")
	assert_int(_system.send(&"short_run", &"digger")).is_greater(0)
	assert_bool(_system.can_send(&"short_run", &"idler")).is_false()
	assert_int(_system.send(&"short_run", &"idler")).is_equal(0)

## ...and with nobody free, there is nothing to send. That is the limit that
## replaced the slot count, and it is one the player lifts by taking another
## hero over rather than by buying a place.
func test_an_expedition_needs_a_free_hero() -> void:
	assert_int(_system.send(&"short_run", &"digger")).is_greater(0)
	assert_bool(_system.can_send(&"short_run", &"digger")).is_false()
	assert_int(_system.send(&"short_run", &"digger")).is_equal(0)

## The chain gate: the step is next in line, but its hero is not levelled far
## enough to take it.
func test_a_hero_below_the_level_gate_cannot_be_sent() -> void:
	_finish_short_run()
	assert_bool(_system.is_unlocked(&"deep_run")).is_false()
	assert_bool(_system.can_send(&"deep_run", &"digger")).is_false()
	_data.set_level(&"digger", 3)
	assert_bool(_system.is_unlocked(&"deep_run")).is_true()
	assert_bool(_system.can_send(&"deep_run", &"digger")).is_true()

## A step further along the chain than the player has walked is shut, however
## high the hero's level.
func test_a_step_out_of_chain_order_cannot_be_sent() -> void:
	_data.set_level(&"digger", 3)
	assert_bool(_system.is_unlocked(&"deep_run")).is_false()
	assert_int(_system.send(&"deep_run", &"digger")).is_equal(0)

func test_a_sealed_ruin_sends_nobody() -> void:
	_biomes_data.reset()
	assert_bool(_system.is_controlling()).is_false()
	assert_int(_system.send(&"short_run", &"digger")).is_equal(0)

# ─── The clock ───────────────────────────────────────────────────────────────

func test_a_mission_is_not_complete_before_its_duration_is_up() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 99.0
	var entry := _data.find(instance_id)
	assert_bool(_system.is_complete(entry)).is_false()
	assert_float(_system.seconds_remaining(entry)).is_equal_approx(1.0, EPS)
	assert_float(_system.progress_ratio(entry)).is_equal_approx(0.99, EPS)

func test_a_mission_completes_once_the_clock_passes_its_end() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 100.0
	var entry := _data.find(instance_id)
	assert_bool(_system.is_complete(entry)).is_true()
	assert_float(_system.seconds_remaining(entry)).is_equal_approx(0.0, EPS)

## The offline case. No tick is driven, nothing is replayed - a gap in the wall
## clock is the entire mechanism.
func test_a_gap_spanning_the_duration_finishes_the_mission_with_no_ticks() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 86400.0
	assert_bool(_system.is_complete(_data.find(instance_id))).is_true()
	assert_bool(_system.collect(instance_id)).is_true()
	assert_bool(_player.relics.equals(BigNumber.new(1.0, 1))).is_true()

func test_a_clock_moved_backwards_is_clamped_to_now() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now -= 500.0
	_system.sync_clock_rollback()
	var entry := _data.find(instance_id)
	assert_float(entry["started_at"]).is_equal_approx(_now, EPS)
	# And it now runs its authored length from here rather than being stuck.
	assert_float(_system.seconds_remaining(entry)).is_equal_approx(100.0, EPS)

func test_a_clock_moved_forwards_is_left_alone() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 50.0
	_system.sync_clock_rollback()
	assert_float(_data.find(instance_id)["started_at"]).is_equal_approx(1000.0, EPS)

# ─── Speed and reward ────────────────────────────────────────────────────────

func test_a_mission_speed_effect_shortens_the_next_send() -> void:
	_grant_stat(&"swift", &"mission_speed", UpgradeEffectDef.Op.MORE, 1.0, 1)
	assert_float(_system.duration_for(&"short_run", &"digger")).is_equal_approx(50.0, EPS)

## The snapshot contract: a boost bought while a hero is out does not move
## the errand it is already on.
func test_a_speed_boost_does_not_shorten_a_mission_already_in_flight() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_grant_stat(&"swift", &"mission_speed", UpgradeEffectDef.Op.MORE, 1.0, 1)
	assert_float(_data.find(instance_id)["duration"]).is_equal_approx(100.0, EPS)

func test_a_mission_reward_effect_raises_the_next_payout() -> void:
	_grant_stat(&"rich", &"mission_reward", UpgradeEffectDef.Op.MORE, 1.0, 1)
	var payouts := _system.payouts_for(&"short_run", &"digger")
	assert_int(payouts.size()).is_equal(1)
	var amount := BigNumber.new(float(payouts[0]["m"]), int(payouts[0]["e"]))
	assert_bool(amount.equals(BigNumber.new(2.0, 1))).is_true()

## Per-currency stats single out one kind of mission.
func test_a_currency_gain_effect_only_moves_that_currency() -> void:
	_grant_stat(&"glyphy", &"glyph_gain", UpgradeEffectDef.Op.MORE, 1.0, 1)
	var relic_payouts := _system.payouts_for(&"short_run", &"digger")
	var relics := BigNumber.new(float(relic_payouts[0]["m"]), int(relic_payouts[0]["e"]))
	assert_bool(relics.equals(BigNumber.new(1.0, 1))).is_true()
	var glyph_payouts := _system.payouts_for(&"deep_run", &"digger")
	var glyphs := BigNumber.new(float(glyph_payouts[0]["m"]), int(glyph_payouts[0]["e"]))
	assert_bool(glyphs.equals(BigNumber.from_value(10.0))).is_true()

func test_a_reward_boost_does_not_raise_a_mission_already_in_flight() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_grant_stat(&"rich", &"mission_reward", UpgradeEffectDef.Op.MORE, 1.0, 1)
	_now += 100.0
	assert_bool(_system.collect(instance_id)).is_true()
	assert_bool(_player.relics.equals(BigNumber.new(1.0, 1))).is_true()

# ─── Collecting ──────────────────────────────────────────────────────────────

func test_collecting_pays_out_frees_the_hero_and_counts_the_mission() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 100.0
	assert_bool(_system.collect(instance_id)).is_true()
	assert_bool(_player.relics.equals(BigNumber.new(1.0, 1))).is_true()
	assert_int(_system.expeditions_out()).is_equal(0)
	assert_int(_data.missions_completed).is_equal(1)
	assert_bool(_heroes.is_busy(&"digger")).is_false()

func test_collecting_moves_the_lifetime_total() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 100.0
	_system.collect(instance_id)
	assert_bool(_player.lifetime_relics.equals(BigNumber.new(1.0, 1))).is_true()

func test_an_unfinished_mission_cannot_be_collected() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 50.0
	assert_bool(_system.collect(instance_id)).is_false()
	assert_bool(_player.relics.equals(BigNumber.new(0.0, 0))).is_true()
	assert_int(_system.expeditions_out()).is_equal(1)

func test_collect_all_takes_every_finished_mission_and_leaves_the_rest() -> void:
	# Two different expeditions: the same one cannot be out twice at once.
	_heroes.recruit(&"idler")
	var first := _system.send(&"short_run", &"digger")
	_now += 60.0
	var second := _system.send(&"side_run", &"idler")
	_now += 50.0   # first is 110s in and done, second only 50s of its 200s
	assert_int(_system.completed_count()).is_equal(1)
	assert_int(_system.collect_all()).is_equal(1)
	assert_bool(_data.find(first).is_empty()).is_true()
	assert_bool(_data.find(second).is_empty()).is_false()

func test_the_tally_is_projected_onto_player_data() -> void:
	var instance_id := _system.send(&"short_run", &"digger")
	_now += 100.0
	_system.collect(instance_id)
	assert_int(_player.missions_completed).is_equal(1)

func test_sync_rebuilds_the_projection_after_a_load() -> void:
	_data.missions_completed = 7
	_player.missions_completed = 0
	_system.sync_missions_completed()
	assert_int(_player.missions_completed).is_equal(7)

# ─── Walking a chain ─────────────────────────────────────────────────────────

## A chain is walked in order, and where a hero stands in it is how many of its
## own expeditions are home.
func test_a_chain_is_walked_one_step_at_a_time() -> void:
	assert_int(_system.chain_length(&"digger")).is_equal(2)
	assert_int(_system.chain_position(&"digger")).is_zero()
	assert_str(String(_system.next_step(&"digger").id)).is_equal("short_run")

	_finish_short_run()
	assert_int(_system.chain_position(&"digger")).is_equal(1)
	assert_str(String(_system.next_step(&"digger").id)).is_equal("deep_run")

func test_a_finished_chain_offers_nothing() -> void:
	_finish_short_run()
	_data.set_level(&"digger", 3)
	assert_int(_system.send(&"deep_run", &"digger")).is_greater(0)
	_now += 400.0
	assert_bool(_system.collect(_data.active[0]["instance_id"])).is_true()
	assert_int(_system.chain_position(&"digger")).is_equal(2)
	assert_object(_system.next_step(&"digger")).is_null()
	assert_str(String(_system.sendable_step(&"digger"))).is_empty()

## Only the chain's own hero. Nothing on screen offers another, but the model is
## what makes that true rather than the screen.
func test_another_heros_expedition_is_refused() -> void:
	_heroes.recruit(&"idler")
	assert_bool(_system.can_send(&"short_run", &"idler")).is_false()
	assert_int(_system.send(&"short_run", &"idler")).is_zero()

## What the Send button reads: the one step this hero could start right now.
func test_the_sendable_step_is_the_next_one_it_can_actually_take() -> void:
	assert_str(String(_system.sendable_step(&"digger"))).is_equal("short_run")
	_finish_short_run()
	# Next in line, but behind a level it has not reached.
	assert_str(String(_system.sendable_step(&"digger"))).is_empty()
	_data.set_level(&"digger", 3)
	assert_str(String(_system.sendable_step(&"digger"))).is_equal("deep_run")

func test_a_hero_already_out_has_no_sendable_step() -> void:
	_system.send(&"short_run", &"digger")
	assert_str(String(_system.sendable_step(&"digger"))).is_empty()

func test_an_unrecruited_hero_has_no_sendable_step() -> void:
	assert_str(String(_system.sendable_step(&"idler"))).is_empty()

## The level a step still wants, for the line the card shows while it waits.
func test_levels_until_unlock_counts_down_to_the_gate() -> void:
	assert_int(_system.levels_until_unlock(&"deep_run")).is_equal(2)
	_data.set_level(&"digger", 3)
	assert_int(_system.levels_until_unlock(&"deep_run")).is_zero()
